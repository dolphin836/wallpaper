import Foundation

// Additional models needed by the v2 main window. The original
// Models.swift covers the popover's lighter Wallpaper / User shapes;
// these add Tag, Category, Collection, plus the richer WallpaperDetail
// the new full-page detail consumes (uploader + tags + similar +
// engagement counts, hydrated by /wallpapers/:slug).

struct Tag: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String?
}

struct Category: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case sortOrder = "sort_order"
    }
}

// Lightweight uploader shape returned by /wallpapers/:slug. Same fields
// the web's UploaderCard uses.
struct WallpaperUploader: Decodable, Hashable {
    let id: Int
    let username: String
    let nickname: String?
    let avatarURL: String?
    let bio: String?

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, bio
        case avatarURL = "avatar_url"
    }
}

// WallpaperDetail — returned by /wallpapers/:slug. Layered on top of
// the lighter Wallpaper carried in the popover's lists so the new
// detail page can render uploader card, tags, and palette without
// extra round-trips.
struct WallpaperDetail: Decodable, Identifiable {
    let id: Int
    let slug: String
    let title: String
    let description: String?
    let width: Int
    let height: Int
    let fileSize: Int
    let fileType: String
    let dominantColor: String?
    let colorPalette: String?     // comma-separated hex string
    let frameURLs: String?        // comma-separated, dynamic wallpapers only
    let originalURL: String
    let thumbURL: String
    let previewURL: String
    let previewVideoURL: String?
    let viewCount: Int
    let likeCount: Int
    let downloadCount: Int
    let favoriteCount: Int
    let isDynamic: Bool
    let isAIGenerated: Bool?
    let isLiked: Bool?
    let isFavorited: Bool?
    let isDownloaded: Bool?
    let categoryID: Int?
    let userID: Int
    let createdAt: String
    let tags: [Tag]?
    let uploader: WallpaperUploader?

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, width, height, tags, uploader
        case fileSize = "file_size"
        case fileType = "file_type"
        case dominantColor = "dominant_color"
        case colorPalette = "color_palette"
        case frameURLs = "frame_urls"
        case originalURL = "original_url"
        case thumbURL = "thumb_url"
        case previewURL = "preview_url"
        case previewVideoURL = "preview_video_url"
        case viewCount = "view_count"
        case likeCount = "like_count"
        case downloadCount = "download_count"
        case favoriteCount = "favorite_count"
        case isDynamic = "is_dynamic"
        case isAIGenerated = "is_ai_generated"
        case isLiked = "is_liked"
        case isFavorited = "is_favorited"
        case isDownloaded = "is_downloaded"
        case categoryID = "category_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }

    var resolutionLabel: String {
        let px = max(width, height)
        if px >= 7680 { return "8K" }
        if px >= 3840 { return "4K" }
        if px >= 2560 { return "2K" }
        if px >= 1920 { return "1080P" }
        return "HD"
    }
    var paletteList: [String] {
        (colorPalette ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    var displayURL: String {
        previewURL.isEmpty ? thumbURL : previewURL
    }
}

// Collection (brief and detail). Mirrors the web's CollectionBrief +
// the public collection list rows.
struct CollectionBrief: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let wallpaperCount: Int
    let containsWallpaper: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title
        case wallpaperCount = "wallpaper_count"
        case containsWallpaper = "contains_wallpaper"
    }
}

struct CollectionItem: Decodable, Identifiable, Hashable {
    let id: Int
    let slug: String
    let title: String
    let coverURL: String?
    let wallpaperCount: Int
    let isPublic: Bool?
    let userID: Int?
    let createdAt: String?
    let recentTiles: [CollectionTile]?

    enum CodingKeys: String, CodingKey {
        case id, slug, title
        case coverURL = "cover_url"
        case wallpaperCount = "wallpaper_count"
        case isPublic = "is_public"
        case userID = "user_id"
        case createdAt = "created_at"
        case recentTiles = "recent_tiles"
    }
}

struct CollectionTile: Decodable, Hashable {
    let thumbURL: String
    let previewURL: String
    let dominantColor: String

