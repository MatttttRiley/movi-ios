import SwiftUI
import AVKit
import GoogleCast

// MARK: - Loader: resolves kind+id -> stream URL, then hands off to the player.
//
// Live API facts: movie detail is { movie: TitleItem } with stream_url
// and position; show detail episodes carry stream_url directly. There is
// no episode detail endpoint and no playback object — the old loader
// called an endpoint that does not exist for every episode tap.

struct PlayerLoader: View {
    @State private var kind: String
    @State private var itemId: Int
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var streamUrl: URL?
    @State private var startAt: Double = 0
    @State private var mediaTitle = ""
    @State private var error = ""
    @State private var reloadToken = UUID()
    @State private var lastPosition: Double = 0
    @State private var lastDuration: Double = 0
    @ObservedObject private var cast = CastController.shared

    private let directUrl: String?
    private let displayTitle: String?

    init(kind: String, itemId: Int, directUrl: String? = nil, displayTitle: String? = nil) {
        _kind = State(initialValue: kind)
        _itemId = State(initialValue: itemId)
        self.directUrl = directUrl
        self.displayTitle = displayTitle
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if cast.isCasting {
                // Local playback is paused (PlayerView dismantles) while
                // the receiver plays. Ending the session rebuilds it below
                // from the receiver's last position.
                CastingView(title: mediaTitle, deviceName: cast.deviceName)
            } else if let streamUrl {
                PlayerView(
                    url: streamUrl,
                    startAt: cast.resumePosition > 1 ? cast.resumePosition : startAt,
                    onProgress: reportProgress,
                    onEnded: playNext,
                    onFailed: { msg in error = msg }
                )
                .id(streamUrl) // New URL = new player. Without this, up-next
                .ignoresSafeArea() // kept playing the previous video, because
                // the representable never swapped its player item.
                .onAppear {
                    CastController.shared.setPendingMedia(
                        url: streamUrl, title: mediaTitle, startAt: startAt)
                }
            } else if !error.isEmpty {
                VStack(spacing: 16) {
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Button("Try Again") { reloadToken = UUID() }
                        .buttonStyle(.borderedProminent)
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white)
                }
                .padding(32)
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: reloadToken) { await load() }
        .onChange(of: cast.isCasting) { _, nowCasting in
            // Session ended: keep the receiver's position so the final
            // report on disappear resumes from it even if local playback
            // never restarts before the screen closes.
            if !nowCasting, cast.resumePosition > 0 {
                lastPosition = cast.resumePosition
            }
        }
        .onDisappear {
            // Final progress report so closing mid-video still resumes.
            if lastDuration > 0, lastPosition > 0 {
                Task { await app.reportProgress(kind: kind, id: itemId, position: lastPosition, duration: lastDuration) }
            }
        }
    }

    // MARK: - Load

    private func load() async {
        streamUrl = nil
        error = ""
        do {
            if let directUrl, let u = URL(string: directUrl) {
                streamUrl = u
                startAt = 0
                mediaTitle = displayTitle ?? ""
                await app.markHistory(movieId: kind == "movie" ? itemId : 0)
                return
            }
            if kind == "movie" {
                let r: MovieDetailResponse = try await APIClient.shared.get("movie", params: ["id": "\(itemId)"])
                guard let m = r.movie, let f = m.streamUrl, let u = URL(string: f), !f.isEmpty else {
                    error = "This title has no video file yet."
                    return
                }
                streamUrl = u
                startAt = Double(m.positionSeconds ?? 0)
                mediaTitle = m.title
                await app.markHistory(movieId: m.id)
            } else {
                // No episode endpoint exists: episodes are only playable
                // via the show detail's stream_url, passed as directUrl.
                error = "This episode couldn't be loaded. Open it from its show page."
            }
        } catch let e as APIError {
            error = e.localizedDescription
        } catch {
            self.error = "Couldn't load the video."
        }
    }

    // MARK: - Progress reporting (live field names)

    private func reportProgress(position: Double, duration: Double) {
        lastPosition = position
        lastDuration = duration
        Task {
            await app.reportProgress(kind: kind, id: itemId, position: position, duration: duration)
        }
    }

    // MARK: - Playback ended
    //
    // No up-next: the server's show response carries no next-episode
    // info, so inventing one would play the wrong episode. End -> dismiss.

    private func playNext() {
        dismiss()
    }
}

// MARK: - Casting screen (system styling, no custom chrome)
//
// Shown instead of the local player while a Cast session is active.
// Disconnect ends the session; PlayerLoader then rebuilds local playback.

struct CastingView: View {
    let title: String
    let deviceName: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Casting\(deviceName.map { " to \($0)" } ?? "")")
                .font(.headline)
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("Playback continues on your TV. Disconnect to resume here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Disconnect") {
                CastController.shared.disconnect()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}

// MARK: - Native player (AVPlayerViewController, system controls)

struct PlayerView: UIViewControllerRepresentable {
    let url: URL
    let startAt: Double
    var onProgress: (Double, Double) -> Void = { _, _ in }
    var onEnded: () -> Void = {}
    var onFailed: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        // HIG audio: explicitly initiated media uses the Playback category
        // (movie mode, AirPlay allowed), so it plays in silent mode, pauses
        // on headphone disconnect, and reroutes like system media.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .moviePlayback, options: [.allowAirPlay])
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        vc.entersFullScreenWhenPlaybackBegins = true
        vc.exitsFullScreenWhenPlaybackEnds = true
        vc.allowsPictureInPicturePlayback = true

        // Cast button: the SDK's own button, placed over the video via
        // contentOverlayView (the system player has no SwiftUI toolbar to
        // host it). Tapping it opens the Cast device picker; picking a
        // device starts a session and PlayerLoader swaps to the casting
        // screen. It sits behind the player's own controls when they are
        // visible, and over the video when they are hidden.
        if let overlay = vc.contentOverlayView {
            let castButton = GCKUICastButton(frame: .zero)
            castButton.translatesAutoresizingMaskIntoConstraints = false
            castButton.tintColor = .white
            overlay.addSubview(castButton)
            NSLayoutConstraint.activate([
                castButton.widthAnchor.constraint(equalToConstant: 44),
                castButton.heightAnchor.constraint(equalToConstant: 44),
                castButton.topAnchor.constraint(
                    equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 8),
                castButton.trailingAnchor.constraint(
                    equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            ])
        }

        let interval = CMTime(seconds: 10, preferredTimescale: 600)
        context.coordinator.progressToken = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak player] _ in
            guard let player = player, let item = player.currentItem else { return }
            let pos = player.currentTime().seconds
            let dur = item.duration.seconds
            if pos.isFinite, dur.isFinite, dur > 0, pos > 0 {
                self.onProgress(pos, dur)
            }
        }
        let center = NotificationCenter.default
        center.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.playbackEnded),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        center.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.playbackFailed),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: player.currentItem
        )

        if startAt > 1 {
            // Default seek tolerance: exact seeks (.zero) are slow and can
            // fail on streamed files; the player snaps to the nearest
            // keyframe and starts promptly.
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600)) { _ in
                player.play()
            }
        } else {
            player.play()
        }
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // The .id(url) in PlayerLoader recreates this view for a new URL,
        // so update never needs to swap items mid-flight.
    }

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

        @objc func playbackFailed(_ note: Notification) {
            let msg = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            parent.onFailed(msg ?? "This video failed to play. Check your connection and try again.")
        }
    }
}
