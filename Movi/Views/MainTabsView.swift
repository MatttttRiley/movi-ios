import SwiftUI

/// Standard tab bar (HIG: at most a handful of top-level destinations,
/// system tab items, one NavigationStack per tab so back behavior is
/// per-tab and never leaks between tabs).
struct MainTabsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
                    .navigationDestination(for: Destination.self) { dest in
                        destinationView(dest)
                    }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                SearchView()
                    .navigationDestination(for: Destination.self) { dest in
                        destinationView(dest)
                    }
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack {
                LibraryView()
                    .navigationDestination(for: Destination.self) { dest in
                        destinationView(dest)
                    }
            }
            .tabItem { Label("My List", systemImage: "bookmark.fill") }

            NavigationStack {
                DownloadsView()
            }
            .tabItem { Label("Downloads", systemImage: "arrow.down.circle.fill") }
        }
        .tint(.moviAccent)
    }

    @ViewBuilder
    private func destinationView(_ dest: Destination) -> some View {
        switch dest {
        case .movie(let id):
            MovieDetailView(movieId: id)
        case .show(let id):
            ShowDetailView(showId: id)
        }
    }
}
