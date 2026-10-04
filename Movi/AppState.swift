import Foundation
import SwiftUI

/// Session state machine: loading -> login -> profiles -> main.
@MainActor
final class AppState: ObservableObject {
    enum Phase {
        case loading, login, profiles, main
    }

    @Published var phase: Phase = .loading
    @Published var user: APIUser?
    @Published var profiles: [Profile] = []
    @Published var profile: Profile?
    @Published var csrf = ""
    @Published var error = ""

    private let decoder = JSONDecoder()

    // MARK: - Bootstrap

    /// If a session cookie survived, skip straight to profiles/home.
    func bootstrap() async {
        do {
            let r: ProfilesResponse = try await APIClient.shared.get("app_profiles")
            user = nil
            profiles = r.profiles
            csrf = r.csrf ?? ""
            if let cur = r.current_profile_id,
               let p = profiles.first(where: { $0.id == cur }) {
                profile = p
                phase = .main
            } else {
                phase = .profiles
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
                error = r.error ?? "Login failed."
                return
            }
            user = u
            await loadProfiles()
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
            // Best effort; local state is dropped regardless.
        }
        user = nil
        profiles = []
        profile = nil
        csrf = ""
        phase = .login
    }

    // MARK: - Profiles

    func loadProfiles() async {
        do {
            let r: ProfilesResponse = try await APIClient.shared.get("app_profiles")
            profiles = r.profiles
            csrf = r.csrf ?? ""
            phase = .profiles
        } catch {
            error = "Couldn't load profiles."
        }
    }

    func selectProfile(_ p: Profile) async {
        error = ""
        do {
            _ = try await APIClient.shared.postForm("app_profile_select", fields: [
                "profile_id": "\(p.id)",
            ])
            profile = p
            phase = .main
        } catch {
            error = "Couldn't select that profile."
        }
    }

    // MARK: - Helpers

    /// Form fields for CSRF-protected writes (progress, favorites, history).
    func csrfFields(_ extra: [String: String] = [:]) -> [String: String] {
        var f = extra
        f["csrf"] = csrf
        return f
    }
}

private struct EmptyResponse: Decodable {}
