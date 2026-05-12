import Foundation

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

    private let baseURL = "https://api.wallpaperexchange.com/api/v1"

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", queryItems: [URLQueryItem]? = nil) async throws -> T {
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

    func fetchWallpapers(cursor: Int? = nil, limit: Int = 20, deviceWidth: Int, deviceHeight: Int) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "device_width", value: String(deviceWidth)),
            .init(name: "device_height", value: String(deviceHeight)),
            .init(name: "include_dynamic", value: "true"),
        ]
        if let c = cursor {
            items.append(.init(name: "cursor", value: String(c)))
        }
        let resp: APIResponse<PaginatedData<Wallpaper>> = try await request("/wallpapers", queryItems: items)
        return resp.data
    }

    func fetchMyDownloads(cursor: Int? = nil, limit: Int = 20) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
        ]
        if let c = cursor {
            items.append(.init(name: "cursor", value: String(c)))
        }
        let resp: APIResponse<PaginatedData<Wallpaper>> = try await request("/users/me/downloads", queryItems: items)
        return resp.data
    }

    func fetchCoins() async throws -> Int {
        let resp: APIResponse<CoinsResponse> = try await request("/users/me/coins")
        return resp.data.coins
    }

    func fetchProfile() async throws -> User {
        let resp: APIResponse<User> = try await request("/users/me")
        return resp.data
    }

    /// Returns the redirect URL for the original file download (costs 1 coin).
    func getDownloadURL(wallpaperID: Int) async throws -> URL {
        let path = "/wallpapers/\(wallpaperID)/download"
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
