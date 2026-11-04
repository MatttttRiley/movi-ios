import SwiftUI

/// My List, from app_home.my_list. There is no favorites endpoint on the
/// live server — the old app called one that 404s, so this tab could
/// never load. Server favorites are movies only.
struct LibraryView: View {
    @EnvironmentObject var app: AppState
    @State private var list: [TitleItem] = []
    @State private var error = ""

    var body: some View {
        Group {
            if !error.isEmpty {
                ErrorStateView(message: error) { Task { await load() } }
            } else if list.isEmpty {
                if #available(iOS 17, *) {
                    ContentUnavailableView(
                        "Your List Is Empty",
                        systemImage: "bookmark",
                        description: Text("Tap My List on any movie to save it here.")
                    )
                } else {
                    Text("Your list is empty. Tap My List on any movie to save it here.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 16) {
                        ForEach(list) { item in
                            PosterCard(item: item, kind: "movie")
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 96)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("My List")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private func load() async {
        do {
            let h: HomeResponse = try await APIClient.shared.get("app_home")
            list = h.myList ?? []
            error = ""
        } catch let e as APIError {
            error = e.localizedDescription
        } catch {
            self.error = "Couldn't load your list."
        }
    }
}
