import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @State private var movies: [HomeItem] = []
    @State private var shows: [HomeItem] = []
    @State private var error = ""

    var body: some View {
        ZStack {
            Color.moviBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !movies.isEmpty {
                        section(title: "Movies", items: movies)
                    }
                    if !shows.isEmpty {
                        section(title: "Shows", items: shows)
                    }
                    if movies.isEmpty && shows.isEmpty && error.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 44))
                                .foregroundColor(.white.opacity(0.3))
                            Text("Your list is empty.")
                                .foregroundColor(.white.opacity(0.6))
                            Text("Tap My List on any title to save it here.")
                                .font(.callout)
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                    if !error.isEmpty {
                        Text(error).foregroundColor(.red).padding(.horizontal, 16)
                    }
                    Spacer(minLength: 24)
                }
                .padding(.top, 8)
            }
            .refreshable { await load() }
        }
        .navigationTitle("My List")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private func section(title: String, items: [HomeItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
                ForEach(items) { item in
                    PosterCard(item: item)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func load() async {
        do {
            let r: FavoritesResponse = try await APIClient.shared.get("favorites")
            // Favorites rows carry no `kind`; stamp for navigation.
            movies = (r.movies ?? []).map {
                HomeItem(itemId: $0.itemId, title: $0.title, year: $0.year,
                         posterUrl: $0.posterUrl, kind: "movie",
                         positionSeconds: nil, durationSeconds: nil,
                         showTitle: nil, seasonNo: nil, episodeNo: nil)
            }
            shows = (r.shows ?? []).map {
                HomeItem(itemId: $0.itemId, title: $0.title, year: $0.year,
                         posterUrl: $0.posterUrl, kind: "show",
                         positionSeconds: nil, durationSeconds: nil,
                         showTitle: nil, seasonNo: nil, episodeNo: nil)
            }
            error = ""
        } catch let e as APIError {
            error = e.localizedDescription
        } catch {
            error = "Couldn't load your list."
        }
    }
}
