import SwiftUI

/// Home, built from the live app_home response:
/// continue_watching, movies, shows, my_list.
/// The old app decoded hero/rows, which the server never sent, so home
/// could never load correctly. This version shows exactly what the
/// server returns, with a real hero (first continue-watching item, else
/// the newest movie) and standard empty/error states.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var home: HomeResponse?
    @State private var error = ""
    @State private var playRequest: PlayRequest?
    @State private var showAccount = false

    var body: some View {
        Group {
            if let home {
                ScrollView {
                    VStack(spacing: 20) {
                        if let hero = heroItem(from: home) {
                            HeroView(hero: hero, onPlay: {
                                playRequest = PlayRequest(kind: heroKind(hero), itemId: hero.id, directUrl: hero.streamUrl, displayTitle: hero.title)
                            })
                        }
                        if let cw = home.continueWatching, !cw.isEmpty {
                            HomeRowView(title: "Continue Watching", items: cw, kind: "movie")
                        }
                        if let movies = home.movies, !movies.isEmpty {
                            HomeRowView(title: "Recently Added Movies", items: movies, kind: "movie")
                        }
                        if let shows = home.shows, !shows.isEmpty {
                            HomeRowView(title: "Recently Added Shows", items: shows, kind: "show")
                        }
                        if let list = home.myList, !list.isEmpty {
                            HomeRowView(title: "My List", items: list, kind: "movie")
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(.top, 8)
                    // Last rows must clear the floating tab bar: the tab
                    // bar overlaps scroll content on current iOS, so a
                    // plain spacer is not enough.
                    .padding(.bottom, 96)
                }
                .refreshable { await load() }
            } else if !error.isEmpty {
                ErrorStateView(message: error) { Task { await load() } }
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Movi")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAccount = true
                } label: {
                    Label("Account", systemImage: "person.circle")
                }
                .accessibilityLabel("Account")
            }
        }
        .navigationDestination(isPresented: $showAccount) {
            AccountView()
        }
        .task { await load() }
        .fullScreenCover(item: $playRequest) { req in
            PlayerLoader(kind: req.kind, itemId: req.itemId, directUrl: req.directUrl, displayTitle: req.displayTitle)
                .environmentObject(app)
        }
    }

    private func heroItem(from home: HomeResponse) -> TitleItem? {
        if let cw = home.continueWatching, let first = cw.first { return first }
        return home.movies?.first
    }

    private func heroKind(_ hero: TitleItem) -> String {
        // Continue-watching rows are movies only, server-side.
        "movie"
    }

    private func load() async {
        do {
            let h: HomeResponse = try await APIClient.shared.get("app_home")
            home = h
            error = ""
        } catch let e as APIError {
            if case .sessionExpired = e {
                await app.logout()
            } else {
                error = e.localizedDescription
            }
        } catch {
            self.error = "Couldn't load home."
        }
    }
}

struct HeroView: View {
    let hero: TitleItem
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BackdropBanner(imageUrl: hero.backdrop, fallbackPosterUrl: hero.poster, height: 340)
            VStack(alignment: .leading, spacing: 10) {
                Text(hero.title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                if let y = hero.year {
                    Text("\(y)").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.moviAccent)
                    .controlSize(.large)
                    NavigationLink(value: Destination(kind: "movie", id: hero.id)) {
                        Text("More Info")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(20)
        }
    }
}

/// Identifiable play request driving the fullscreen player.
struct PlayRequest: Identifiable {
    let id = UUID()
    let kind: String // "movie" | "episode"
    let itemId: Int
    /// Direct stream URL when the caller already has one (e.g. an episode
    /// from a show detail response). PlayerLoader uses it without an extra
    /// API round-trip; when nil it falls back to the detail endpoints.
    var directUrl: String? = nil
    var displayTitle: String? = nil
}
