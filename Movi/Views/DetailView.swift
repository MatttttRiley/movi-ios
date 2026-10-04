import SwiftUI

// MARK: - Movie detail

struct MovieDetailView: View {
    let movieId: Int
    @EnvironmentObject var app: AppState
    @State private var movie: MovieDetail?
    @State private var error = ""
    @State private var playRequest: PlayRequest?

    var body: some View {
        ZStack {
            Color.moviBackground.ignoresSafeArea()
            if let m = movie {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BackdropBanner(imageUrl: m.backdropUrl ?? m.posterUrl, height: 240)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(m.title)
                                .font(.system(size: 28, weight: .black))
                                .foregroundColor(.white)
                            HStack(spacing: 10) {
                                if let y = m.year { Text("\(y)") }
                                if let g = m.genres, !g.isEmpty { Text(g.replacingOccurrences(of: ",", with: " • ")) }
                            }
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            if let ov = m.overview, !ov.isEmpty {
                                Text(ov)
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            MoviGlassGroup(spacing: 12) {
                                HStack(spacing: 12) {
                                    Button {
                                        playRequest = PlayRequest(kind: "movie", itemId: m.id)
                                    } label: {
                                        Label("Play", systemImage: "play.fill")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 28)
                                            .padding(.vertical, 10)
                                            .moviPlayChrome()
                                    }
                                    FavoriteButton(kind: "movie", id: m.id, isFavorite: m.isFavorite ?? false) {
                                        await reload()
                                    }
                                    DownloadButton(kind: "movie", libraryId: m.id,
                                                   title: m.title, posterUrl: m.posterUrl)
                                }
                            }
                            if let label = m.playback?.resumeLabel {
                                Text(label)
                                    .font(.callout)
                                    .foregroundColor(.moviAccent)
                            }
                        }
                        .padding(.horizontal, 20)
                        Spacer(minLength: 30)
                    }
                }
            } else if !error.isEmpty {
                Text(error).foregroundColor(.red)
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .fullScreenCover(item: $playRequest) { req in
            PlayerLoader(kind: req.kind, itemId: req.itemId)
                .environmentObject(app)
        }
    }

    private func reload() async {
        do {
            let m: MovieDetail = try await APIClient.shared.get("movie", params: ["id": "\(movieId)"])
            movie = m
            error = ""
        } catch let e as APIError {
            error = e.localizedDescription
        } catch {
            error = "Couldn't load this title."
        }
    }
}

// MARK: - Show detail

struct ShowDetailView: View {
    let showId: Int
    @EnvironmentObject var app: AppState
    @State private var show: ShowDetail?
    @State private var error = ""
    @State private var seasonIndex = 0
    @State private var playRequest: PlayRequest?

    var body: some View {
        ZStack {
            Color.moviBackground.ignoresSafeArea()
            if let s = show {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        BackdropBanner(imageUrl: s.backdropUrl ?? s.posterUrl, height: 240)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(s.title)
                                .font(.system(size: 28, weight: .black))
                                .foregroundColor(.white)
                            HStack(spacing: 10) {
                                if let y = s.year { Text("\(y)") }
                                if let g = s.genres, !g.isEmpty { Text(g.replacingOccurrences(of: ",", with: " • ")) }
                            }
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            if let ov = s.overview, !ov.isEmpty {
                                Text(ov).foregroundColor(.white.opacity(0.85))
                            }
                            FavoriteButton(kind: "show", id: s.id, isFavorite: s.isFavorite ?? false) {
                                await reload()
                            }
                            if let seasons = s.seasons, !seasons.isEmpty {
                                Picker("Season", selection: $seasonIndex) {
                                    ForEach(seasons.indices, id: \.self) { i in
                                        Text("Season \(seasons[i].seasonNumber ?? i + 1)").tag(i)
                                    }
                                }
                                .pickerStyle(.segmented)
                                if seasonIndex < seasons.count,
                                   let eps = seasons[seasonIndex].episodes {
                                    ForEach(eps) { ep in
                                        EpisodeRow(episode: ep, showTitle: s.title, posterUrl: s.posterUrl) {
                                            playRequest = PlayRequest(kind: "episode", itemId: ep.id)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        Spacer(minLength: 30)
                    }
                }
            } else if !error.isEmpty {
                Text(error).foregroundColor(.red)
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .fullScreenCover(item: $playRequest) { req in
            PlayerLoader(kind: req.kind, itemId: req.itemId)
                .environmentObject(app)
        }
    }

    private func reload() async {
        do {
            let s: ShowDetail = try await APIClient.shared.get("show", params: ["id": "\(showId)"])
            show = s
            error = ""
        } catch let e as APIError {
            error = e.localizedDescription
        } catch {
            error = "Couldn't load this show."
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let showTitle: String?
    let posterUrl: String?
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                HStack(spacing: 12) {
                    ZStack(alignment: .bottom) {
                        AsyncPoster(url: episode.stillUrl, width: 96, cornerRadius: 6)
                        if let p = episode.progress {
                            ProgressView(value: p).tint(.red).padding(4)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("E\(episode.episodeNumber ?? 0) · \(episode.title ?? "Episode")")
                            .font(.headline)
                            .foregroundColor(.white)
                        if let ov = episode.overview, !ov.isEmpty {
                            Text(ov)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.8))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            DownloadButton(kind: "episode", libraryId: episode.id,
                           title: [showTitle, episode.title].compactMap { $0 }.joined(separator: " — "),
                           posterUrl: posterUrl, compact: true)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Episode deep-link loader (from Continue Watching)

struct EpisodeLoaderView: View {
    let episodeId: Int
    @EnvironmentObject var app: AppState
    @State private var playRequest: PlayRequest?

    var body: some View {
        ZStack {
            Color.moviBackground.ignoresSafeArea()
            ProgressView()
        }
        .onAppear {
            playRequest = PlayRequest(kind: "episode", itemId: episodeId)
        }
        .fullScreenCover(item: $playRequest) { req in
            PlayerLoader(kind: req.kind, itemId: req.itemId)
                .environmentObject(app)
        }
    }
}

// MARK: - Favorite toggle

struct FavoriteButton: View {
    let kind: String
    let id: Int
    @State var isFavorite: Bool
    let onChange: () async -> Void
    @EnvironmentObject var app: AppState
    @State private var busy = false

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Label(isFavorite ? "In My List" : "My List",
                  systemImage: isFavorite ? "bookmark.fill" : "bookmark")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .moviGlassCapsule()
        }
        .disabled(busy)
    }

    private func toggle() async {
        busy = true
        do {
            _ = try await APIClient.shared.postForm("favorite",
                fields: app.csrfFields(["kind": kind, "id": "\(id)", "action": "toggle"]))
            isFavorite.toggle()
            await onChange()
        } catch { }
        busy = false
    }
}
