import Foundation

// WallpaperManager / VideoWallpaperController user-facing strings: the
// auto-rotate interval label and the LocalizedError shown when a wallpaper
// file is missing locally. One memberwise init shared by the four
// instances — a missing translation fails the build.

struct ManagerStrings {
    // Auto-rotate interval label (ShuffleStatusBanner / settings)
    let intervalMinutes: (Int) -> String
    let intervalHours: (Int) -> String
    let intervalDays: (Int) -> String
    let intervalHoursMinutes: (Int, Int) -> String   // (hours, minutes)

    // WallpaperError
    let fileUnavailable: String
    let autoRotateCollectionEmpty: String
}

private let managerEN = ManagerStrings(
    intervalMinutes: { n in n == 1 ? "1 minute" : "\(n) minutes" },
    intervalHours: { n in n == 1 ? "1 hour" : "\(n) hours" },
    intervalDays: { n in n == 1 ? "1 day" : "\(n) days" },
    intervalHoursMinutes: { h, m in "\(h == 1 ? "1 h" : "\(h) h") \(m) min" },
    fileUnavailable: "Wallpaper file is not available locally.",
    autoRotateCollectionEmpty: "This collection does not contain any wallpapers."
)

private let managerZhCN = ManagerStrings(
    intervalMinutes: { n in "\(n) 分钟" },
    intervalHours: { n in "\(n) 小时" },
    intervalDays: { n in "\(n) 天" },
    intervalHoursMinutes: { h, m in "\(h) 小时 \(m) 分钟" },
    fileUnavailable: "本地没有该壁纸文件。",
    autoRotateCollectionEmpty: "这个合集里还没有壁纸。"
)

private let managerZhTW = ManagerStrings(
    intervalMinutes: { n in "\(n) 分鐘" },
    intervalHours: { n in "\(n) 小時" },
    intervalDays: { n in "\(n) 天" },
    intervalHoursMinutes: { h, m in "\(h) 小時 \(m) 分鐘" },
    fileUnavailable: "本機沒有該桌布檔案。",
    autoRotateCollectionEmpty: "這個合輯裡還沒有桌布。"
)

private let managerJA = ManagerStrings(
    intervalMinutes: { n in "\(n)分" },
    intervalHours: { n in "\(n)時間" },
    intervalDays: { n in "\(n)日" },
    intervalHoursMinutes: { h, m in "\(h)時間\(m)分" },
    fileUnavailable: "壁紙ファイルがローカルにありません。",
    autoRotateCollectionEmpty: "このコレクションにはまだ壁紙がありません。"
)

extension L10n {
    static var manager: ManagerStrings {
        switch lang {
        case .en: managerEN
        case .zhCN: managerZhCN
        case .zhTW: managerZhTW
        case .ja: managerJA
        }
    }
}
