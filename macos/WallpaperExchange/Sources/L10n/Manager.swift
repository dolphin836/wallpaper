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
    let autoShuffleTooltipOn: String
    let autoShuffleTooltipOff: (String) -> String
    let autoShuffleBannerTitle: String
    let autoShuffleBannerMessage: (String) -> String
    let autoShuffleNext: (Int, Int) -> String
    let autoShuffleNextUnknown: String
    let macDynamicShowingOnly: String
    let macDynamicShowOnly: String
    let revealDownloadsFolder: String
    let openInBrowser: String
    let localDiskUsedHelp: String

    // WallpaperError
    let fileUnavailable: String
    let autoRotateCollectionEmpty: String
}

private let managerEN = ManagerStrings(
    intervalMinutes: { n in n == 1 ? "1 minute" : "\(n) minutes" },
    intervalHours: { n in n == 1 ? "1 hour" : "\(n) hours" },
    intervalDays: { n in n == 1 ? "1 day" : "\(n) days" },
    intervalHoursMinutes: { h, m in "\(h == 1 ? "1 h" : "\(h) h") \(m) min" },
    autoShuffleTooltipOn: "Auto-shuffle on — click to stop",
    autoShuffleTooltipOff: { "Auto-shuffle every \($0)" },
    autoShuffleBannerTitle: "Auto-shuffle is on. ",
    autoShuffleBannerMessage: { "Pulling from your downloads every \($0)." },
    autoShuffleNext: { h, m in "NEXT · \(h) H \(m) M" },
    autoShuffleNextUnknown: "NEXT · —",
    macDynamicShowingOnly: "Showing only macOS dynamic wallpapers",
    macDynamicShowOnly: "Show only macOS dynamic wallpapers",
    revealDownloadsFolder: "Reveal the downloads folder in Finder",
    openInBrowser: "Open in browser",
    localDiskUsedHelp: "Local disk used by cached wallpapers",
    fileUnavailable: "Wallpaper file is not available locally.",
    autoRotateCollectionEmpty: "This collection does not contain any wallpapers."
)

private let managerZhCN = ManagerStrings(
    intervalMinutes: { n in "\(n) 分钟" },
    intervalHours: { n in "\(n) 小时" },
    intervalDays: { n in "\(n) 天" },
    intervalHoursMinutes: { h, m in "\(h) 小时 \(m) 分钟" },
    autoShuffleTooltipOn: "自动轮换已开启，点击停止",
    autoShuffleTooltipOff: { "每 \($0) 自动轮换" },
    autoShuffleBannerTitle: "自动轮换已开启。",
    autoShuffleBannerMessage: { "每 \($0) 从我的下载中切换壁纸。" },
    autoShuffleNext: { h, m in "下次 · \(h) 小时 \(m) 分钟" },
    autoShuffleNextUnknown: "下次 · —",
    macDynamicShowingOnly: "当前只显示 macOS 动态壁纸",
    macDynamicShowOnly: "只显示 macOS 动态壁纸",
    revealDownloadsFolder: "在访达中显示下载目录",
    openInBrowser: "在浏览器中打开",
    localDiskUsedHelp: "缓存壁纸占用的本地磁盘空间",
    fileUnavailable: "本地没有该壁纸文件。",
    autoRotateCollectionEmpty: "这个合集里还没有壁纸。"
)

private let managerZhTW = ManagerStrings(
    intervalMinutes: { n in "\(n) 分鐘" },
    intervalHours: { n in "\(n) 小時" },
    intervalDays: { n in "\(n) 天" },
    intervalHoursMinutes: { h, m in "\(h) 小時 \(m) 分鐘" },
    autoShuffleTooltipOn: "自動輪換已開啟，點擊停止",
    autoShuffleTooltipOff: { "每 \($0) 自動輪換" },
    autoShuffleBannerTitle: "自動輪換已開啟。",
    autoShuffleBannerMessage: { "每 \($0) 從我的下載中切換桌布。" },
    autoShuffleNext: { h, m in "下次 · \(h) 小時 \(m) 分鐘" },
    autoShuffleNextUnknown: "下次 · —",
    macDynamicShowingOnly: "目前只顯示 macOS 動態桌布",
    macDynamicShowOnly: "只顯示 macOS 動態桌布",
    revealDownloadsFolder: "在 Finder 中顯示下載資料夾",
    openInBrowser: "在瀏覽器中開啟",
    localDiskUsedHelp: "快取桌布占用的本機磁碟空間",
    fileUnavailable: "本機沒有該桌布檔案。",
    autoRotateCollectionEmpty: "這個合輯裡還沒有桌布。"
)

private let managerJA = ManagerStrings(
    intervalMinutes: { n in "\(n)分" },
    intervalHours: { n in "\(n)時間" },
    intervalDays: { n in "\(n)日" },
    intervalHoursMinutes: { h, m in "\(h)時間\(m)分" },
    autoShuffleTooltipOn: "自動シャッフルはオンです。クリックで停止",
    autoShuffleTooltipOff: { "\($0)ごとに自動シャッフル" },
    autoShuffleBannerTitle: "自動シャッフルはオンです。",
    autoShuffleBannerMessage: { "\($0)ごとにダウンロードから壁紙を切り替えます。" },
    autoShuffleNext: { h, m in "次回 · \(h)時間 \(m)分" },
    autoShuffleNextUnknown: "次回 · —",
    macDynamicShowingOnly: "macOS 動的壁紙のみ表示中",
    macDynamicShowOnly: "macOS 動的壁紙のみ表示",
    revealDownloadsFolder: "ダウンロードフォルダを Finder で表示",
    openInBrowser: "ブラウザで開く",
    localDiskUsedHelp: "キャッシュ壁紙が使用しているローカルディスク容量",
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
