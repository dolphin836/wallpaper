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

    func fetchUserUploads(username: String, cursor: Int? = nil, limit: Int = 24) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let c = cursor { items.append(.init(name: "cursor", value: String(c))) }
        let resp: APIResponse<PaginatedData<Wallpaper>> = try await request("/users/\(username)/wallpapers", queryItems: items)
        return resp.data
    }

    func fetchUserLikes(username: String, cursor: Int? = nil, limit: Int = 24) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let c = cursor { items.append(.init(name: "cursor", value: String(c))) }
        let resp: APIResponse<PaginatedData<Wallpaper>> = try await request("/users/\(username)/likes", queryItems: items)
        return resp.data
    }

    func fetchUserFavorites(username: String, cursor: Int? = nil, limit: Int = 24) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let c = cursor { items.append(.init(name: "cursor", value: String(c))) }
        let resp: APIResponse<PaginatedData<Wallpaper>> = try await request("/users/\(username)/favorites", queryItems: items)
        return resp.data
    }

    func fetchUserDownloads(username: String, cursor: Int? = nil, limit: Int = 24) async throws -> PaginatedData<Wallpaper> {
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let c = cursor { items.append(.init(name: "cursor", value: String(c))) }
        let resp: APIResponse<PaginatedData<Wallpaper>> = try await request("/users/\(username)/downloads", queryItems: items)
        return resp.data
    }

    // ─── Collections ─────────────────────────────────────────────
    func fetchMyCollections(q: String? = nil, wallpaperID: Int? = nil, limit: Int = 50) async throws -> [CollectionBrief] {
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let q, !q.isEmpty { items.append(.init(name: "q", value: q)) }
        if let w = wallpaperID, w > 0 { items.append(.init(name: "wallpaper_id", value: String(w))) }
        let resp: APIResponse<[CollectionBrief]> = try await request("/users/me/collections", queryItems: items)
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
        var items: [URLQueryItem] = [.init(name: "limit", value: String(limit))]
        if let c = cursor { items.append(.init(name: "cursor", value: String(c))) }
        let resp: APIResponse<PaginatedData<Wallpaper>> = try await request("/collections/\(collectionID)/wallpapers", queryItems: items)
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

