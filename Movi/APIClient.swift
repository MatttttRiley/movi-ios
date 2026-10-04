import Foundation

enum APIError: Error, LocalizedError {
    case network
    case server(String)
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .network: return "Couldn't reach the server."
        case .server(let msg): return msg
        case .sessionExpired: return "Your session expired. Please log in again."
        }
    }
}

private struct APIErrorBody: Decodable {
    let error: String?
}

/// Talks to the Movi JSON API. The PHP session cookie is kept in the shared
/// cookie storage, so login persists across launches like a browser.
final class APIClient {
    static let shared = APIClient()

    let base = URL(string: "https://movi.byethost6.com/api.php")!
    let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - GET

    func get<T: Decodable>(_ api: String, params: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "api", value: api)]
        for (k, v) in params {
            items.append(URLQueryItem(name: k, value: v))
        }
        comps.queryItems = items
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - POST (form-encoded, like the site's own forms)

    @discardableResult
    func postForm(_ api: String, fields: [String: String]) async throws -> Data {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "api", value: api)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        req.httpBody = fields
            .map { k, v in
                formEscape(k) + "=" + formEscape(v)
            }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data: data)
        return data
    }

    private func formEscape(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    // MARK: - Response validation

    static func check(_ resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw APIError.network }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data).error)
                ?? "Server error (\(http.statusCode))."
            throw APIError.server(msg)
        }
        // Logged-out API calls get redirected to the HTML login page.
        if let prefix = String(data: data.prefix(32), encoding: .utf8),
           prefix.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            throw APIError.sessionExpired
        }
    }
}
