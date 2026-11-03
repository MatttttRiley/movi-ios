import SwiftUI

@main
struct MoviApp: App {
    @StateObject private var app = AppState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
            // Deliberately no forced color scheme: the app follows the
            // system appearance, as the Human Interface Guidelines require.
            // All colors below are semantic or adapt to light and dark.
        }
    }
}

/// Top-level router: loading -> sign-in -> profiles (multi-profile only) -> main tabs.
struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            switch app.phase {
            case .loading:
                ProgressView("Loading Movi…")
                    .task { await app.bootstrap() }
            case .login:
                LoginView()
            case .profiles:
                ProfilesView()
            case .main:
                MainTabsView()
            }
        }
        .background(Color(.systemBackground))
    }
}

/// Handles background-download completion so iOS can wake the app to
/// finish a download that started while the app was in the background.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Cast discovery must be configured before any player UI appears.
        CastController.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            DownloadStore.shared.backgroundCompletionHandler = completionHandler
        }
    }
}
