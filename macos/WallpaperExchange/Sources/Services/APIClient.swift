import Foundation
import AppKit
import UniformTypeIdentifiers

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case insufficientCoins
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return L10n.settings.errInvalidURL
        case .unauthorized: return L10n.settings.errUnauthorized
        case .insufficientCoins: return L10n.settings.errInsufficientCoins
        case .serverError(let code, let msg): return L10n.settings.errServer(code, msg)
        case .decodingError(let err): return L10n.settings.errDecoding(err.localizedDescription)
        case .networkError(let err): return err.localizedDescription
        }
    }
}

struct MacScreenRequirement: Sendable {
    let width: Int
    let height: Int

    static var current: MacScreenRequirement {
        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        return screens
            .map {
                let pixels = Self.displayModePixels(for: $0)
                return MacScreenRequirement(width: pixels.width, height: pixels.height)
            }
            .min { lhs, rhs in
                let lhsPixels = lhs.width * lhs.height
                let rhsPixels = rhs.width * rhs.height
                if lhsPixels == rhsPixels { return lhs.width < rhs.width }
                return lhsPixels < rhsPixels
            }
            ?? MacScreenRequirement(width: 1920, height: 1080)
    }

    private static func displayModePixels(for screen: NSScreen) -> (width: Int, height: Int) {
        // NSScreen.frame is the current "looks like" display mode size.
        // Do not multiply by backingScaleFactor or use the panel's native
        // pixels here; explicit My Device queries should match the user's
        // effective desktop size.
        return (
            Int(screen.frame.width.rounded()),
            Int(screen.frame.height.rounded())
        )
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
    private let analyticsSessionKey = "wpe_analytics_session_id"
    private let analyticsStampKey = "wpe_analytics_session_stamp"
    private let analyticsSessionTTL: TimeInterval = 30 * 60

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    // Shared paginated helper. Screen-size filtering is performed by the
    // backend from the native-client headers attached in request<T>, keeping
    // pagination and totals consistent across every list surface.
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
        return resp.data
    }

    func trackEvent(_ type: String, path: String, props: [String: String] = [:]) async {
        guard let url = URL(string: baseURL + "/events") else { return }
        var eventProps = props
        eventProps["client"] = "mac"
        eventProps["platform"] = "macos"
        eventProps["version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

        let payload: [String: Any] = [
            "session_id": analyticsSessionID(),
            "type": type,
            "path": path,
            "referrer": "",
            "props": eventProps,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(L10n.lang.rawValue, forHTTPHeaderField: "Accept-Language")
        req.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("mac", forHTTPHeaderField: "X-Wallpaper-Client")
        if let token = await AuthService.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            _ = try await session.data(for: req)
        } catch {
            // Telemetry must never block the native client.
        }
    }

    // Internal (not private) so extensions in sibling files can route
    // their endpoints through the same request plumbing — token attach,
    // 401/402 mapping, decoding. See APIClient+Main.swift.
    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> T {
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
        if let body {
            req.httpBody = body
            req.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        // Backend localizes content fields (category/tag names, collection
        // titles) from this header; falls back to the original text.
        req.setValue(L10n.lang.rawValue, forHTTPHeaderField: "Accept-Language")
        req.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("mac", forHTTPHeaderField: "X-Wallpaper-Client")
        let screenRequirement = MacScreenRequirement.current
        req.setValue(String(screenRequirement.width), forHTTPHeaderField: "X-Device-Width")
        req.setValue(String(screenRequirement.height), forHTTPHeaderField: "X-Device-Height")

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

    private var appUserAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "WallpaperExchange/mac \(version)"
    }

    private func analyticsSessionID() -> String {
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let last = defaults.double(forKey: analyticsStampKey)
        if let existing = defaults.string(forKey: analyticsSessionKey),
           !existing.isEmpty,
           last > 0,
           now - last < analyticsSessionTTL {
            defaults.set(now, forKey: analyticsStampKey)
            return existing
        }

        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: analyticsSessionKey)
        defaults.set(now, forKey: analyticsStampKey)
        return fresh
    }

    func fetchWallpapers(
        cursor: Int? = nil,
        limit: Int = 20,
        dynamicOnly: Bool = false,
        aiOnly: Bool = false,
        search: String? = nil,
        categoryID: Int? = nil,
        sort: String? = nil,
        deviceMatch: Bool = false,
        includeVideo: Bool = false
    ) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = []
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
        // Explicit My Device match keeps using query parameters so it can
        // override the default native-client header contract.
        if deviceMatch {
            let requirement = MacScreenRequirement.current
            items.append(.init(name: "device_width", value: String(requirement.width)))
            items.append(.init(name: "device_height", value: String(requirement.height)))
            items.append(.init(name: "include_dynamic", value: "true"))
        }
        // Hide video by default. The dynamic/live feed intentionally opts
        // video back in because the backend's dynamic_only filter spans
        // Mac dynamic wallpapers + video wallpapers, matching the web.
        if !includeVideo && !dynamicOnly {
            items.append(.init(name: "exclude_video", value: "true"))
        }
        return try await fetchWallpaperPage("/wallpapers", cursor: cursor, limit: limit, queryItems: items)
    }

