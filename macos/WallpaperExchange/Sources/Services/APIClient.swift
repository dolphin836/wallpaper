import Foundation
import AppKit
import UniformTypeIdentifiers

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case insufficientCoins
    case unsupportedResolution
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "Please log in"
        case .insufficientCoins: return "Insufficient coins"
        case .unsupportedResolution: return "This wallpaper is too small for the current display"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .decodingError(let err): return "Decode error: \(err.localizedDescription)"
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
                MacScreenRequirement(
                    width: Int(($0.frame.width * $0.backingScaleFactor).rounded()),
                    height: Int(($0.frame.height * $0.backingScaleFactor).rounded())
                )
            }
            .min { lhs, rhs in
                let lhsPixels = lhs.width * lhs.height
                let rhsPixels = rhs.width * rhs.height
                if lhsPixels == rhsPixels { return lhs.width < rhs.width }
                return lhsPixels < rhsPixels
            }
            ?? MacScreenRequirement(width: 1920, height: 1080)
    }

    func supports(width: Int, height: Int) -> Bool {
        width >= self.width && height >= self.height
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

    func compatibleWallpapers(_ wallpapers: [Wallpaper]) -> [Wallpaper] {
        let requirement = MacScreenRequirement.current
        return wallpapers.filter { requirement.supports(width: $0.width, height: $0.height) }
    }

    // Keep following server cursors when a page contains undersized
    // wallpapers so a compatible feed never appears empty prematurely.
    func fetchCompatibleWallpaperPage(
        _ path: String,
        cursor: Int?,
        limit: Int,
        queryItems: [URLQueryItem] = []
    ) async throws -> PaginatedData<Wallpaper> {
        var accepted: [Wallpaper] = []
        var nextCursor = cursor
        var hasMore = true
        var total: Int?
        var rounds = 0
        let maxRounds = limit <= 1 ? 1 : 50

        while accepted.count < limit && hasMore && rounds < maxRounds {
            rounds += 1
            let previousCursor = nextCursor
            var items = queryItems
            items.append(.init(name: "limit", value: String(max(1, limit - accepted.count))))
            if let nextCursor {
                items.append(.init(name: "cursor", value: String(nextCursor)))
            }

            let resp: APIResponse<PaginatedData<Wallpaper>> = try await request(path, queryItems: items)
            let page = resp.data
            accepted.append(contentsOf: compatibleWallpapers(page.items))
            total = total ?? page.total
            nextCursor = page.nextCursor
            hasMore = page.hasMore

            if hasMore && nextCursor == previousCursor {
                hasMore = false
            }
        }

        return PaginatedData(items: accepted, nextCursor: nextCursor, hasMore: hasMore, total: total)
    }

    func requireCompatibleDetail(_ detail: WallpaperDetail) throws -> WallpaperDetail {
        guard MacScreenRequirement.current.supports(width: detail.width, height: detail.height) else {
            throw APIError.unsupportedResolution
        }
        return detail
    }

    func compatibleWeeklyPicks(_ picks: [WeeklyPicked]) -> [WeeklyPicked] {
        let requirement = MacScreenRequirement.current
        return picks.filter { requirement.supports(width: $0.width, height: $0.height) }
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
        // Device-resolution match — sends this Mac's physical pixel
        // dimensions so the backend filters to wallpapers with a
        // matching variant.
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
        return try await fetchCompatibleWallpaperPage("/wallpapers", cursor: cursor, limit: limit, queryItems: items)
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
        guard size > 0 else { throw APIError.serverError(400, "Empty file") }

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
            throw APIError.serverError(http.statusCode, "Video upload could not start")
        }
        guard let location = http.value(forHTTPHeaderField: "Location"),
              let uploadURL = tusUploadURL(from: location) else {
            throw APIError.serverError(http.statusCode, "Video upload location missing")
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
                throw APIError.serverError(patchHTTP.statusCode, "Video upload failed")
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
        if http.statusCode >= 400 { throw APIError.serverError(http.statusCode, "Avatar upload failed") }
        struct AvatarResp: Decodable { let avatar_url: String }
        return try decoder.decode(APIResponse<AvatarResp>.self, from: data).data.avatar_url
    }

    func fetchForYou(limit: Int = 30) async throws -> [Wallpaper] {
        let requestLimit = min(60, max(limit, limit * 2))
        let items: [URLQueryItem] = [
            .init(name: "limit", value: String(requestLimit)),
            .init(name: "exclude_video", value: "true"),
        ]
        let resp: APIResponse<[Wallpaper]> = try await request("/wallpapers/for-you", queryItems: items)
        return Array(compatibleWallpapers(resp.data).prefix(limit))
    }

    func fetchMyDownloads(
        cursor: Int? = nil,
        limit: Int = 20,
        deviceWidth: Int? = nil,
        deviceHeight: Int? = nil,
        dynamicOnly: Bool = false
    ) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = [
            // The mac client can't render video wallpapers. Downloads are
            // cross-platform, so drop any video the user pulled elsewhere.
            .init(name: "exclude_video", value: "true"),
        ]
        // Same mutual exclusion as fetchWallpapers — dynamic-only wins over
        // resolution match when both are conceptually set.
        if dynamicOnly {
            items.append(.init(name: "dynamic_only", value: "true"))
        } else if let w = deviceWidth, let h = deviceHeight, w > 0, h > 0 {
            items.append(.init(name: "device_width", value: String(w)))
            items.append(.init(name: "device_height", value: String(h)))
            items.append(.init(name: "include_dynamic", value: "true"))
        }
        return try await fetchCompatibleWallpaperPage("/users/me/downloads", cursor: cursor, limit: limit, queryItems: items)
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

    private func handleUploadResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 402 { throw APIError.insufficientCoins }
        if http.statusCode >= 400 {
            let msg = (try? decoder.decode(MessageEnvelope.self, from: data))?.message ?? "Upload failed"
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
private struct MessageEnvelope: Decodable { let message: String? }

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
