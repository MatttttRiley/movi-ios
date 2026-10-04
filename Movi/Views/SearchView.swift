import SwiftUI

struct SearchView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var movies: [HomeItem] = []
    @State private var shows: [HomeItem] = []
    @State private var searching = false
    @State private var error = ""

    var body: some View {
        ZStack {
            Color.moviBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.5))
                        TextField("Titles", text: $query)
                            .foregroundColor(.white)
                            .submitLabel(.search)
                            .onSubmit { Task { await search() } }
                        if !query.isEmpty {
                            Button {
                                query = ""
                                movies = []
                                shows = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.moviCard)
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if searching {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if !error.isEmpty {
                        Text(error).foregroundColor(.red).padding(.horizontal, 16)
                    } else {
                        if !movies.isEmpty {
                            resultGrid(title: "Movies", items: movies.map(fixKind("movie")))
                        }
                        if !shows.isEmpty {
                            resultGrid(title: "Shows", items: shows.map(fixKind("show")))
                        }
                        if !query.isEmpty && movies.isEmpty && shows.isEmpty && !searching {
                            Text("No results for \"\(query)\".")
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 16)
                        }
                    }
                    Spacer(minLength: 24)
                }
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
    }

    /// Search results carry no `kind`; stamp it so cards navigate correctly.
    private func fixKind(_ kind: String) -> (HomeItem) -> HomeItem {
        { item in
            HomeItem(itemId: item.itemId, title: item.title, year: item.year,
                     posterUrl: item.posterUrl, kind: kind,
                     positionSeconds: nil, durationSeconds: nil,
                     showTitle: nil, seasonNo: nil, episodeNo: nil)
        }
    }

    private func resultGrid(title: String, items: [HomeItem]) -> some View {
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

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        searching = true
        error = ""
        do {
            let r: SearchResponse = try await APIClient.shared.get("search", params: ["q": q])
            movies = r.movies ?? []
            shows = r.shows ?? []
        } catch let e as APIError {
            error = e.localizedDescription
        } catch {
            error = "Search failed."
        }
        searching = false
    }
}

// MARK: - HomeItem convenience init for stamping kinds

extension HomeItem {
    init(itemId: Int, title: String, year: Int?, posterUrl: String?, kind: String,
         positionSeconds: Double?, durationSeconds: Double?,
         showTitle: String?, seasonNo: Int?, episodeNo: Int?) {
        self.itemId = itemId
        self.title = title
        self.year = year
        self.posterUrl = posterUrl
        self.kind = kind
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.showTitle = showTitle
        self.seasonNo = seasonNo
        self.episodeNo = episodeNo
    }
}
