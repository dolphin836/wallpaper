import Foundation

// Mirror of backend/internal/handler/mac_release.json — served at
// GET /api/v1/mac/release. Only the fields the updater actually reads
// are decoded; other keys (releases array, min_macos_version, etc.) are
// ignored.
struct MacRelease: Decodable {
    let currentVersion: String
    let currentDmgURL: String
    let releases: [MacReleaseEntry]?

    enum CodingKeys: String, CodingKey {
        case currentVersion = "current_version"
        case currentDmgURL = "current_dmg_url"
        case releases
    }
}

struct MacReleaseEntry: Decodable {
    let version: String
    let releasedAt: String?
    let notes: [String]?

    enum CodingKeys: String, CodingKey {
        case version
        case releasedAt = "released_at"
        case notes
    }
}
