import Foundation

// MARK: - Models, matched exactly to the live api.php (Movi v2).
//
// Every shape below was verified against /var/www/movi/api.php on
// 2026-11-03. The previous app decoded a spec that the live server never
// implemented (hero/rows, poster_url, playback objects, a favorites
// endpoint, download endpoints) — that mismatch is why so much of the old
// app silently failed. Nothing here decodes a field the server does not
// send, and every field that can be absent is optional with a safe default,
// so one odd row can never blank a whole screen.

// MARK: - Auth

struct APIUser: Codable {
    let id: Int
    let username: String
    let email: String
    let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case id, username, email, is_admin
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .is_admin), let b {
            isAdmin = b
        } else {
            isAdmin = (try? c.decodeIfPresent(Int.self, forKey: .is_admin)) ?? 0 == 1
        }
    }
}

struct LoginResponse: Codable {
    let ok: Bool
    let user: APIUser?
    let error: String?
}

struct Profile: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let color: String?
}

struct ProfilesResponse: Codable {
    let profiles: [Profile]?
}

// MARK: - Shared title row
//
// api.php's movie_row(): id, title, year, overview, poster, backdrop,
// genres, runtime, duration, stream_url. Continue-watching rows add
// position and progress. Show rows in home/search carry only
// id, title, year, overview, poster, backdrop.

struct TitleItem: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let year: Int?
    let overview: String?
    let poster: String?
    let backdrop: String?
    let genres: String?
    let runtimeMinutes: Int?
    let durationSeconds: Int?
    let streamUrl: String?
    let positionSeconds: Int?
    let progress: Double?

    var progressFraction: Double? {
        if let p = progress { return min(1, max(0, p)) }
        guard let pos = positionSeconds, let dur = durationSeconds, dur > 0 else { return nil }
        return min(1, max(0, Double(pos) / Double(dur)))
    }

    enum CodingKeys: String, CodingKey {
        case id, title, year, overview, poster, backdrop, genres, runtime, duration
        case stream_url, position, progress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        poster = try c.decodeIfPresent(String.self, forKey: .poster)
        backdrop = try c.decodeIfPresent(String.self, forKey: .backdrop)
        // genres arrives as a plain string from the database; tolerate an
        // array too, so a future server change cannot break decoding.
        if let g = try? c.decodeIfPresent(String.self, forKey: .genres) {
            genres = g
        } else if let arr = try? c.decodeIfPresent([String].self, forKey: .genres) {
            genres = arr?.joined(separator: ", ")
        } else {
            genres = nil
        }
        runtimeMinutes = try c.decodeIfPresent(Int.self, forKey: .runtime)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .duration)
        streamUrl = try c.decodeIfPresent(String.self, forKey: .stream_url)
        positionSeconds = try c.decodeIfPresent(Int.self, forKey: .position)
        progress = try c.decodeIfPresent(Double.self, forKey: .progress)
    }
}

// MARK: - Home

struct HomeResponse: Codable {
    let continueWatching: [TitleItem]?
    let movies: [TitleItem]?
    let shows: [TitleItem]?
    let myList: [TitleItem]?

    enum CodingKeys: String, CodingKey {
        case continueWatching = "continue_watching"
        case movies, shows
        case myList = "my_list"
    }
}

// MARK: - Detail

struct MovieDetailResponse: Codable {
    let movie: TitleItem?
}

struct EpisodeItem: Codable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let episodeNumber: Int
    let overview: String?
    let still: String?
    let durationSeconds: Int?
    let streamUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, still, duration
        case episodeNumber = "episode_num"
        case streamUrl = "stream_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title)
        episodeNumber = try c.decodeIfPresent(Int.self, forKey: .episodeNumber) ?? 0
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        still = try c.decodeIfPresent(String.self, forKey: .still)
        durationSeconds = try c.decodeIfPresent(Int.self, forKey: .duration)
        streamUrl = try c.decodeIfPresent(String.self, forKey: .streamUrl)
    }
}

struct SeasonItem: Codable, Identifiable, Hashable {
    let id: Int
    let seasonNumber: Int
    let episodes: [EpisodeItem]?

    enum CodingKeys: String, CodingKey {
        case id, episodes
        case seasonNumber = "season_num"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber) ?? 0
        episodes = try c.decodeIfPresent([EpisodeItem].self, forKey: .episodes)
    }
}

struct ShowDetailItem: Codable {
    let id: Int
    let title: String
    let overview: String?
    let poster: String?
    let backdrop: String?
    let seasons: [SeasonItem]?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, poster, backdrop, seasons
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        poster = try c.decodeIfPresent(String.self, forKey: .poster)
        backdrop = try c.decodeIfPresent(String.self, forKey: .backdrop)
        seasons = try c.decodeIfPresent([SeasonItem].self, forKey: .seasons)
    }
}

struct ShowDetailResponse: Codable {
    let show: ShowDetailItem?
}

// MARK: - Search

struct SearchResponse: Codable {
    let movies: [TitleItem]?
    let shows: [TitleItem]?
}

// MARK: - Navigation

enum Destination: Hashable {
    case movie(Int)
    case show(Int)

    init(kind: String, id: Int) {
        if kind == "movie" { self = .movie(id) } else { self = .show(id) }
    }
}

// Backwards-compatible alias used by older views during the rewrite.
typealias HomeItem = TitleItem
