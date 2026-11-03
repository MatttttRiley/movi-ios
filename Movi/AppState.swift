import Foundation
import SwiftUI

/// Session state machine: loading -> sign-in -> (profile, only when the
/// account actually has more than one) -> main.
///
/// The server requires a selected profile for home, progress, history and
/// favorites. Movi accounts normally have exactly one profile, so the app
/// selects it silently and never shows a picker for a choice that isn't
/// really a choice. The picker appears only if an account has several.
@MainActor
final class AppState: ObservableObject {
    enum Phase {
        case loading, login, profiles, main
    }

    @Published var phase: Phase = .loading
    @Published var user: APIUser?
    @Published var profiles: [Profile] = []
    @Published var profile: Profile?
    @Published var error = ""

    private let decoder = JSONDecoder()

    // MARK: - Bootstrap

    func bootstrap() async {
        do {
            let r: ProfilesResponse = try await APIClient.shared.get("app_profiles")
            let list = r.profiles ?? []
            if list.isEmpty {
                // No profile rows at all: the session may still be valid for
                // home, or it may be expired. Home decides, once.
                let _: HomeResponse = try await APIClient.shared.get("app_home")
                phase = .main
                return
            }
            profiles = list
            if list.count == 1 {
                try await selectProfile(list[0])
            } else {
                phase = .profiles
            }
        } catch let e as APIError {
            if case .sessionExpired = e {
                phase = .login
            } else {
                phase = .login
            }
        } catch {
            phase = .login
        }
    }

    // MARK: - Auth

    func login(email: String, password: String) async {
        error = ""
        do {
            let data = try await APIClient.shared.postForm("app_login", fields: [
                "email": email,
                "password": password,
            ])
            let r = try decoder.decode(LoginResponse.self, from: data)
            guard r.ok, let u = r.user else {
                error = r.error ?? "Sign-in failed."
                return
            }
            user = u
            await bootstrap()
        } catch let e as APIError {
            error = e.localizedDescription
        } catch {
            error = "Couldn't reach the server."
        }
    }

    func logout() async {
        do {
            let _: EmptyResponse = try await APIClient.shared.get("app_logout")
        } catch {
            // Best effort; local state and cookies are dropped regardless.
        }
        APIClient.shared.clearCookies()
        user = nil
        profiles = []
        profile = nil
        error = ""
        phase = .login
    }

    // MARK: - Profiles

    func selectProfile(_ p: Profile) async throws {
        _ = try await APIClient.shared.postForm("app_profile_select", fields: [
            "profile_id": "\(p.id)",
        ])
        profile = p
        phase = .main
    }

    func selectProfileFromPicker(_ p: Profile) async {
        error = ""
        do {
            try await selectProfile(p)
        } catch {
            error = "Couldn't select that profile."
        }
    }

    // MARK: - Watch state (live api.php field names)

    /// Progress: POST progress { type: "movie"|"episode", id, position, duration }.
    func reportProgress(kind: String, id: Int, position: Double, duration: Double) async {
        guard duration > 0, position >= 0 else { return }
        _ = try? await APIClient.shared.postForm("progress", fields: [
            "type": kind,
            "id": "\(id)",
            "position": "\(Int(position))",
            "duration": "\(Int(duration))",
        ])
    }

    /// History: POST history_add { id } (movies only, server-side).
    func markHistory(movieId: Int) async {
        guard movieId > 0 else { return }
        _ = try? await APIClient.shared.postForm("history_add", fields: ["id": "\(movieId)"])
    }

    /// Favorite toggle: POST favorite { id } (movies only, server-side).
    /// Returns favorited state; nil means the request failed.
    func toggleFavorite(movieId: Int) async -> Bool? {
        struct FavResp: Decodable {
            let ok: Bool?
            let favorited: Bool?
        }
        do {
            let data = try await APIClient.shared.postForm("favorite", fields: ["id": "\(movieId)"])
            return try decoder.decode(FavResp.self, from: data).favorited
        } catch {
            return nil
        }
    }

    func isFavorite(movieId: Int, myList: [TitleItem]) -> Bool {
        myList.contains { $0.id == movieId }
    }
}

private struct EmptyResponse: Decodable {}
