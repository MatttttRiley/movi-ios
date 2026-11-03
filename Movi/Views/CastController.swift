import Foundation
import GoogleCast

// MARK: - Google Cast sender
//
// The Cast SDK ships no official Swift Package Manager distribution, so the
// project depends on the community SPM wrapper SRGSSR/google-cast-sdk
// (GoogleCast xcframework, 4.8.x). It exposes the same GoogleCast module
// and API as the official SDK. Default media receiver CC1AD845 is the
// starting point; a custom receiver app ID can replace it later without
// touching the player code.
//
// Behaviour contract with PlayerLoader:
//  - PlayerLoader registers the current title as pending media. When the
//    user picks a device from the Cast button, didStartSession loads that
//    media onto the receiver and PlayerLoader swaps local playback for the
//    casting screen.
//  - When the session ends, the receiver's last position (if any) is kept
//    as resumePosition and PlayerLoader rebuilds local AVPlayer playback
//    from it. Progress reporting resumes once local playback restarts.

final class CastController: NSObject, ObservableObject {
    static let shared = CastController()

    /// The default media receiver. Replace with a custom receiver app ID
    /// when one exists; nothing else in the app needs to change.
    static let receiverAppID = "CC1AD845"

    @Published private(set) var isCasting = false
    @Published private(set) var deviceName: String?
    @Published private(set) var resumePosition: Double = 0

    private struct PendingMedia {
        let url: URL
        let title: String
        let startAt: Double
    }

    private var pendingMedia: PendingMedia?
    private var didRegisterListener = false
    private static var didConfigure = false

    private override init() {
        super.init()
    }

    /// Call once, early in app launch (AppDelegate). Calling it twice is a
    /// no-op: GCKCastContext may only be given its options once.
    static func configure() {
        guard !didConfigure else { return }
        didConfigure = true
        let criteria = GCKDiscoveryCriteria(applicationID: receiverAppID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)
        shared.registerListener()
    }

    private func registerListener() {
        guard !didRegisterListener else { return }
        didRegisterListener = true
        GCKCastContext.sharedInstance().sessionManager.add(self)
    }

    /// The title currently on screen. Called by the player whenever a new
    /// stream loads, so a session started from the Cast button already
    /// knows what to play. If a session is already active, the new title
    /// loads onto the receiver immediately.
    func setPendingMedia(url: URL, title: String, startAt: Double) {
        pendingMedia = PendingMedia(url: url, title: title, startAt: startAt)
        if isCasting {
            loadPendingMedia()
        }
    }

    /// Ends the session from the casting screen. didEndSession flips
    /// isCasting back off, which rebuilds local playback.
    func disconnect() {
        GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
    }

    // MARK: - Loading onto the receiver

    private func loadPendingMedia() {
        guard let media = pendingMedia,
              let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession,
              let client = session.remoteMediaClient else { return }
        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(media.title, forKey: kGCKMetadataKeyTitle)
        let info = GCKMediaInformation(
            contentID: media.url.absoluteString,
            streamType: .buffered,
            contentType: "video/mp4",
            metadata: metadata,
            streamDuration: 0,
            mediaTracks: [],
            textTrackStyle: nil,
            customData: nil
        )
        let options = GCKMediaLoadOptions()
        options.autoplay = true
        options.playPosition = media.startAt
        client.loadMedia(info, with: options)
    }
}

// MARK: - GCKSessionManagerListener

extension CastController: GCKSessionManagerListener {
    func sessionManager(_ manager: GCKSessionManager, didStart session: GCKSession) {
        deviceName = session.device.friendlyName
        isCasting = true
        loadPendingMedia()
    }

    func sessionManager(_ manager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        // Best effort: the receiver's position may already be gone by the
        // time this fires, in which case local playback resumes from the
        // last locally reported position instead (resumePosition stays 0).
        if let castSession = session as? GCKCastSession,
           let position = castSession.remoteMediaClient?.approximateStreamPosition(),
           position.isFinite, position > 0 {
            resumePosition = position
        }
        deviceName = nil
        isCasting = false
    }

    func sessionManager(_ manager: GCKSessionManager, didFailToStartSessionWithError error: Error?) {
        // No session, so nothing changes: local playback keeps going.
        isCasting = false
    }
}
