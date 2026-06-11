import Foundation

// Endpoints needed by the v2 main window — kept in a separate
// extension file so the popover-era surface in APIClient.swift stays
// untouched and reviewable. All methods route through the shared
// `request<T>` helper (token attached, 401 → APIError.unauthorized).
extension APIClient {

    // ─── Detail / similar ────────────────────────────────────────
    func fetchWallpaperDetail(slug: String) async throws -> WallpaperDetail {
        let resp: APIResponse<WallpaperDetail> = try await request("/wallpapers/\(slug)")
        return resp.data
    }

    // Returns the lighter Wallpaper shape — same as fetchWallpapers —
    // for the 'More like this' grid on the detail page.
    func fetchSimilarWallpapers(wallpaperID: Int, limit: Int = 12) async throws -> [Wallpaper] {
        let resp: APIResponse<[Wallpaper]> = try await request(
            "/wallpapers/\(wallpaperID)/similar",
            queryItems: [.init(name: "limit", value: String(limit))]
        )
        return resp.data
    }

    // ─── Categories ──────────────────────────────────────────────
    func fetchCategories() async throws -> [Category] {
        let resp: APIResponse<[Category]> = try await request("/categories")
        return resp.data
    }

    // ─── Profile (public) ────────────────────────────────────────
    func fetchPublicProfile(username: String) async throws -> PublicProfile {
        let resp: APIResponse<PublicProfile> = try await request("/users/\(username)")
        return resp.data
    }

