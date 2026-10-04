import Foundation

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
        id = try c.decode(Int.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        email = try c.decode(String.self, forKey: .email)
        if let b = try? c.decode(Bool.self, forKey: .is_admin) {
            isAdmin = b
        } else {
            isAdmin = ((try? c.decode(Int.self, forKey: .is_admin)) ?? 0) == 1
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
    let color: String
}

struct ProfilesResponse: Codable {
    let profiles: [Profile]
    let current_profile_id: Int?
    let csrf: String?
}

// MARK: - Home

/// One card in a home row. Movies/shows use `id`; continue-watching uses
/// `item_id` + `kind`. Decodes either shape.
struct HomeItem: Codable, Identifiable, Hashable {
    let itemId: Int
    let title: String
    let year: Int?
    let posterUrl: String?
    let kind: String
    let positionSeconds: Double?
    let durationSeconds: Double?
    let showTitle: String?
    let seasonNo: Int?
    let episodeNo: Int?

    var id: Int { itemId }

    var progress: Double? {
        guard let p = positionSeconds, let d = durationSeconds, d > 0 else { return nil }
        return min(1, max(0, p / d))
    }

    /// Where tapping this card should go.
    var destination: Destination? {
        switch kind {
        case "movie": return .movie(itemId)
        case "show": return .show(itemId)
        case "episode": return .episode(itemId)
        default: return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case item_id, id, title, year, poster_url, kind
        case position_seconds, duration_seconds
        case show_title, season_no, episode_no
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(Int.self, forKey: .item_id) {
            itemId = v
        } else {
            itemId = try c.decode(Int.self, forKey: .id)
        }
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        posterUrl = try c.decodeIfPresent(String.self, forKey: .poster_url)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        positionSeconds = try c.decodeIfPresent(Double.self, forKey: .position_seconds)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .duration_seconds)
        showTitle = try c.decodeIfPresent(String.self, forKey: .show_title)
        seasonNo = try c.decodeIfPresent(Int.self, forKey: .season_no)
        episodeNo = try c.decodeIfPresent(Int.self, forKey: .episode_no)
    }
}

struct HomeRow: Codable, Identifiable, Hashable {
    let key: String
    let title: String
    let kind: String
    let items: [HomeItem]

    var id: String { key }
}

struct HomeResponse: Codable {
    let hero: HomeItem?
    let rows: [HomeRow]
}

// MARK: - Detail

struct PlaybackInfo: Codable {
    let fileUrl: String?
    let resumeHintSec: Double?
    let resumeLabel: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case fileUrl = "file_url"
        case resumeHintSec = "resume_hint_sec"
        case resumeLabel = "resume_label"
        case error
    }
}

struct WatchProgress: Codable {
    let position_seconds: Double?
    let duration_seconds: Double?
}

struct MovieDetail: Codable {
    let id: Int
    let title: String
    let year: Int?
    let overview: String?
    let posterUrl: String?
    let backdropUrl: String?
    let genres: String?
    let isFavorite: Bool?
    let progress: WatchProgress?
    let playback: PlaybackInfo?

    enum CodingKeys: String, CodingKey {
        case id, title, year, overview, genres
        case posterUrl = "poster_url"
        case backdropUrl = "backdrop_url"
        case isFavorite = "is_favorite"
        case progress, playback
    }
}

struct Episode: Codable, Identifiable, Hashable {
    let id: Int
    let episodeNumber: Int?
    let title: String?
    let overview: String?
    let stillUrl: String?
    let positionSeconds: Double?
    let durationSeconds: Double?

    var progress: Double? {
        guard let p = positionSeconds, let d = durationSeconds, d > 0 else { return nil }
        return min(1, max(0, p / d))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case episodeNumber = "episode_number"
        case title, overview
        case stillUrl = "still_url"
        case positionSeconds = "position_seconds"
        case durationSeconds = "duration_seconds"
    }
}

struct Season: Codable, Identifiable, Hashable {
    let id: Int
    let seasonNumber: Int?
    let episodes: [Episode]?

    enum CodingKeys: String, CodingKey {
        case id
        case seasonNumber = "season_number"
        case episodes
    }
}

struct ShowDetail: Codable {
    let id: Int
    let title: String
    let year: Int?
    let overview: String?
    let posterUrl: String?
    let backdropUrl: String?
    let genres: String?
    let isFavorite: Bool?
    let seasons: [Season]?

    enum CodingKeys: String, CodingKey {
        case id, title, year, overview, genres, seasons
        case posterUrl = "poster_url"
        case backdropUrl = "backdrop_url"
        case isFavorite = "is_favorite"
    }
}

struct NextRef: Codable {
    let id: Int
    let episode_number: Int?
    let season_number: Int?
}

struct EpisodeDetail: Codable {
    let id: Int
    let title: String?
    let overview: String?
    let episodeNumber: Int?
    let seasonNumber: Int?
    let showTitle: String?
    let showId: Int?
    let playback: PlaybackInfo?
    let next: NextRef?

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case showTitle = "show_title"
        case showId = "show_id"
        case playback, next
    }
}

// MARK: - Search / library

struct SearchResponse: Codable {
    let movies: [HomeItem]?
    let shows: [HomeItem]?
}

struct FavoritesResponse: Codable {
    let movies: [HomeItem]?
    let shows: [HomeItem]?
}

// MARK: - Navigation

enum Destination: Hashable {
    case movie(Int)
    case show(Int)
    case episode(Int)
}
