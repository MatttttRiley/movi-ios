import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var home: HomeResponse?
    @State private var error = ""
    @State private var playRequest: PlayRequest?

    var body: some View {
        ZStack {
            Color.moviBackground.ignoresSafeArea()
            if let home {
                ScrollView {
                    VStack(spacing: 20) {
                        if let hero = home.hero {
                            HeroView(hero: hero, onPlay: { playRequest = PlayRequest(kind: heroKind(hero), itemId: hero.itemId) })
                        }
                        ForEach(home.rows) { row in
                            HomeRowView(row: row)
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(.top, 8)
                }
                .refreshable { await load() }
            } else if !error.isEmpty {
                VStack(spacing: 12) {
                    Text(error).foregroundColor(.red)
                    Button("Try again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Movi")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await app.logout() }
                } label: {
                    Image(systemName: "person.circle")
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $playRequest) { req in
            PlayerLoader(kind: req.kind, itemId: req.itemId)
                .environmentObject(app)
        }
    }

    private func heroKind(_ hero: HomeItem) -> String {
        hero.kind == "episode" ? "episode" : "movie"
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
            error = "Couldn't load home."
        }
    }
}

struct HeroView: View {
    let hero: HomeItem
    let onPlay: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BackdropBanner(imageUrl: nil, height: 340)
            // Prefer a backdrop if the item carries one; HomeItem has none,
            // so fall back to the poster art blurred behind.
            VStack(alignment: .leading, spacing: 10) {
                Text(hero.title)
                    .font(.system(size: 30, weight: .black))
                    .foregroundColor(.white)
                if let y = hero.year {
                    Text("\(y)").foregroundColor(.white.opacity(0.7))
                }
                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            .background(Color.moviAccent)
                            .cornerRadius(8)
                    }
                    if let dest = hero.destination {
                        NavigationLink(value: dest) {
                            Text("More Info")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
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
}