    enum CodingKeys: String, CodingKey {
        case thumbURL = "thumb_url"
        case previewURL = "preview_url"
        case dominantColor = "dominant_color"
    }
}

// Weekly Picks. The current rail powers the home / weekly page hero
// strip; archive lists past weeks; byWeek is a specific week's full
// pick set.
struct WeeklyPicked: Decodable, Identifiable {
    let id: Int
    let slug: String
    let title: String
    let originalURL: String
    let thumbURL: String
    let previewURL: String
    let width: Int
    let height: Int
    let fileSize: Int
    let fileType: String
    let dominantColor: String?
    let isDynamic: Bool
    let isAIGenerated: Bool?
    let sortOrder: Int
    let isHero: Bool

    enum CodingKeys: String, CodingKey {
        case id, slug, title, width, height
        case originalURL = "original_url"
        case thumbURL = "thumb_url"
        case previewURL = "preview_url"
        case fileSize = "file_size"
        case fileType = "file_type"
        case dominantColor = "dominant_color"
        case isDynamic = "is_dynamic"
        case isAIGenerated = "is_ai_generated"
        case sortOrder = "sort_order"
        case isHero = "is_hero"
    }
}

struct WeeklyCurrent: Decodable {
    let year: Int
    let week: Int
    let picks: [WeeklyPicked]
    // themes is optional on Mac — we don't render the theme rail there yet.
    let themes: [CollectionItem]?
}

struct WeeklyByWeek: Decodable {
    let year: Int
    let week: Int
    let picks: [WeeklyPicked]
}

struct WeeklyArchiveEntry: Decodable, Identifiable, Hashable {
    var id: String { "\(year)-\(week)" }
    let year: Int
    let week: Int
    let count: Int
    let coverURL: String
    let accentColor: String?
    let dominantColor: String?
    let colorPalette: String?

    enum CodingKeys: String, CodingKey {
        case year, week, count
        case coverURL = "cover_url"
        case accentColor = "accent_color"
        case dominantColor = "dominant_color"
        case colorPalette = "color_palette"
    }
}

// Devices. /devices returns a flat list of all supported device
// profiles; /devices/:slug returns one with its wallpaper count + a
// `wallpaper_count` envelope used by the device detail page.
struct DeviceProfile: Decodable, Identifiable, Hashable {
    let id: Int
    let platform: String
    let brand: String
    let name: String
    let slug: String
    let width: Int
    let height: Int
    let ppi: Int
    let sortOrder: Int
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, platform, brand, name, slug, width, height, ppi
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }
}

struct DeviceProfileDetail: Decodable {
    let device: DeviceProfile
    let wallpaperCount: Int

    enum CodingKeys: String, CodingKey {
        case device
        case wallpaperCount = "wallpaper_count"
    }
}

// Uploader card on the Uploaders index. wallpaper_count + total_downloads
// are aggregates the backend joins in; recent_thumbs/tints power the
// small thumbnail strip the web's UploadersPage renders.
struct UploaderListItem: Decodable, Identifiable, Hashable {
    let id: Int
    let username: String
    let nickname: String
    let avatarURL: String
    let bio: String
    let wallpaperCount: Int
    let totalDownloads: Int
    let recentThumbs: [String]?
    let recentTints: [String]?

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, bio
        case avatarURL = "avatar_url"
        case wallpaperCount = "wallpaper_count"
        case totalDownloads = "total_downloads"
        case recentThumbs = "recent_thumbs"
        case recentTints = "recent_tints"
    }
}

struct UploaderListResponse: Decodable {
    let items: [UploaderListItem]
    let total: Int
}

struct PublicProfile: Decodable {
    let id: Int
    let username: String
    let nickname: String?
    let avatarURL: String?
    let bio: String?
    let uploadCount: Int?
    let downloadCount: Int?
    let likeCount: Int?
    let collectionCount: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, bio
        case avatarURL = "avatar_url"
        case uploadCount = "upload_count"
        case downloadCount = "download_count"
        case likeCount = "like_count"
        case collectionCount = "collection_count"
        case createdAt = "created_at"
    }
}
