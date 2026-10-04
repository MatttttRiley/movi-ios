import SwiftUI

@main
struct MoviApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
    }
}

/// Top-level router: loading -> login -> profiles -> main tabs.
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
