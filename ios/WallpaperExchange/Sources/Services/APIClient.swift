import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

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

// This device's native pixel size, used for the "fits my screen" filter.
// On iOS, UIScreen.main is fine: wallpapers target the device the app
// runs on, and iPhone/iPad have exactly one built-in screen. The AppKit
// branch only serves the macOS dev-preview build.
struct DeviceScreenRequirement: Sendable {
    let width: Int
    let height: Int

    @MainActor
    static var current: DeviceScreenRequirement {
        #if canImport(UIKit)
        let bounds = UIScreen.main.nativeBounds
        return DeviceScreenRequirement(
            width: Int(bounds.width.rounded()),
            height: Int(bounds.height.rounded())
        )
        #else
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        return DeviceScreenRequirement(
            width: Int(frame.width.rounded()),
            height: Int(frame.height.rounded())
        )
        #endif
    }
}

// Same request plumbing as the Mac client's APIClient — token attach,
// 401/402 mapping, envelope decoding — minus the Mac-only surface
// (screen enumeration, DMG release manifest, file-URL uploads).
actor APIClient {
    static let shared = APIClient()

    // Apex domain; the api. subdomain isn't routed in prod.
    private let baseURL = "https://wallpaperexchange.com/api/v1"

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    func fetchWallpaperPage(
        _ path: String,
        cursor: Int?,
        limit: Int,
        queryItems: [URLQueryItem] = []
    ) async throws -> PaginatedData<Wallpaper> {
        var items = queryItems
        items.append(.init(name: "limit", value: String(limit)))
        if let cursor {
            items.append(.init(name: "cursor", value: String(cursor)))
        }
        let resp: APIResponse<PaginatedData<Wallpaper>> = try await request(path, queryItems: items)
        // Central choke point: every list surface (discover, collections,
        // user libraries) flows through here, so the iOS live-content
        // exclusion holds everywhere without per-endpoint backend support.
        return resp.data.droppingLiveContent()
    }

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
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 402 { throw APIError.insufficientCoins }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchWallpapers(
        cursor: Int? = nil,
        limit: Int = 24,
        aiOnly: Bool = false,
        search: String? = nil,
        categoryID: Int? = nil,
        sort: String? = nil,
        deviceRequirement: DeviceScreenRequirement? = nil
    ) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = []
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
        if let req = deviceRequirement {
            items.append(.init(name: "device_width", value: String(req.width)))
            items.append(.init(name: "device_height", value: String(req.height)))
        }
        items.append(.init(name: "exclude_video", value: "true"))
        return try await fetchWallpaperPage("/wallpapers", cursor: cursor, limit: limit, queryItems: items)
    }

    func fetchForYou(limit: Int = 30) async throws -> [Wallpaper] {
        let items: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "exclude_video", value: "true"),
        ]
        let resp: APIResponse<[Wallpaper]> = try await request("/wallpapers/for-you", queryItems: items)
        return resp.data.filter(\.isUsableOnIOS)
    }

    func fetchCoins() async throws -> Int {
        let resp: APIResponse<CoinsResponse> = try await request("/users/me/coins")
        return resp.data.coins
    }

    func fetchProfile() async throws -> User {
        let resp: APIResponse<User> = try await request("/users/me")
        return resp.data
    }

    // ─── Auth ─────────────────────────────────────────────────────
    private func sendAuthJSON<B: Encodable>(_ path: String, body: B) async throws -> AuthResponse {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.networkError(error) }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode >= 400 {
            let envelope = try? decoder.decode(MessageEnvelope.self, from: data)
            throw APIError.serverError(envelope?.code ?? http.statusCode,
                                       envelope?.message ?? "Authentication failed")
        }
        do {
            return try decoder.decode(APIResponse<AuthResponse>.self, from: data).data
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable { let email: String; let password: String }
        return try await sendAuthJSON("/auth/login", body: Body(email: email, password: password))
    }

    func register(username: String, email: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable { let username: String; let email: String; let password: String }
        return try await sendAuthJSON("/auth/register", body: Body(username: username, email: email, password: password))
    }

    // ─── JSON-body writes ────────────────────────────────────────
    private func sendJSON<B: Encodable>(_ path: String, method: String, body: B) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.networkError(error) }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 402 { throw APIError.insufficientCoins }
        if http.statusCode >= 400 {
            let msg = (try? decoder.decode(MessageEnvelope.self, from: data))?.message ?? "Request failed"
            throw APIError.serverError(http.statusCode, msg)
        }
        return data
    }

    func updateProfile(nickname: String, bio: String) async throws -> User {
        struct Body: Encodable { let nickname: String; let bio: String }
        let data = try await sendJSON("/users/me/profile", method: "PUT", body: Body(nickname: nickname, bio: bio))
        return try decoder.decode(APIResponse<User>.self, from: data).data
    }

    func changePassword(old: String, new: String) async throws {
        struct Body: Encodable { let old_password: String; let new_password: String }
        _ = try await sendJSON("/users/me/password", method: "PUT", body: Body(old_password: old, new_password: new))
    }

    func updatePrivacy(likesPublic: Bool? = nil, favoritesPublic: Bool? = nil, downloadsPublic: Bool? = nil) async throws {
        struct Body: Encodable {
            let likes_public: Bool?
            let favorites_public: Bool?
            let downloads_public: Bool?
        }
        _ = try await sendJSON("/users/me/privacy", method: "PUT",
                               body: Body(likes_public: likesPublic, favorites_public: favoritesPublic, downloads_public: downloadsPublic))
    }

    func createCollection(title: String, isPublic: Bool = true) async throws -> CollectionItem {
        struct Body: Encodable { let title: String; let is_public: Bool }
        let data = try await sendJSON("/collections", method: "POST", body: Body(title: title, is_public: isPublic))
        return try decoder.decode(APIResponse<CollectionItem>.self, from: data).data
    }

    func addToCollection(collectionID: Int, wallpaperID: Int) async throws {
        struct Body: Encodable { let wallpaper_id: Int }
        _ = try await sendJSON("/collections/\(collectionID)/wallpapers", method: "POST", body: Body(wallpaper_id: wallpaperID))
    }

    // ─── Uploads ─────────────────────────────────────────────────
    // PhotosPicker hands back raw Data, so the iOS upload path is
    // Data-based rather than the Mac client's file-URL multipart.
    func uploadWallpaperData(
        _ fileData: Data,
        filename: String,
        mime: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let url = URL(string: baseURL + "/wallpapers") else { throw APIError.invalidURL }
        guard let token = await AuthService.shared.token else { throw APIError.unauthorized }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate(progress: progress)
        let uploadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { uploadSession.finishTasksAndInvalidate() }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await uploadSession.upload(for: req, from: body)
        } catch {
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 402 { throw APIError.insufficientCoins }
        if http.statusCode >= 400 {
            let msg = (try? decoder.decode(MessageEnvelope.self, from: data))?.message ?? "Upload failed"
            throw APIError.serverError(http.statusCode, msg)
        }
        progress(1)
    }

    func uploadAvatar(imageData: Data, filename: String = "avatar.jpg", mime: String = "image/jpeg") async throws -> String {
        guard let url = URL(string: baseURL + "/users/me/avatar") else { throw APIError.invalidURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = await AuthService.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.networkError(error) }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode >= 400 { throw APIError.serverError(http.statusCode, "Avatar upload failed") }
        struct AvatarResp: Decodable { let avatar_url: String }
        return try decoder.decode(APIResponse<AvatarResp>.self, from: data).data.avatar_url
    }

    // ─── Download (costs 1 coin, returns redirect target) ────────
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

        let (data, response) = try await noRedirectSession.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 402 { throw APIError.insufficientCoins }

        guard http.statusCode == 302 || http.statusCode == 301,
              let location = http.value(forHTTPHeaderField: "Location"),
              let redirectURL = URL(string: location) else {
            let msg = (try? decoder.decode(MessageEnvelope.self, from: data))?.message ?? "Download is not available"
            throw APIError.serverError(http.statusCode, msg)
        }
        return redirectURL
    }

    static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        default:
            if let type = UTType(filenameExtension: ext),
               let mime = type.preferredMIMEType {
                return mime
            }
            return "application/octet-stream"
        }
    }
}

// iOS can't apply video wallpapers (no system support, see 2026-06-12
// product decision) nor macOS-dynamic solar/h24 HEICs, so the iOS
// client hides live content on every surface.
extension Wallpaper {
    var isUsableOnIOS: Bool {
        !isDynamic && !fileType.hasPrefix("video/")
    }
}

extension PaginatedData where T == Wallpaper {
    func droppingLiveContent() -> PaginatedData<Wallpaper> {
        PaginatedData(
            items: items.filter(\.isUsableOnIOS),
            nextCursor: nextCursor,
            hasMore: hasMore,
            total: total
        )
    }
}

// Minimal envelope used to surface a server error message on 4xx.
private struct MessageEnvelope: Decodable {
    let code: Int?
    let message: String?
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}