    // `status` mirrors the web Uploads tab: "1" = published, "0,5" =
    // pending/processing (owner-only). Omitted → server default.
    func fetchUserUploads(
        username: String,
        cursor: Int? = nil,
        limit: Int = 24,
        status: String? = nil
    ) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = []
        if let s = status, !s.isEmpty { items.append(.init(name: "status", value: s)) }
        return try await fetchWallpaperPage("/users/\(username)/wallpapers", cursor: cursor, limit: limit, queryItems: items)
    }

    func fetchUserLikes(username: String, cursor: Int? = nil, limit: Int = 24) async throws -> PaginatedData<Wallpaper> {
        try await fetchWallpaperPage("/users/\(username)/likes", cursor: cursor, limit: limit)
    }

    func fetchUserFavorites(username: String, cursor: Int? = nil, limit: Int = 24) async throws -> PaginatedData<Wallpaper> {
        try await fetchWallpaperPage("/users/\(username)/favorites", cursor: cursor, limit: limit)
    }

    func fetchUserDownloads(username: String, cursor: Int? = nil, limit: Int = 24) async throws -> PaginatedData<Wallpaper> {
        try await fetchWallpaperPage("/users/\(username)/downloads", cursor: cursor, limit: limit)
    }

    // ─── Collections ─────────────────────────────────────────────
    func fetchMyCollections(q: String? = nil, wallpaperID: Int? = nil, limit: Int = 50) async throws -> [CollectionBrief] {
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let q, !q.isEmpty { items.append(.init(name: "q", value: q)) }
        if let w = wallpaperID, w > 0 { items.append(.init(name: "wallpaper_id", value: String(w))) }
        let resp: APIResponse<[CollectionBrief]> = try await request("/users/me/collections", queryItems: items)
        return resp.data
    }

    // A user's own collections (paginated, with covers) — the profile
    // Collections tab. Route accepts a numeric id or a username.
    func fetchUserCollections(idOrUsername: String, cursor: Int? = nil, limit: Int = 12) async throws -> PaginatedData<CollectionItem> {
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let c = cursor { items.append(.init(name: "cursor", value: String(c))) }
        let resp: APIResponse<PaginatedData<CollectionItem>> = try await request("/users/\(idOrUsername)/collections", queryItems: items)
        return resp.data
    }

    func fetchPublicCollections(cursor: Int? = nil, limit: Int = 24) async throws -> PaginatedData<CollectionItem> {
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let c = cursor { items.append(.init(name: "cursor", value: String(c))) }
        let resp: APIResponse<PaginatedData<CollectionItem>> = try await request("/collections", queryItems: items)
        return resp.data
    }

    func fetchCollection(slug: String) async throws -> CollectionItem {
        let resp: APIResponse<CollectionItem> = try await request("/collections/\(slug)")
        return resp.data
    }

    func fetchCollectionWallpapers(collectionID: Int, cursor: Int? = nil, limit: Int = 24) async throws -> PaginatedData<Wallpaper> {
        try await fetchWallpaperPage("/collections/\(collectionID)/wallpapers", cursor: cursor, limit: limit)
    }

    // ─── Weekly Picks ────────────────────────────────────────────
    func fetchWeeklyCurrent() async throws -> WeeklyCurrent {
        let resp: APIResponse<WeeklyCurrent> = try await request("/weekly-picks/current")
        return resp.data
    }

    func fetchWeeklyArchive(limit: Int = 50) async throws -> [WeeklyArchiveEntry] {
        let resp: APIResponse<[WeeklyArchiveEntry]> = try await request(
            "/weekly-picks/archive",
            queryItems: [.init(name: "limit", value: String(limit))]
        )
        return resp.data
    }

    func fetchWeeklyByWeek(year: Int, week: Int) async throws -> WeeklyByWeek {
        let resp: APIResponse<WeeklyByWeek> = try await request("/weekly-picks/\(year)/\(week)")
        return resp.data
    }

    // ─── Devices ─────────────────────────────────────────────────
    func fetchDevices() async throws -> [DeviceProfile] {
        let resp: APIResponse<[DeviceProfile]> = try await request("/devices")
        return resp.data
    }

    func fetchDevice(slug: String) async throws -> DeviceProfileDetail {
        let resp: APIResponse<DeviceProfileDetail> = try await request("/devices/\(slug)")
        return resp.data
    }

    func fetchDeviceWallpapers(slug: String, cursor: Int? = nil, limit: Int = 24) async throws -> PaginatedData<Wallpaper> {
        try await fetchWallpaperPage("/devices/\(slug)/wallpapers", cursor: cursor, limit: limit)
    }

    // ─── Uploaders ───────────────────────────────────────────────
    func fetchUploaders(sort: String = "trending", page: Int = 1, limit: Int = 24) async throws -> UploaderListResponse {
        let resp: APIResponse<UploaderListResponse> = try await request(
            "/users",
            queryItems: [
                .init(name: "sort", value: sort),
                .init(name: "page", value: String(page)),
                .init(name: "limit", value: String(limit)),
            ]
        )
        return resp.data
    }

    // ─── Coins ledger ────────────────────────────────────────────
    func fetchCoinTransactions(cursor: Int? = nil, limit: Int = 30) async throws -> PaginatedData<CoinTransaction> {
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let c = cursor { items.append(.init(name: "cursor", value: String(c))) }
        let resp: APIResponse<PaginatedData<CoinTransaction>> = try await request("/users/me/coin-transactions", queryItems: items)
        return resp.data
    }

    // ─── Engagement actions ──────────────────────────────────────
    func like(wallpaperID: Int) async throws {
        let _: APIResponse<EmptyData> = try await request("/wallpapers/\(wallpaperID)/like", method: "POST")
    }
    func unlike(wallpaperID: Int) async throws {
        let _: APIResponse<EmptyData> = try await request("/wallpapers/\(wallpaperID)/like", method: "DELETE")
    }
    func favorite(wallpaperID: Int) async throws {
        let _: APIResponse<EmptyData> = try await request("/wallpapers/\(wallpaperID)/favorite", method: "POST")
    }
    func unfavorite(wallpaperID: Int) async throws {
        let _: APIResponse<EmptyData> = try await request("/wallpapers/\(wallpaperID)/favorite", method: "DELETE")
    }
}

// Empty response body for write actions that only signal success/fail
// via HTTP status. We still expect the envelope so re-using the same
// `request<T>` helper means we don't have to special-case auth/error
// handling for these paths.
struct EmptyData: Decodable {}