    // Personalised "For You" feed — a single-shot top-N list (no cursor
    // pagination), signed-in only. Mirrors the web's GET
    // /wallpapers/for-you, which returns a plain array in `data`.
    // Create a community collection (POST /collections with a JSON body).
    func createCollection(title: String, isPublic: Bool = true) async throws -> CollectionItem {
        struct Body: Encodable { let title: String; let is_public: Bool }
        guard let url = URL(string: baseURL + "/collections") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(L10n.lang.rawValue, forHTTPHeaderField: "Accept-Language")
        req.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("mac", forHTTPHeaderField: "X-Wallpaper-Client")
        if let token = await AuthService.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(Body(title: title, is_public: isPublic))
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.networkError(error) }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw APIError.unauthorized }
            if http.statusCode >= 400 { throw APIError.networkError(URLError(.badServerResponse)) }
        }
        do {
            let resp = try decoder.decode(APIResponse<CollectionItem>.self, from: data)
            return resp.data
        } catch { throw APIError.decodingError(error) }
    }

    // ─── JSON-body writes (profile / password / privacy) ─────────
    // Shared plumbing for PUT/POST/PATCH with an Encodable body — same
    // token + 401/402 + error-envelope handling as request<T>. Returns
    // the raw envelope bytes; callers decode `data` if they need it.
    private func sendJSON<B: Encodable>(_ path: String, method: String, body: B) async throws -> Data {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(L10n.lang.rawValue, forHTTPHeaderField: "Accept-Language")
        req.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("mac", forHTTPHeaderField: "X-Wallpaper-Client")
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
            let msg = (try? decoder.decode(MessageEnvelope.self, from: data))?.message ?? L10n.settings.errRequestFailed
            throw APIError.serverError(http.statusCode, msg)
        }
        return data
    }

    private func sendAuthJSON<B: Encodable>(_ path: String, body: B) async throws -> AuthResponse {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(L10n.lang.rawValue, forHTTPHeaderField: "Accept-Language")
        req.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("mac", forHTTPHeaderField: "X-Wallpaper-Client")
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
                                       envelope?.message ?? L10n.settings.errAuthFailed)
        }

        do {
            return try decoder.decode(APIResponse<AuthResponse>.self, from: data).data
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable { let email: String; let password: String; let client: String }
        return try await sendAuthJSON("/auth/login", body: Body(email: email, password: password, client: "mac"))
    }

    func register(username: String, email: String, password: String) async throws -> AuthResponse {
        struct Body: Encodable { let username: String; let email: String; let password: String; let client: String; let source: String }
        return try await sendAuthJSON("/auth/register", body: Body(username: username, email: email, password: password, client: "mac", source: "mac_app"))
    }

    // Edit a collection's title / description / visibility (owner only;
    // the server rejects editor/weekly themes). PUT /collections/:id.
    func updateCollection(id: Int, title: String, description: String, isPublic: Bool) async throws {
        struct Body: Encodable { let title: String; let description: String; let is_public: Bool }
        _ = try await sendJSON("/collections/\(id)", method: "PUT", body: Body(title: title, description: description, is_public: isPublic))
    }

    // Add a wallpaper to one of the user's collections.
    func addToCollection(collectionID: Int, wallpaperID: Int) async throws {
        struct Body: Encodable { let wallpaper_id: Int }
        _ = try await sendJSON("/collections/\(collectionID)/wallpapers", method: "POST", body: Body(wallpaper_id: wallpaperID))
    }

    func updateProfile(nickname: String, bio: String) async throws -> User {
        struct Body: Encodable { let nickname: String; let bio: String }
        let data = try await sendJSON("/users/me/profile", method: "PUT", body: Body(nickname: nickname, bio: bio))
        return try decoder.decode(APIResponse<User>.self, from: data).data
    }

    func uploadWallpaperFile(
        fileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let url = URL(string: baseURL + "/wallpapers") else { throw APIError.invalidURL }
        guard let token = await AuthService.shared.token else { throw APIError.unauthorized }

        let boundary = "Boundary-\(UUID().uuidString)"
        let filename = fileURL.lastPathComponent
        let mime = Self.mimeType(for: fileURL)
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { fileURL.stopAccessingSecurityScopedResource() }
        }

        let fileData = try Data(contentsOf: fileURL)
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
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.upload(for: req, from: body)
        } catch {
            throw APIError.networkError(error)
        }
        try handleUploadResponse(data: data, response: response)
        progress(1)
    }

    func uploadVideoTus(
        fileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let token = await AuthService.shared.token else { throw APIError.unauthorized }
        guard let createURL = URL(string: baseURL + "/uploads/tus") else { throw APIError.invalidURL }

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { fileURL.stopAccessingSecurityScopedResource() }
        }

        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw APIError.serverError(400, L10n.settings.errEmptyFile) }

        let mime = Self.mimeType(for: fileURL)
        var create = URLRequest(url: createURL)
        create.httpMethod = "POST"
        create.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        create.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        create.setValue(String(size), forHTTPHeaderField: "Upload-Length")
        create.setValue(Self.tusMetadata([
            "filename": fileURL.lastPathComponent,
            "filetype": mime,
        ]), forHTTPHeaderField: "Upload-Metadata")

        let createResponse: URLResponse
        do {
            (_, createResponse) = try await URLSession.shared.data(for: create)
        } catch {
            throw APIError.networkError(error)
        }
        guard let http = createResponse as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode >= 400 {
            throw APIError.serverError(http.statusCode, L10n.settings.errVideoUploadStart)
        }
        guard let location = http.value(forHTTPHeaderField: "Location"),
              let uploadURL = tusUploadURL(from: location) else {
            throw APIError.serverError(http.statusCode, L10n.settings.errVideoUploadLocation)
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let chunkSize = 8 * 1024 * 1024
        var offset = 0
        while offset < size {
            let length = min(chunkSize, size - offset)
            let chunk = try handle.read(upToCount: length) ?? Data()
            guard !chunk.isEmpty else { break }

            var patch = URLRequest(url: uploadURL)
            patch.httpMethod = "PATCH"
            patch.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            patch.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
            patch.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            patch.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")

            let patchResponse: URLResponse
            do {
                (_, patchResponse) = try await URLSession.shared.upload(for: patch, from: chunk)
            } catch {
                throw APIError.networkError(error)
            }
            guard let patchHTTP = patchResponse as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }
            if patchHTTP.statusCode == 401 { throw APIError.unauthorized }
            if patchHTTP.statusCode >= 400 {
                throw APIError.serverError(patchHTTP.statusCode, L10n.settings.errVideoUploadFailed)
            }

            if let rawOffset = patchHTTP.value(forHTTPHeaderField: "Upload-Offset"),
               let serverOffset = Int(rawOffset) {
                offset = serverOffset
            } else {
                offset += chunk.count
            }
            progress(min(1, Double(offset) / Double(size)))
        }
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

    // Multipart avatar upload — POST /users/me/avatar with a single
    // `avatar` file part (same field the web FormData uses). Returns the
    // new avatar_url.
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
        if http.statusCode >= 400 { throw APIError.serverError(http.statusCode, L10n.settings.errAvatarUploadFailed) }
        struct AvatarResp: Decodable { let avatar_url: String }
        return try decoder.decode(APIResponse<AvatarResp>.self, from: data).data.avatar_url
    }

    func fetchForYou(limit: Int = 30) async throws -> [Wallpaper] {
        let items: [URLQueryItem] = [
            .init(name: "limit", value: String(limit)),
            .init(name: "exclude_video", value: "true"),
        ]
        let resp: APIResponse<[Wallpaper]> = try await request("/wallpapers/for-you", queryItems: items)
        return resp.data
    }

    func fetchMyDownloads(
        cursor: Int? = nil,
        limit: Int = 20,
        deviceWidth: Int? = nil,
        deviceHeight: Int? = nil,
        dynamicOnly: Bool = false
    ) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = []
        if !dynamicOnly {
            items.append(.init(name: "exclude_video", value: "true"))
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
        return try await fetchWallpaperPage("/users/me/downloads", cursor: cursor, limit: limit, queryItems: items)
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
    /// Always returns the original file's URL — device variants were
    /// retired on 2026-07-05; clients filter wallpapers that don't fit
    /// the screen instead of downloading resized copies.
    func getDownloadURL(wallpaperID: Int) async throws -> URL {
        let path = "/wallpapers/\(wallpaperID)/download"
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(L10n.lang.rawValue, forHTTPHeaderField: "Accept-Language")
        req.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("mac", forHTTPHeaderField: "X-Wallpaper-Client")
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
            let msg = (try? decoder.decode(MessageEnvelope.self, from: data))?.message ?? L10n.settings.errDownloadUnavailable
            throw APIError.serverError(http.statusCode, msg)
        }

        return redirectURL
    }

    private func handleUploadResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 402 { throw APIError.insufficientCoins }
        if http.statusCode >= 400 {
            let msg = (try? decoder.decode(MessageEnvelope.self, from: data))?.message ?? L10n.settings.errUploadFailed
            throw APIError.serverError(http.statusCode, msg)
        }
    }

    private func tusUploadURL(from location: String) -> URL? {
        if let absolute = URL(string: location), absolute.scheme != nil {
            return absolute
        }
        guard var components = URLComponents(string: baseURL) else { return nil }
        if location.hasPrefix("/") {
            components.path = location
            components.query = nil
            return components.url
        }
        return URL(string: location, relativeTo: URL(string: baseURL))?.absoluteURL
    }

    private static func tusMetadata(_ values: [String: String]) -> String {
        values.map { key, value in
            let encoded = Data(value.utf8).base64EncodedString()
            return "\(key) \(encoded)"
        }
        .joined(separator: ",")
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
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "mkv": return "video/x-matroska"
        default:
            if let type = UTType(filenameExtension: ext),
               let mime = type.preferredMIMEType {
                return mime
            }
            return "application/octet-stream"
        }
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
