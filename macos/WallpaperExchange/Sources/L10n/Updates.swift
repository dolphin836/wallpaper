import Foundation

// UpdateService strings: check-result alerts, the upgrade prompt, and
// the download-progress panel. Built per presentation (NSAlert/NSPanel),
// so they pick up the current language naturally. The four instances
// share one memberwise init, so a missing translation fails the build.

struct UpdatesStrings {
    // Check results.
    let checkFailedTitle: String
    let checkFailedMessage: (String) -> String   // error description
    let upToDateTitle: String
    let upToDateMessage: (String) -> String      // current version

    // Upgrade prompt.
    let newVersionTitle: (String) -> String      // latest version
    let versionComparison: (String, String) -> String  // (current, latest)
    let whatsNew: String
    let installNow: String
    let later: String

    // Install pipeline failures.
    let updateFailedTitle: String
    let badDownloadURL: String
    let downloadFailed: (String) -> String       // error description
    let mountFailed: (String) -> String          // error description
    let noAppInInstaller: String

    // Progress panel.
    let panelTitle: String
    let downloadingVersion: (String) -> String   // version
    let connecting: String
    let installing: String
    let restarting: String
    let downloadedSoFar: (String) -> String      // e.g. "12.3 MB"

    let ok: String
}

private let updatesEN = UpdatesStrings(
    checkFailedTitle: "Couldn't check for updates",
    checkFailedMessage: { "Network or server error: \($0)" },
    upToDateTitle: "You're up to date",
    upToDateMessage: { "Wallpaper Exchange \($0) is the latest version." },
    newVersionTitle: { "New version available — \($0)" },
    versionComparison: { current, latest in "You're running \(current). The latest release is \(latest)." },
    whatsNew: "What's new:",
    installNow: "Install Now",
    later: "Later",
    updateFailedTitle: "Update failed",
    badDownloadURL: "Bad download URL.",
    downloadFailed: { "Download failed: \($0)" },
    mountFailed: { "Couldn't mount the installer: \($0)" },
    noAppInInstaller: "The installer didn't contain an app bundle.",
    panelTitle: "Wallpaper Exchange Update",
    downloadingVersion: { "Downloading version \($0)…" },
    connecting: "Connecting…",
    installing: "Installing…",
    restarting: "Restarting…",
    downloadedSoFar: { "\($0) downloaded" },
    ok: "OK"
)

private let updatesZhCN = UpdatesStrings(
    checkFailedTitle: "无法检查更新",
    checkFailedMessage: { "网络或服务器错误：\($0)" },
    upToDateTitle: "已是最新版本",
    upToDateMessage: { "Wallpaper Exchange \($0) 已是最新版本。" },
    newVersionTitle: { "发现新版本 — \($0)" },
    versionComparison: { current, latest in "当前版本为 \(current)，最新版本为 \(latest)。" },
    whatsNew: "更新内容：",
    installNow: "立即安装",
    later: "稍后",
    updateFailedTitle: "更新失败",
    badDownloadURL: "下载地址无效。",
    downloadFailed: { "下载失败：\($0)" },
    mountFailed: { "无法挂载安装镜像：\($0)" },
    noAppInInstaller: "安装包中未找到应用。",
    panelTitle: "Wallpaper Exchange 更新",
    downloadingVersion: { "正在下载 \($0)…" },
    connecting: "正在连接…",
    installing: "正在安装…",
    restarting: "正在重新启动…",
    downloadedSoFar: { "已下载 \($0)" },
    ok: "好"
)

private let updatesZhTW = UpdatesStrings(
    checkFailedTitle: "無法檢查更新",
    checkFailedMessage: { "網路或伺服器錯誤：\($0)" },
    upToDateTitle: "已是最新版本",
    upToDateMessage: { "Wallpaper Exchange \($0) 已是最新版本。" },
    newVersionTitle: { "發現新版本 — \($0)" },
    versionComparison: { current, latest in "目前版本為 \(current)，最新版本為 \(latest)。" },
    whatsNew: "更新內容：",
    installNow: "立即安裝",
    later: "稍後",
    updateFailedTitle: "更新失敗",
    badDownloadURL: "下載位址無效。",
    downloadFailed: { "下載失敗：\($0)" },
    mountFailed: { "無法掛載安裝映像檔：\($0)" },
    noAppInInstaller: "安裝套件中未找到應用程式。",
    panelTitle: "Wallpaper Exchange 更新",
    downloadingVersion: { "正在下載 \($0)…" },
    connecting: "正在連線…",
    installing: "正在安裝…",
    restarting: "正在重新啟動…",
    downloadedSoFar: { "已下載 \($0)" },
    ok: "好"
)

private let updatesJA = UpdatesStrings(
    checkFailedTitle: "アップデートを確認できませんでした",
    checkFailedMessage: { "ネットワークまたはサーバーエラー：\($0)" },
    upToDateTitle: "最新の状態です",
    upToDateMessage: { "Wallpaper Exchange \($0) は最新バージョンです。" },
    newVersionTitle: { "新しいバージョンがあります — \($0)" },
    versionComparison: { current, latest in "現在のバージョンは \(current) です。最新リリースは \(latest) です。" },
    whatsNew: "新機能：",
    installNow: "今すぐインストール",
    later: "あとで",
    updateFailedTitle: "アップデートに失敗しました",
    badDownloadURL: "ダウンロード URL が無効です。",
    downloadFailed: { "ダウンロードに失敗しました：\($0)" },
    mountFailed: { "インストーラーをマウントできませんでした：\($0)" },
    noAppInInstaller: "インストーラーにアプリが含まれていませんでした。",
    panelTitle: "Wallpaper Exchange アップデート",
    downloadingVersion: { "バージョン \($0) をダウンロード中…" },
    connecting: "接続中…",
    installing: "インストール中…",
    restarting: "再起動しています…",
    downloadedSoFar: { "\($0) ダウンロード済み" },
    ok: "OK"
)

extension L10n {
    static var updates: UpdatesStrings {
        switch lang {
        case .en: updatesEN
        case .zhCN: updatesZhCN
        case .zhTW: updatesZhTW
        case .ja: updatesJA
        }
    }
}
