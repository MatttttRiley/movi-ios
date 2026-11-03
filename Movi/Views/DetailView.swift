import SwiftUI

// MARK: - Movie detail (live shape: { movie: TitleItem })

struct MovieDetailView: View {
    let movieId: Int
    @EnvironmentObject var app: AppState
    @State private var movie: TitleItem?
    @State private var isFavorite = false
    @State private var myList: [TitleItem] = []
    @State private var error = ""
    @State private var playRequest: PlayRequest?

    var body: some View {
        Group {
            if let m = movie {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BackdropBanner(imageUrl: m.backdrop, fallbackPosterUrl: m.poster, height: 240)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(m.title)
                                .font(.title.bold())
                                .accessibilityAddTraits(.isHeader)
                            HStack(spacing: 10) {
                                if let y = m.year { Text("\(y)") }
                                if let g = m.genres, !g.isEmpty { Text(g.replacingOccurrences(of: ",", with: " • ")) }
                                if let rt = m.runtimeMinutes { Text("\(rt) min") }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            if let ov = m.overview, !ov.isEmpty {
                                Text(ov).font(.body)
                            }
                            HStack(spacing: 12) {
                                Button {
                                    playRequest = PlayRequest(kind: "movie", itemId: m.id, directUrl: m.streamUrl, displayTitle: m.title)
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.moviAccent)
                                FavoriteButton(isFavorite: isFavorite) {
                                    await toggleFavorite()
                                }
                                DownloadButton(kind: "movie", libraryId: m.id, title: m.title, posterUrl: m.poster, streamUrl: m.streamUrl)
                            }
                            if let pos = m.positionSeconds, pos > 0 {
                                Text("Resume from \(formattedTime(pos))")
                                    .font(.callout)
                                    .foregroundStyle(Color.moviAccent)
                            }
                        }
                        .padding(.horizontal, 20)
                        Spacer(minLength: 30)
                    }
                }
            } else if !error.isEmpty {
                ErrorStateView(message: error) { Task { await reload() } }
            } else {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .fullScreenCover(item: $playRequest) { req in
            PlayerLoader(kind: req.kind, itemId: req.itemId, directUrl: req.directUrl, displayTitle: req.displayTitle)
                .environmentObject(app)
        }
    }

    private func formattedTime(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private func reload() async {
        do {
            let r: MovieDetailResponse = try await APIClient.shared.get("movie", params: ["id": "\(movieId)"])
            guard let m = r.movie else { error = "This title couldn't be found."; return }
            movie = m
            error = ""
            // My List membership comes from home (no favorites endpoint).
            if let h: HomeResponse = try? await APIClient.shared.get("app_home") {
                myList = h.myList ?? []
                isFavorite = myList.contains { $0.id == movieId }
            }
        } catch let e as APIError {
            error = e.localizedDescription
        } catch {
            self.error = "Couldn't load this title."
        }
    }

    private func toggleFavorite() async {
        if let fav = await app.toggleFavorite(movieId: movieId) {
            isFavorite = fav
        }
    }
}

// MARK: - Show detail (live shape: { show: { seasons: [{ season_num, episodes }] } })

struct ShowDetailView: View {
    let showId: Int
    @EnvironmentObject var app: AppState
    @State private var show: ShowDetailItem?
    @State private var error = ""
    @State private var seasonIndex = 0
    @State private var playRequest: PlayRequest?

    var body: some View {
        Group {
            if let s = show {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BackdropBanner(imageUrl: s.backdrop, fallbackPosterUrl: s.poster, height: 240)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(s.title)
                                .font(.title.bold())
                                .accessibilityAddTraits(.isHeader)
                            if let ov = s.overview, !ov.isEmpty {
                                Text(ov).font(.body)
                            }
                            if let seasons = s.seasons, !seasons.isEmpty {
                                // HIG: a Menu, not a segmented control, when
                                // there can be many seasons.
                                Menu {
                                    ForEach(seasons.indices, id: \.self) { i in
                                        Button("Season \(seasons[i].seasonNumber)") { seasonIndex = i }
                                    }
                                } label: {
                                    Label("Season \(seasons[min(seasonIndex, seasons.count - 1)].seasonNumber)", systemImage: "chevron.up.chevron.down")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Choose season")
                                if seasonIndex < seasons.count,
                                   let eps = seasons[seasonIndex].episodes {
                                    ForEach(eps) { ep in
                                        EpisodeRow(episode: ep, showTitle: s.title, posterUrl: s.poster) {
                                            var req = PlayRequest(kind: "episode", itemId: ep.id)
                                            req.directUrl = ep.streamUrl
                                            req.displayTitle = [s.title, ep.title].compactMap { $0 }.joined(separator: " — ")
                                            playRequest = req
                                        }
                                    }
                                }
                            } else {
                                Text("No episodes available yet.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        Spacer(minLength: 30)
                    }
                }
            } else if !error.isEmpty {
                ErrorStateView(message: error) { Task { await reload() } }
            } else {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .fullScreenCover(item: $playRequest) { req in
            PlayerLoader(kind: req.kind, itemId: req.itemId, directUrl: req.directUrl, displayTitle: req.displayTitle)
                .environmentObject(app)
        }
    }

    private func reload() async {
        do {
            let r: ShowDetailResponse = try await APIClient.shared.get("show", params: ["id": "\(showId)"])
            guard let s = r.show else { error = "This show couldn't be found."; return }
            show = s
            error = ""
            if seasonIndex >= (s.seasons?.count ?? 0) { seasonIndex = 0 }
        } catch let e as APIError {
            error = e.localizedDescription
        } catch {
            self.error = "Couldn't load this show."
        }
    }
}

struct EpisodeRow: View {
    let episode: EpisodeItem
    let showTitle: String?
    let posterUrl: String?
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    AsyncPoster(url: episode.still ?? posterUrl, width: 96, cornerRadius: 6, accessibilityLabel: episode.title ?? "Episode")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Episode \(episode.episodeNumber) · \(episode.title ?? "Episode")")
                            .font(.headline)
                            .lineLimit(2)
                        if let ov = episode.overview, !ov.isEmpty {
                            Text(ov)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if let dur = episode.durationSeconds, dur > 0 {
                            Text("\(dur / 60) min")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play episode \(episode.episodeNumber), \(episode.title ?? "")")
            DownloadButton(kind: "episode", libraryId: episode.id,
                           title: [showTitle, episode.title].compactMap { $0 }.joined(separator: " — "),
                           posterUrl: posterUrl, streamUrl: episode.streamUrl, compact: true)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Favorite toggle (movies only, server-side)

struct FavoriteButton: View {
    var isFavorite: Bool
    let onToggle: () async -> Void
    @State private var busy = false

    var body: some View {
        Button {
            Task { busy = true; await onToggle(); busy = false }
        } label: {
            Label(isFavorite ? "In My List" : "My List",
                  systemImage: isFavorite ? "bookmark.fill" : "bookmark")
        }
        .buttonStyle(.bordered)
        .disabled(busy)
        .accessibilityLabel(isFavorite ? "Remove from My List" : "Add to My List")
    }
}
