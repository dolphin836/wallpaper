import SwiftUI

// Inline sample data so the preview app needs zero auth / network.
// Picsum.photos serves random photos against a deterministic seed so
// repeat loads cache the same image — good enough for layout review.

struct DemoWallpaper: Identifiable, Hashable {
    static func == (lhs: DemoWallpaper, rhs: DemoWallpaper) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: Int
    let title: String
    let category: String
    let tags: [String]
    let width: Int
    let height: Int
    let fileSize: String     // human readable
    let dominant: Color
    let palette: [Color]
    let uploader: String
    let likes: Int
    let downloads: Int
    let isDynamic: Bool

    var resolutionLabel: String {
        let m = max(width, height)
        if m >= 7680 { return "8K" }
        if m >= 3840 { return "4K" }
        if m >= 2560 { return "2K" }
        if m >= 1920 { return "1080P" }
        return "HD"
    }

    var previewURL: URL {
        // picsum.photos with a stable seed → deterministic preview tile.
        URL(string: "https://picsum.photos/seed/wpe-\(id)/1280/720")!
    }
}

enum DemoData {
    static let wallpapers: [DemoWallpaper] = [
        DemoWallpaper(
            id: 101, title: "Misty Pine Forest on Mountain Slopes",
            category: "Nature", tags: ["forest", "mountain", "mist", "moody", "pines"],
            width: 3840, height: 2160, fileSize: "2.3 MB",
            dominant: Color(red: 0.18, green: 0.32, blue: 0.27),
            palette: [
                Color(red: 0.12, green: 0.18, blue: 0.16),
                Color(red: 0.22, green: 0.32, blue: 0.28),
                Color(red: 0.38, green: 0.48, blue: 0.42),
                Color(red: 0.64, green: 0.66, blue: 0.58),
                Color(red: 0.88, green: 0.86, blue: 0.78),
            ],
            uploader: "forest_walker", likes: 88, downloads: 142, isDynamic: false
        ),
        DemoWallpaper(
            id: 102, title: "Hallstatt at Dusk",
            category: "City", tags: ["village", "lake", "alps", "europe"],
            width: 5120, height: 2880, fileSize: "3.4 MB",
            dominant: Color(red: 0.28, green: 0.32, blue: 0.46),
            palette: [
                Color(red: 0.14, green: 0.18, blue: 0.28),
                Color(red: 0.28, green: 0.32, blue: 0.46),
                Color(red: 0.55, green: 0.46, blue: 0.40),
                Color(red: 0.82, green: 0.62, blue: 0.42),
                Color(red: 0.92, green: 0.78, blue: 0.58),
            ],
            uploader: "alps_dreaming", likes: 211, downloads: 380, isDynamic: false
        ),
        DemoWallpaper(
            id: 103, title: "Neon Bedroom",
            category: "Tech", tags: ["cyberpunk", "neon", "interior"],
            width: 3840, height: 2160, fileSize: "1.9 MB",
            dominant: Color(red: 0.62, green: 0.18, blue: 0.42),
            palette: [
                Color(red: 0.10, green: 0.06, blue: 0.18),
                Color(red: 0.32, green: 0.10, blue: 0.30),
                Color(red: 0.62, green: 0.18, blue: 0.42),
                Color(red: 0.18, green: 0.42, blue: 0.62),
                Color(red: 0.30, green: 0.72, blue: 0.78),
            ],
            uploader: "syntwave_kid", likes: 144, downloads: 240, isDynamic: true
        ),
        DemoWallpaper(
            id: 104, title: "Abstract Curves",
            category: "Abstract", tags: ["gradient", "curves", "minimal"],
            width: 2560, height: 1440, fileSize: "1.1 MB",
            dominant: Color(red: 0.55, green: 0.45, blue: 0.78),
            palette: [
                Color(red: 0.42, green: 0.30, blue: 0.62),
                Color(red: 0.55, green: 0.45, blue: 0.78),
                Color(red: 0.70, green: 0.60, blue: 0.85),
                Color(red: 0.90, green: 0.78, blue: 0.86),
                Color(red: 0.98, green: 0.88, blue: 0.74),
            ],
            uploader: "form_studies", likes: 60, downloads: 92, isDynamic: false
        ),
        DemoWallpaper(
            id: 105, title: "Dolomites Village",
            category: "Nature", tags: ["mountains", "village", "alpine"],
            width: 5120, height: 2880, fileSize: "3.8 MB",
            dominant: Color(red: 0.36, green: 0.42, blue: 0.50),
            palette: [
                Color(red: 0.16, green: 0.22, blue: 0.30),
                Color(red: 0.36, green: 0.42, blue: 0.50),
                Color(red: 0.62, green: 0.62, blue: 0.58),
                Color(red: 0.82, green: 0.76, blue: 0.65),
                Color(red: 0.96, green: 0.90, blue: 0.78),
            ],
            uploader: "alpine_archive", likes: 320, downloads: 540, isDynamic: false
        ),
        DemoWallpaper(
            id: 106, title: "Tifa, Final Fantasy VII Remake",
            category: "Game", tags: ["tifa", "fanart", "ffvii"],
            width: 2160, height: 3840, fileSize: "1.4 MB",
            dominant: Color(red: 0.48, green: 0.24, blue: 0.30),
            palette: [
                Color(red: 0.20, green: 0.12, blue: 0.16),
                Color(red: 0.48, green: 0.24, blue: 0.30),
                Color(red: 0.78, green: 0.42, blue: 0.36),
                Color(red: 0.92, green: 0.70, blue: 0.50),
                Color(red: 0.98, green: 0.88, blue: 0.72),
            ],
            uploader: "fanart_dropoff", likes: 412, downloads: 712, isDynamic: false
        ),
        DemoWallpaper(
            id: 107, title: "Studio Gradient · Orange Blue",
            category: "Abstract", tags: ["gradient", "studio", "warm"],
            width: 3840, height: 2160, fileSize: "0.9 MB",
            dominant: Color(red: 0.92, green: 0.55, blue: 0.32),
            palette: [
                Color(red: 0.96, green: 0.78, blue: 0.62),
                Color(red: 0.92, green: 0.55, blue: 0.32),
                Color(red: 0.65, green: 0.32, blue: 0.22),
                Color(red: 0.32, green: 0.32, blue: 0.48),
                Color(red: 0.18, green: 0.22, blue: 0.42),
            ],
            uploader: "gradient_house", likes: 88, downloads: 132, isDynamic: false
        ),
        DemoWallpaper(
            id: 108, title: "Cozy Cafe with Cat",
            category: "Anime", tags: ["cozy", "cafe", "illustration"],
            width: 3840, height: 2160, fileSize: "1.7 MB",
            dominant: Color(red: 0.42, green: 0.62, blue: 0.45),
            palette: [
                Color(red: 0.24, green: 0.36, blue: 0.28),
                Color(red: 0.42, green: 0.62, blue: 0.45),
                Color(red: 0.78, green: 0.78, blue: 0.42),
                Color(red: 0.95, green: 0.72, blue: 0.40),
                Color(red: 0.98, green: 0.90, blue: 0.75),
            ],
            uploader: "studio_pixel", likes: 220, downloads: 354, isDynamic: false
        ),
        DemoWallpaper(
            id: 109, title: "Night Lake, Milky Way",
            category: "Nature", tags: ["night", "stars", "milky-way"],
            width: 4000, height: 2250, fileSize: "2.7 MB",
            dominant: Color(red: 0.16, green: 0.18, blue: 0.32),
            palette: [
                Color(red: 0.06, green: 0.08, blue: 0.18),
                Color(red: 0.16, green: 0.18, blue: 0.32),
                Color(red: 0.36, green: 0.40, blue: 0.62),
                Color(red: 0.70, green: 0.70, blue: 0.82),
                Color(red: 0.95, green: 0.95, blue: 0.95),
            ],
            uploader: "night_sky_logs", likes: 510, downloads: 880, isDynamic: false
        ),
        DemoWallpaper(
            id: 110, title: "Brooklyn Bridge at Sunset",
            category: "City", tags: ["nyc", "bridge", "sunset"],
            width: 4096, height: 2304, fileSize: "2.4 MB",
            dominant: Color(red: 0.82, green: 0.42, blue: 0.28),
            palette: [
                Color(red: 0.22, green: 0.10, blue: 0.12),
                Color(red: 0.56, green: 0.26, blue: 0.22),
                Color(red: 0.82, green: 0.42, blue: 0.28),
                Color(red: 0.96, green: 0.68, blue: 0.42),
                Color(red: 0.98, green: 0.88, blue: 0.68),
            ],
            uploader: "boroughs", likes: 188, downloads: 290, isDynamic: false
        ),
        DemoWallpaper(
            id: 111, title: "Aerial Canyon Road",
            category: "Nature", tags: ["canyon", "river", "aerial"],
            width: 3840, height: 2160, fileSize: "2.1 MB",
            dominant: Color(red: 0.58, green: 0.38, blue: 0.28),
            palette: [
                Color(red: 0.28, green: 0.18, blue: 0.14),
                Color(red: 0.58, green: 0.38, blue: 0.28),
                Color(red: 0.82, green: 0.65, blue: 0.48),
                Color(red: 0.46, green: 0.55, blue: 0.40),
                Color(red: 0.92, green: 0.92, blue: 0.86),
            ],
            uploader: "aerial_atlas", likes: 240, downloads: 410, isDynamic: false
        ),
        DemoWallpaper(
            id: 112, title: "Cabin by the Alpine Lake",
            category: "Nature", tags: ["cabin", "lake", "alpine"],
            width: 3840, height: 2160, fileSize: "2.0 MB",
            dominant: Color(red: 0.32, green: 0.42, blue: 0.50),
            palette: [
                Color(red: 0.14, green: 0.20, blue: 0.26),
                Color(red: 0.32, green: 0.42, blue: 0.50),
                Color(red: 0.65, green: 0.58, blue: 0.42),
                Color(red: 0.85, green: 0.78, blue: 0.60),
                Color(red: 0.95, green: 0.92, blue: 0.85),
            ],
            uploader: "lake_house_log", likes: 165, downloads: 268, isDynamic: false
        ),
    ]

