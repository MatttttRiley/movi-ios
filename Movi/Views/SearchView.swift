import SwiftUI

/// Standard searchable list (HIG: use .searchable in the navigation bar,
/// not a custom search box). Results update as you type, debounced so a
/// fast typist does not fire a request per keystroke. The server needs at
/// least 2 characters; shorter queries simply show the empty state.
struct SearchView: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    @State private var movies: [TitleItem] = []
    @State private var shows: [TitleItem] = []
    @State private var searching = false
    @State private var error = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Group {
            if searching && movies.isEmpty && shows.isEmpty {
                ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !error.isEmpty {
                ErrorStateView(message: error) { Task { await searchNow() } }
            } else if !query.isEmpty && movies.isEmpty && shows.isEmpty {
                if #available(iOS 17, *) {
                    ContentUnavailableView.search(text: query)
                } else {
                    Text("No results for \(query).").foregroundStyle(.secondary)
                }
            } else if query.isEmpty {
                if #available(iOS 17, *) {
                    ContentUnavailableView(
                        "Search Movi",
                        systemImage: "magnifyingglass",
                        description: Text("Type at least 2 characters to search movies and shows.")
                    )
                } else {
                    Text("Type at least 2 characters to search movies and shows.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !movies.isEmpty {
                            resultGrid(title: "Movies", items: movies, kind: "movie")
                        }
                        if !shows.isEmpty {
                            resultGrid(title: "Shows", items: shows, kind: "show")
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 96)
                }
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "Movies and shows")
        .onChange(of: query, perform: { _ in scheduleSearch() })
        .onDisappear { searchTask?.cancel() }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            movies = []
            shows = []
            error = ""
            searching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await searchNow()
        }
    }

    private func searchNow() async {
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
            self.error = "Search failed."
        }
        searching = false
    }

    private func resultGrid(title: String, items: [TitleItem], kind: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.horizontal, 16)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
                ForEach(items) { item in
                    PosterCard(item: item, kind: kind)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}
