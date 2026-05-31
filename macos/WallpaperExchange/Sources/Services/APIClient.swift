import Foundation
import AppKit

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case insufficientCoins
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "Please log in"
        case .insufficientCoins: return "Insufficient coins"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .decodingError(let err): return "Decode error: \(err.localizedDescription)"
        case .networkError(let err): return err.localizedDescription
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    // Apex domain; the api. subdomain isn't routed in prod (TLS
    // connection-reset). This was a long-standing bug that masked
    // itself because cached tokens skipped the login path.
    private let baseURL = "https://wallpaperexchange.com/api/v1"

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    // Internal (not private) so extensions in sibling files can route
    // their endpoints through the same request plumbing — token attach,
    // 401/402 mapping, decoding. See APIClient+Main.swift.
    func request<T: Decodable>(_ path: String, method: String = "GET", queryItems: [URLQueryItem]? = nil) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        if let items = queryItems, !items.isEmpty {
            components.queryItems = items
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method

        if let token = await AuthService.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        if http.statusCode == 402 {
            throw APIError.insufficientCoins
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchWallpapers(
        cursor: Int? = nil,
        limit: Int = 20,
        dynamicOnly: Bool = false,
        aiOnly: Bool = false,
        search: String? = nil,
        categoryID: Int? = nil,
        sort: String? = nil,
        deviceMatch: Bool = false
    ) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
        ]
        if dynamicOnly {
            items.append(.init(name: "dynamic_only", value: "true"))
        }
        if aiOnly {
            items.append(.init(name: "ai_only", value: "true"))
        }
        if let s = search?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            items.append(.init(name: "search", value: s))
        }
        if let id = categoryID, id > 0 {
            items.append(.init(name: "category_id", value: String(id)))
        }
        if let sort, !sort.isEmpty {
            items.append(.init(name: "sort", value: sort))
        }
        // Device-resolution match — sends this Mac's physical pixel
        // dimensions so the backend filters to wallpapers with a
        // matching variant.
        if deviceMatch, let screen = NSScreen.main {
            let dpr = Int(screen.backingScaleFactor)
            let w = Int(screen.frame.width) * dpr
            let h = Int(screen.frame.height) * dpr
            items.append(.init(name: "device_width", value: String(w)))
            items.append(.init(name: "device_height", value: String(h)))
            items.append(.init(name: "include_dynamic", value: "true"))
        }
        // The mac client doesn't render video wallpapers. Hide them
        // server-side so we don't even pay the metadata round trip.
        items.append(.init(name: "exclude_video", value: "true"))
        if let c = cursor {
            items.append(.init(name: "cursor", value: String(c)))
        }
        let resp: APIResponse<PaginatedData<Wallpaper>> = try await request("/wallpapers", queryItems: items)
        return resp.data
    }

    func fetchMyDownloads(
        cursor: Int? = nil,
        limit: Int = 20,
        deviceWidth: Int? = nil,
        deviceHeight: Int? = nil,
        dynamicOnly: Bool = false
    ) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            // The mac client can't render video wallpapers. Downloads are
            // cross-platform, so drop any video the user pulled elsewhere.
            .init(name: "exclude_video", value: "true"),
        ]
        if let c = cursor {
            items.append(.init(name: "cursor", value: String(c)))
        }
        // Same mutual exclusion as fetchWallpapers — dynamic-only wins over
        // resolution match when both are conceptually set.
        if dynamicOnly {
            items.append(.init(name: "dynamic_only", value: "true"))
        } else if let w = deviceWidth, let h = deviceHeight, w > 0, h > 0 {
            items.append(.init(name: "device_width", value: String(w)))
            items.append(.init(name: "device_height", value: String(h)))
            items.append(.init(name: "include_dynamic", value: "true"))
        }
        let resp: APIResponse<PaginatedData<Wallpaper>> = try await request("/users/me/downloads", queryItems: items)
        return resp.data
    }

    func fetchCoins() async throws -> Int {
        let resp: APIResponse<CoinsResponse> = try await request("/users/me/coins")
        return resp.data.coins
    }

    // Powers UpdateService — pulls the current release manifest off the
    // API so the client can compare against its own Info.plist version
    // and self-upgrade when a new build ships.
    func fetchMacRelease() async throws -> MacRelease {
        let resp: APIResponse<MacRelease> = try await request("/mac/release")
        return resp.data
    }

    func fetchProfile() async throws -> User {
        let resp: APIResponse<User> = try await request("/users/me")
        return resp.data
    }

    /// Returns the redirect URL for the file download (costs 1 coin).
    ///
    /// `targetWidth` / `targetHeight` are an optional hint about the
    /// resolution the caller actually needs to fill. When both are >0 the
    /// backend hands back the smallest pre-rendered variant covering W×H
    /// instead of the original — typically 1.5–3 MB instead of the often
    /// 10–60 MB raw upload. Defaults of 0 keep the legacy behavior (always
    /// returns the original) for callers that explicitly want the source
    /// file. Dynamic HEIC wallpapers always come back as the original
    /// regardless of these hints — variants can't represent a multi-frame
    /// HEIC.
    func getDownloadURL(wallpaperID: Int, targetWidth: Int = 0, targetHeight: Int = 0) async throws -> URL {
        var path = "/wallpapers/\(wallpaperID)/download"
        if targetWidth > 0 && targetHeight > 0 {
            path += "?width=\(targetWidth)&height=\(targetHeight)"
        }
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = await AuthService.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        let noRedirectSession = URLSession(configuration: config, delegate: NoRedirectDelegate.shared, delegateQueue: nil)

        let (_, response) = try await noRedirectSession.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 402 { throw APIError.insufficientCoins }

        guard http.statusCode == 302 || http.statusCode == 301,
              let location = http.value(forHTTPHeaderField: "Location"),
              let redirectURL = URL(string: location) else {
            throw APIError.serverError(http.statusCode, "No redirect")
        }

        return redirectURL
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