    // Sidebar destinations the demo renders. Counts are sample values.
    static let destinations: [DemoDestination] = [
        DemoDestination(id: "discover",  label: "Discover",        icon: "sparkles",                  badge: nil,    section: .browse),
        DemoDestination(id: "weekly",    label: "Weekly Picks",    icon: "calendar.badge.clock",      badge: "23",   section: .browse),
        DemoDestination(id: "device",    label: "For Your Device", icon: "laptopcomputer",            badge: "4K",   section: .browse),
        DemoDestination(id: "category",  label: "Categories",      icon: "square.grid.3x2",           badge: nil,    section: .browse),
        DemoDestination(id: "downloads", label: "Downloads",       icon: "arrow.down.circle",         badge: "12",   section: .mine),
        DemoDestination(id: "collections", label: "Collections",   icon: "rectangle.stack",           badge: "5",    section: .mine),
        DemoDestination(id: "liked",     label: "Liked",           icon: "heart",                     badge: "47",   section: .mine),
        DemoDestination(id: "uploaded",  label: "Uploaded by Me",  icon: "tray.and.arrow.up",         badge: "8",    section: .mine),
    ]
}

struct DemoDestination: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    let badge: String?
    let section: SidebarSection
}

enum SidebarSection: String, CaseIterable {
    case browse = "Browse"
    case mine = "My Library"
}
