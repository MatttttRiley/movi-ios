import Foundation

// MARK: - Model

struct DownloadItem: Codable, Identifiable {
    var id: String
    let kind: String // "movie" | "episode"
    let libraryId: Int
    let title: String
    let posterUrl: String?
    var filename: String
    var status: Status
    var progress: Double
    var sizeBytes: Int64?
    var downloadedAt: Date?
    var streamUrl: String?

    enum Status: String, Codable {
        case preparing, downloading, done, failed
    }

    var localURL: URL? {
        guard status == .done, !filename.isEmpty else { return nil }
        let url = DownloadStore.downloadsDir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var statusLabel: String {
        switch status {
        case .preparing: return "Preparing…"
        case .downloading: return "\(Int(progress * 100))%"
        case .done: return sizeLabel ?? "Downloaded"
        case .failed: return "Failed — tap to retry"
        }
    }

    var sizeLabel: String? {
        guard let b = sizeBytes, b > 0 else { return nil }
        if b >= 1_073_741_824 { return String(format: "%.1f GB", Double(b) / 1_073_741_824) }
        return String(format: "%.0f MB", Double(b) / 1_048_576)
    }
}

// MARK: - URLSession delegate (progress + completion)

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: [Int: (Double) -> Void] = [:]
    var onComplete: [Int: (URL?, Error?) -> Void] = [:]

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let handler = onProgress[downloadTask.taskIdentifier]
        DispatchQueue.main.async { handler?(p) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let handler = onComplete.removeValue(forKey: downloadTask.taskIdentifier)
        onProgress.removeValue(forKey: downloadTask.taskIdentifier)
        DispatchQueue.main.async { handler?(location, nil) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error else { return }
        let handler = onComplete.removeValue(forKey: task.taskIdentifier)
        onProgress.removeValue(forKey: task.taskIdentifier)
        DispatchQueue.main.async { handler?(nil, error) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            DownloadStore.shared.backgroundCompletionHandler?()
            DownloadStore.shared.backgroundCompletionHandler = nil
        }
    }
}

// MARK: - Store
//
// Downloads fetch the title's own stream_url directly, with a BACKGROUND
// session, so a 2 GB movie keeps downloading when the app goes to the
// background and can resume after a relaunch. The old store used a
// foreground session plus server endpoints (app_download_start /
// download_status) that do not exist on the live server, and marked
// anything unfinished at relaunch as failed — every large download was
// doomed. Metadata persists in downloads.json; files in Documents/Downloads.

@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    @Published private(set) var items: [DownloadItem] = []
    @Published var lastError: String = ""
    var backgroundCompletionHandler: (() -> Void)?

    private let delegate = DownloadDelegate()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.philbert.movi.downloads")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    static var downloadsDir: URL {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var metaURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("downloads.json")
    }

    private init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.metaURL),
              let saved = try? JSONDecoder().decode([DownloadItem].self, from: data)
        else { return }
        // A background task survives relaunch, so do NOT mark unfinished
        // items failed here. Items whose file is gone are the only dead ones.
        items = saved.filter { item in
            item.status != .done || item.localURL != nil
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: Self.metaURL, options: .atomic)
        }
    }

    // MARK: - Public API

    func item(kind: String, libraryId: Int) -> DownloadItem? {
        items.first { $0.kind == kind && $0.libraryId == libraryId }
    }

    func start(kind: String, libraryId: Int, title: String, posterUrl: String?, streamUrl: String?) {
        items.removeAll { $0.kind == kind && $0.libraryId == libraryId && $0.status == .failed }
        guard item(kind: kind, libraryId: libraryId) == nil else { return }
        guard let streamUrl, let url = URL(string: streamUrl), !streamUrl.isEmpty else {
            lastError = "This title has no video file to download yet."
            return
        }
        let item = DownloadItem(
            id: UUID().uuidString, kind: kind, libraryId: libraryId,
            title: title, posterUrl: posterUrl, filename: "",
            status: .preparing, progress: 0, sizeBytes: nil,
            downloadedAt: nil, streamUrl: streamUrl
        )
        items.insert(item, at: 0)
        save()
        Task { await runDownload(id: item.id, url: url) }
    }

    func retry(_ item: DownloadItem) {
        start(kind: item.kind, libraryId: item.libraryId, title: item.title,
              posterUrl: item.posterUrl, streamUrl: item.streamUrl)
    }

    func delete(_ item: DownloadItem) {
        if !item.filename.isEmpty {
            try? FileManager.default.removeItem(
                at: Self.downloadsDir.appendingPathComponent(item.filename))
        }
        items.removeAll { $0.id == item.id }
        save()
    }

    var totalBytes: Int64 {
        items.compactMap { $0.sizeBytes }.reduce(0, +)
    }

    // MARK: - Internals

    private func update(id: String, _ mutate: (inout DownloadItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[i])
        save()
    }

    private func runDownload(id: String, url: URL) async {
        guard items.first(where: { $0.id == id }) != nil else { return }
        // Unique filename per title, so two titles can never overwrite
        // each other (the old code used the server filename as-is).
        let filename = "\(id).mp4"
        do {
            try await fetchFile(id: id, from: url, filename: filename)
        } catch {
            fail(id, (error as? APIError)?.localizedDescription ?? "Download failed.")
        }
    }

    private func fetchFile(id: String, from url: URL, filename: String) async throws {
        let dest = Self.downloadsDir.appendingPathComponent(filename)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = session.downloadTask(with: url)
            let tid = task.taskIdentifier
            delegate.onProgress[tid] = { [weak self] p in
                Task { @MainActor [weak self] in
                    self?.update(id: id) { $0.status = .downloading; $0.progress = p }
                }
            }
            delegate.onComplete[tid] = { [weak self] location, error in
                Task { @MainActor [weak self] in
                    guard let self else { cont.resume(throwing: APIError.network("Couldn't reach the server.")); return }
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    guard let location else {
                        cont.resume(throwing: APIError.network("Couldn't reach the server."))
                        return
                    }
                    do {
                        if FileManager.default.fileExists(atPath: dest.path) {
                            try FileManager.default.removeItem(at: dest)
                        }
                        try FileManager.default.moveItem(at: location, to: dest)
                        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                        self.update(id: id) {
                            $0.status = .done
                            $0.progress = 1
                            $0.filename = filename
                            $0.sizeBytes = size
                            $0.downloadedAt = Date()
                        }
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            update(id: id) { $0.status = .downloading }
            task.resume()
        }
    }

    private func fail(_ id: String, _ message: String) {
        update(id: id) { $0.status = .failed; $0.progress = 0 }
        lastError = message
    }
}
