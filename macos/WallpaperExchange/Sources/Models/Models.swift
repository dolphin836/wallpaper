import Foundation

struct APIResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T
}

struct PaginatedData<T: Decodable>: Decodable {
    let items: [T]
    let nextCursor: Int?
    let hasMore: Bool
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case items, total
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

struct User: Decodable, Identifiable {
    let id: Int
    let username: String
    let email: String?
    let nickname: String
    let avatarURL: String
    let bio: String
    let coins: Int
    let status: Int
    let createdAt: String
    let likesPublic: Bool?
    let favoritesPublic: Bool?
    let downloadsPublic: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, email, nickname, bio, coins, status
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case likesPublic = "likes_public"
        case favoritesPublic = "favorites_public"
        case downloadsPublic = "downloads_public"
    }
}

struct AuthResponse: Decodable {
    let token: String
    let user: User
}

struct Wallpaper: Decodable, Identifiable {
    let id: Int
    let slug: String
    let userID: Int
    let categoryID: Int?
    let title: String
    let description: String
    let originalURL: String
    let thumbURL: String
    let previewURL: String
    let width: Int
    let height: Int
    let fileSize: Int
    let fileType: String
    let dominantColor: String?
    let colorPalette: String?
    let status: Int
    let viewCount: Int
    let likeCount: Int
    let downloadCount: Int
    let favoriteCount: Int
    let isDynamic: Bool
    let isAIGenerated: Bool?
    let isLiked: Bool?
    let isFavorited: Bool?
    let isDownloaded: Bool?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, width, height, status
        case userID = "user_id"
        case categoryID = "category_id"
        case originalURL = "original_url"
        case thumbURL = "thumb_url"
        case previewURL = "preview_url"
        case fileSize = "file_size"
        case fileType = "file_type"
        case dominantColor = "dominant_color"
        case colorPalette = "color_palette"
        case viewCount = "view_count"
        case likeCount = "like_count"
        case downloadCount = "download_count"
        case favoriteCount = "favorite_count"
        case isDynamic = "is_dynamic"
        case isAIGenerated = "is_ai_generated"
        case isLiked = "is_liked"
        case isFavorited = "is_favorited"
        case isDownloaded = "is_downloaded"
        case createdAt = "created_at"
    }

    var displayURL: String {
        previewURL.isEmpty ? thumbURL : previewURL
    }

    var resolutionLabel: String {
        let px = max(width, height)
        if px >= 7680 { return "8K" }
        if px >= 3840 { return "4K" }
        if px >= 2560 { return "2K" }
        if px >= 1920 { return "1080P" }
        if px >= 1280 { return "720P" }
        if px > 0    { return "\(width)×\(height)" }
        // Wallpapers seeded before the variant-pipeline backfilled width
        // and height columns can come back with zero. Fall back to a
        // generic chip so every tile carries a label — the design spec
        // calls for a resolution chip on every tile.
        return "HD"
    }
}

/// A wallpaper selection carries the visible source list into detail so
/// previous/next navigation can switch immediately from the list snapshot
/// while the richer detail request is still in flight.
typealias WallpaperSelectionHandler = (_ wallpaper: Wallpaper, _ navigationItems: [Wallpaper]) -> Void

struct CoinsResponse: Decodable {
    let coins: Int
}
