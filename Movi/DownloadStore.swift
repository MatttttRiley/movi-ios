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
    var jobId: String?
    var downloadedAt: Date?

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
        guard let error else { return } // success already handled above
        let handler = onComplete.removeValue(forKey: task.taskIdentifier)
        onProgress.removeValue(forKey: task.taskIdentifier)
        DispatchQueue.main.async { handler?(nil, error) }
    }
}

// MARK: - Store

/// Offline downloads. Flow per item:
/// app_download_start -> poll download_status -> fetch single-use dl_url
/// -> save into Documents/Downloads. Metadata persists in downloads.json.
@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    @Published private(set) var items: [DownloadItem] = []

    private let delegate = DownloadDelegate()
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
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
        // Jobs/tokens don't survive a relaunch; anything unfinished failed.
        items = saved.map { item in
            var it = item
            if it.status != .done {
                it.status = .failed
                it.progress = 0
            }
            return it
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: Self.metaURL)
        }
    }

    // MARK: - Public API

    func item(kind: String, libraryId: Int) -> DownloadItem? {
        items.first { $0.kind == kind && $0.libraryId == libraryId }
    }

    func start(kind: String, libraryId: Int, title: String, posterUrl: String?) {
        // Drop a previous failed attempt for the same title before retrying.
        items.removeAll { $0.kind == kind && $0.libraryId == libraryId && $0.status == .failed }
        guard item(kind: kind, libraryId: libraryId) == nil else { return }
        let item = DownloadItem(
            id: UUID().uuidString, kind: kind, libraryId: libraryId,
            title: title, posterUrl: posterUrl, filename: "",
            status: .preparing, progress: 0, sizeBytes: nil,
            jobId: nil, downloadedAt: nil
        )
        items.insert(item, at: 0)
        save()
        Task { await runDownload(id: item.id) }
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

    private func runDownload(id: String) async {
        guard let item = items.first(where: { $0.id == id }) else { return }
        do {
            // 1. Ask the site to stage the file on the worker.
            struct StartResp: Decodable {
                let ok: Bool
                let job_id: String?
                let error: String?
            }
            let data = try await APIClient.shared.postForm(
                "app_download_start",
                fields: ["kind": item.kind, "id": "\(item.libraryId)"]
            )
            let started = try JSONDecoder().decode(StartResp.self, from: data)
            guard let jobId = started.job_id else {
                fail(id, started.error ?? "Couldn't start the download.")
                return
            }
            update(id: id) { $0.jobId = jobId }

            // 2. Poll until the worker hands us the single-use file URL.
            struct StatusResp: Decodable {
                let status: String?
                let progress: Double?
                let dl_url: String?
                let filename: String?
                let error: String?
            }
            var dlUrl: String?
            var filename = "video.mp4"
            for _ in 0..<120 { // ~6 minutes of "preparing" max
                try await Task.sleep(nanoseconds: 3_000_000_000)
                let st: StatusResp = try await APIClient.shared.get(
                    "download_status", params: ["job_id": jobId])
                if let p = st.progress {
                    let s: DownloadItem.Status = (st.status == "downloading") ? .downloading : .preparing
                    update(id: id) { $0.status = s; $0.progress = p * 0.5 }
                }
                if st.status == "done", let u = st.dl_url {
                    dlUrl = u
                    if let fn = st.filename, !fn.isEmpty { filename = fn }
                    break
                }
                if st.status == "failed" || st.status == "cancelled" {
                    fail(id, st.error ?? "The download failed.")
                    return
                }
            }
            guard let dlUrl, let url = URL(string: dlUrl) else {
                fail(id, "Timed out preparing the download.")
                return
            }

            // 3. Fetch the file (single GET consumes the one-time token).
            try await fetchFile(id: id, from: url, filename: filename)
        } catch {
            fail(id, (error as? APIError)?.localizedDescription ?? "Download failed.")
        }
    }

    private func fetchFile(id: String, from url: URL, filename: String) async throws {
        let safe = filename.replacingOccurrences(of: "/", with: "_")
        let dest = Self.downloadsDir.appendingPathComponent(safe)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let task = session.downloadTask(with: url)
            let tid = task.taskIdentifier
            delegate.onProgress[tid] = { [weak self] p in
                Task { @MainActor [weak self] in
                    self?.update(id: id) { $0.status = .downloading; $0.progress = 0.5 + p * 0.5 }
                }
            }
            delegate.onComplete[tid] = { [weak self] location, error in
                Task { @MainActor [weak self] in
                    guard let self else { cont.resume(throwing: APIError.network); return }
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    guard let location else {
                        cont.resume(throwing: APIError.network)
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
                            $0.filename = safe
                            $0.sizeBytes = size
                            $0.downloadedAt = Date()
                        }
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            task.resume()
        }
    }

    private func fail(_ id: String, _ message: String) {
        update(id: id) { $0.status = .failed; $0.progress = 0 }
        lastError = message
    }

    @Published var lastError: String = ""
}
