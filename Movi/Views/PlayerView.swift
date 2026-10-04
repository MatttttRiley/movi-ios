import SwiftUI
import AVKit

// MARK: - Loader: resolves kind+id -> stream URL, then hands off to the player.

struct PlayerLoader: View {
    @State private var kind: String
    @State private var itemId: Int
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var streamUrl: URL?
    @State private var startAt: Double = 0
    @State private var mediaTitle = ""
    @State private var next: NextRef?
    @State private var error = ""
    @State private var reloadToken = UUID()

    init(kind: String, itemId: Int) {
        _kind = State(initialValue: kind)
        _itemId = State(initialValue: itemId)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let streamUrl {
                PlayerView(
                    url: streamUrl,
                    startAt: startAt,
                    onProgress: reportProgress,
                    onEnded: playNext
                )
                .ignoresSafeArea()
            } else if !error.isEmpty {
                VStack(spacing: 16) {
                    Text(error).foregroundColor(.white).multilineTextAlignment(.center)
                    Button("Close") { dismiss() }.foregroundColor(.moviAccent)
                }
                .padding(32)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: reloadToken) { await load() }
    }

    // MARK: - Load

    private func load() async {
        streamUrl = nil
        error = ""
        do {
            if kind == "movie" {
                let m: MovieDetail = try await APIClient.shared.get("movie", params: ["id": "\(itemId)"])
                guard let f = m.playback?.fileUrl, let u = URL(string: f) else {
                    error = m.playback?.error ?? "This title has no video file yet."
                    return
                }
                streamUrl = u
                startAt = m.playback?.resumeHintSec ?? 0
                mediaTitle = m.title
                next = nil
                markHistory(movieId: m.id, episodeId: 0)
            } else {
                let e: EpisodeDetail = try await APIClient.shared.get("episode", params: ["id": "\(itemId)"])
                guard let f = e.playback?.fileUrl, let u = URL(string: f) else {
                    error = e.playback?.error ?? "This episode has no video file yet."
                    return
                }
                streamUrl = u
                startAt = e.playback?.resumeHintSec ?? 0
                mediaTitle = [e.showTitle, e.title].compactMap { $0 }.joined(separator: " — ")
                next = e.next
                markHistory(movieId: 0, episodeId: e.id)
            }
        } catch let e as APIError {
            error = e.localizedDescription
        } catch {
            error = "Couldn't load the video."
        }
    }

    // MARK: - Progress reporting

    private func reportProgress(position: Double, duration: Double) {
        let fields: [String: String]
        if kind == "movie" {
            fields = ["movie_id": "\(itemId)"]
        } else {
            fields = ["episode_id": "\(itemId)"]
        }
        Task {
            _ = try? await APIClient.shared.postForm("progress", fields: app.csrfFields(
                fields.merging(["position_seconds": "\(Int(position))",
                                "duration_seconds": "\(Int(duration))"]) { a, _ in a }
            ))
        }
    }

    private func markHistory(movieId: Int, episodeId: Int) {
        var fields = [String: String]()
        if movieId > 0 { fields["movie_id"] = "\(movieId)" }
        if episodeId > 0 { fields["episode_id"] = "\(episodeId)" }
        Task {
            _ = try? await APIClient.shared.postForm("history_add", fields: app.csrfFields(fields))
        }
    }

    // MARK: - Up next

    private func playNext() {
        if let n = next {
            kind = "episode"
            itemId = n.id
            reloadToken = UUID()
        } else {
            dismiss()
        }
    }
}

// MARK: - Native player (AVPlayerViewController)

struct PlayerView: UIViewControllerRepresentable {
    let url: URL
    let startAt: Double
    var onProgress: (Double, Double) -> Void = { _, _ in }
    var onEnded: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        vc.entersFullScreenWhenPlaybackBegins = true
        vc.exitsFullScreenWhenPlaybackEnds = true

        let interval = CMTime(seconds: 15, preferredTimescale: 600)
        context.coordinator.progressToken = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak player] _ in
            guard let player = player,
                  let item = player.currentItem else { return }
            let pos = player.currentTime().seconds
            let dur = item.duration.seconds
            if pos.isFinite, dur.isFinite, dur > 0, pos > 0 {
                self.onProgress(pos, dur)
            }
        }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.playbackEnded),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )

        if startAt > 1 {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero) { _ in
                player.play()
            }
        } else {
            player.play()
        }
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        if let token = coordinator.progressToken {
            vc.player?.removeTimeObserver(token)
        }
        NotificationCenter.default.removeObserver(coordinator)
        vc.player?.pause()
    }

    final class Coordinator: NSObject {
        let parent: PlayerView
        var progressToken: Any?

        init(_ parent: PlayerView) {
            self.parent = parent
        }

        @objc func playbackEnded() {
            parent.onEnded()
        }
    }
}
