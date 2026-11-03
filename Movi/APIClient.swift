import Foundation

enum APIError: Error, LocalizedError {
    case network(String)
    case server(String)
    case sessionExpired
    case decoding

    var errorDescription: String? {
        switch self {
        case .network(let msg): return msg
        case .server(let msg): return msg
        case .sessionExpired: return "Your session expired. Please sign in again."
        case .decoding: return "The server sent something unexpected. Please try again."
        }
    }
}

private struct APIErrorBody: Decodable {
    let error: String?
}

/// Talks to the Movi JSON API at https://movi.webs.vc/api.php.
/// Auth is the PHP session cookie in shared cookie storage, so a session
/// survives relaunches the way a browser session does. No credentials are
/// stored anywhere in the app; login sends them once, over HTTPS, and the
/// server sets the cookie.
final class APIClient {
    static let shared = APIClient()

    let base = URL(string: "https://movi.webs.vc/api.php")!
    let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    func clearCookies() {
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies(for: base) ?? [] {
            storage.deleteCookie(cookie)
        }
    }

    // MARK: - GET

    func get<T: Decodable>(_ api: String, params: [String: String] = [:]) async throws -> T {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw APIError.network("Couldn't reach the server.")
        }
        var items = [URLQueryItem(name: "api", value: api)]
        for (k, v) in params {
            items.append(URLQueryItem(name: k, value: v))
        }
        comps.queryItems = items
        guard let url = comps.url else {
            throw APIError.network("Couldn't reach the server.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let (data, resp) = try await dataWithRetry(for: req)
        try Self.check(resp, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    // MARK: - POST (form-encoded, like the site's own forms)

    @discardableResult
    func postForm(_ api: String, fields: [String: String]) async throws -> Data {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw APIError.network("Couldn't reach the server.")
        }
        comps.queryItems = [URLQueryItem(name: "api", value: api)]
        guard let url = comps.url else {
            throw APIError.network("Couldn't reach the server.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        req.httpBody = fields
            .map { k, v in formEscape(k) + "=" + formEscape(v) }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, resp) = try await dataWithRetry(for: req)
        try Self.check(resp, data: data)
        return data
    }

    // MARK: - Retry + error mapping

    private func dataWithRetry(for req: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try await session.data(for: req)
            } catch let e as URLError {
                lastError = e
                // Only a transient network failure is worth one retry.
                if e.code == .timedOut || e.code == .networkConnectionLost {
                    if attempt == 0 { continue }
                }
                throw mapURLError(e)
            } catch {
                throw APIError.network("Couldn't reach the server.")
            }
        }
        throw mapURLError(lastError as? URLError) ?? APIError.network("Couldn't reach the server.")
    }

    private func mapURLError(_ e: URLError?) -> APIError {
        switch e?.code {
        case .notConnectedToInternet:
            return .network("You're offline. Check your connection and try again.")
        case .cancelled:
            return .network("The request was cancelled.")
        default:
            return .network("Couldn't reach the server.")
        }
    }

    private func formEscape(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    // MARK: - Response validation

    static func check(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw APIError.network("Couldn't reach the server.") }
        if http.statusCode == 401 {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data).error) ?? ""
            if msg.lowercased().contains("login") {
                throw APIError.sessionExpired
            }
            throw APIError.server(msg.isEmpty ? "Sign-in failed." : msg)
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data).error)
                ?? "Server error (\(http.statusCode))."
            throw APIError.server(msg)
        }
        // A logged-out API call can come back as the HTML login page.
        if let prefix = String(data: data.prefix(64), encoding: .utf8),
           prefix.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            throw APIError.sessionExpired
        }
        if data.isEmpty {
            throw APIError.decoding
        }
    }
}
