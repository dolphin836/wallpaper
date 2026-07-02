import Foundation

// Strings for the Settings page (account / appearance / storage /
// session cards — the Language card uses L10n.common) plus the
// user-facing APIError messages surfaced from APIClient. Same pattern
// as Common.swift — one memberwise init shared by four instances, so a
// missing translation fails the build.

struct SettingsStrings {
    // Page header
    let kicker: String
    let title: String

    // Account
    let account: String
    let openProfile: String
    let profileEditingNote: String
    let notSignedIn: String
    let signIn: String

    // Appearance
    let appearance: String
    let theme: String
    let themeSystem: String
    let themeLight: String
    let themeDark: String

    // Storage
    let storage: String
    let downloadsFolder: String
    let revealInFinder: String
    let localCache: String
    let localCacheUsed: (String) -> String
    let clearDownloads: String
    let clearDownloadsConfirmTitle: String
    let clearDownloadsDelete: (String) -> String
    let clearDownloadsConfirmMessage: String

    // About
    let about: String
    let version: (String) -> String
    let checkForUpdates: String

    // Session
    let session: String
    let signOut: String
    let signOutDesc: String

    // APIError — user-facing error messages
    let errInvalidURL: String
    let errUnauthorized: String
    let errInsufficientCoins: String
    let errServer: (Int, String) -> String
    let errDecoding: (String) -> String
    let errRequestFailed: String
    let errAuthFailed: String
    let errEmptyFile: String
    let errVideoUploadStart: String
    let errVideoUploadLocation: String
    let errVideoUploadFailed: String
    let errAvatarUploadFailed: String
    let errUploadFailed: String
    let errDownloadUnavailable: String
}

private let settingsEN = SettingsStrings(
    kicker: "SETTINGS",
    title: "Preferences.",
    account: "Account",
    openProfile: "Open profile",
    profileEditingNote: "Profile editing on macOS is coming soon. For now, edit your nickname, avatar, and password on the web site.",
    notSignedIn: "Not signed in.",
    signIn: "Sign in",
    appearance: "Appearance",
    theme: "Theme",
    themeSystem: "System",
    themeLight: "Light",
    themeDark: "Dark",
    storage: "Storage",
    downloadsFolder: "Downloads folder",
    revealInFinder: "Reveal in Finder",
    localCache: "Local cache",
    localCacheUsed: { "\($0) used by downloaded wallpapers" },
    clearDownloads: "Clear downloads",
    clearDownloadsConfirmTitle: "Clear all downloaded wallpapers?",
    clearDownloadsDelete: { "Delete \($0)" },
    clearDownloadsConfirmMessage: "Removes every wallpaper file from the local downloads folder. Your download history stays on the server and files can be re-downloaded.",
    about: "About",
    version: { "Version \($0)" },
    checkForUpdates: "Check for updates",
    session: "Session",
    signOut: "Sign out",
    signOutDesc: "Clear local session and return to the sign-in screen",
    errInvalidURL: "Invalid URL",
    errUnauthorized: "Please log in",
    errInsufficientCoins: "Insufficient coins",
    errServer: { "Server error (\($0)): \($1)" },
    errDecoding: { "Decode error: \($0)" },
    errRequestFailed: "Request failed",
    errAuthFailed: "Authentication failed",
    errEmptyFile: "Empty file",
    errVideoUploadStart: "Video upload could not start",
    errVideoUploadLocation: "Video upload location missing",
    errVideoUploadFailed: "Video upload failed",
    errAvatarUploadFailed: "Avatar upload failed",
    errUploadFailed: "Upload failed",
    errDownloadUnavailable: "Download is not available"
)

private let settingsZhCN = SettingsStrings(
    kicker: "设置",
    title: "偏好设置。",
    account: "账户",
    openProfile: "打开个人主页",
    profileEditingNote: "macOS 端的资料编辑即将上线。目前请在网页端修改昵称、头像和密码。",
    notSignedIn: "未登录。",
    signIn: "登录",
    appearance: "外观",
    theme: "主题",
    themeSystem: "跟随系统",
    themeLight: "浅色",
    themeDark: "深色",
    storage: "存储",
    downloadsFolder: "下载目录",
    revealInFinder: "在访达中显示",
    localCache: "本地缓存",
    localCacheUsed: { "已使用 \($0) 存储已下载壁纸" },
    clearDownloads: "清除下载",
    clearDownloadsConfirmTitle: "清除所有已下载壁纸？",
    clearDownloadsDelete: { "删除 \($0)" },
    clearDownloadsConfirmMessage: "会移除本地下载目录中的所有壁纸文件。你的下载记录会保留在服务器上，之后仍可重新下载。",
    about: "关于",
    version: { "版本 \($0)" },
    checkForUpdates: "检查更新",
    session: "会话",
    signOut: "退出登录",
    signOutDesc: "清除本地会话并返回登录界面",
    errInvalidURL: "无效的 URL",
    errUnauthorized: "请先登录",
    errInsufficientCoins: "金币不足",
    errServer: { "服务器错误（\($0)）：\($1)" },
    errDecoding: { "解析错误：\($0)" },
    errRequestFailed: "请求失败",
    errAuthFailed: "认证失败",
    errEmptyFile: "文件为空",
    errVideoUploadStart: "视频上传无法开始",
    errVideoUploadLocation: "缺少视频上传地址",
    errVideoUploadFailed: "视频上传失败",
    errAvatarUploadFailed: "头像上传失败",
    errUploadFailed: "上传失败",
    errDownloadUnavailable: "当前无法下载"
)

private let settingsZhTW = SettingsStrings(
    kicker: "設定",
    title: "偏好設定。",
    account: "帳戶",
    openProfile: "開啟個人頁面",
    profileEditingNote: "macOS 版的個人資料編輯即將推出。目前請在網站上修改暱稱、頭像和密碼。",
    notSignedIn: "尚未登入。",
    signIn: "登入",
    appearance: "外觀",
    theme: "主題",
    themeSystem: "跟隨系統",
    themeLight: "淺色",
    themeDark: "深色",
    storage: "儲存空間",
    downloadsFolder: "下載資料夾",
    revealInFinder: "在 Finder 中顯示",
    localCache: "本機快取",
    localCacheUsed: { "已使用 \($0) 儲存已下載桌布" },
    clearDownloads: "清除下載",
    clearDownloadsConfirmTitle: "清除所有已下載桌布？",
    clearDownloadsDelete: { "刪除 \($0)" },
    clearDownloadsConfirmMessage: "會移除本機下載資料夾中的所有桌布檔案。你的下載記錄會保留在伺服器上，之後仍可重新下載。",
    about: "關於",
    version: { "版本 \($0)" },
    checkForUpdates: "檢查更新",
    session: "工作階段",
    signOut: "登出",
    signOutDesc: "清除本機工作階段並返回登入畫面",
    errInvalidURL: "無效的 URL",
    errUnauthorized: "請先登入",
    errInsufficientCoins: "金幣不足",
    errServer: { "伺服器錯誤（\($0)）：\($1)" },
    errDecoding: { "解析錯誤：\($0)" },
    errRequestFailed: "請求失敗",
    errAuthFailed: "驗證失敗",
    errEmptyFile: "檔案為空",
    errVideoUploadStart: "影片上傳無法開始",
    errVideoUploadLocation: "缺少影片上傳位址",
    errVideoUploadFailed: "影片上傳失敗",
    errAvatarUploadFailed: "頭像上傳失敗",
    errUploadFailed: "上傳失敗",
    errDownloadUnavailable: "目前無法下載"
)

private let settingsJA = SettingsStrings(
    kicker: "設定",
    title: "環境設定。",
    account: "アカウント",
    openProfile: "プロフィールを開く",
    profileEditingNote: "macOSでのプロフィール編集は近日対応予定です。現時点ではニックネーム・アバター・パスワードはWebサイトで編集してください。",
    notSignedIn: "サインインしていません。",
    signIn: "サインイン",
    appearance: "外観",
    theme: "テーマ",
    themeSystem: "システム",
    themeLight: "ライト",
    themeDark: "ダーク",
    storage: "ストレージ",
    downloadsFolder: "ダウンロードフォルダ",
    revealInFinder: "Finderで表示",
    localCache: "ローカルキャッシュ",
    localCacheUsed: { "ダウンロード済み壁紙が \($0) 使用中" },
    clearDownloads: "ダウンロードを削除",
    clearDownloadsConfirmTitle: "ダウンロード済み壁紙をすべて削除しますか？",
    clearDownloadsDelete: { "\($0) を削除" },
    clearDownloadsConfirmMessage: "ローカルのダウンロードフォルダ内にある壁紙ファイルをすべて削除します。ダウンロード履歴はサーバーに残り、後で再ダウンロードできます。",
    about: "情報",
    version: { "バージョン \($0)" },
    checkForUpdates: "アップデートを確認",
    session: "セッション",
    signOut: "ログアウト",
    signOutDesc: "ローカルセッションを消去してサインイン画面に戻ります",
    errInvalidURL: "無効なURLです",
    errUnauthorized: "ログインしてください",
    errInsufficientCoins: "コインが不足しています",
    errServer: { "サーバーエラー（\($0)）：\($1)" },
    errDecoding: { "デコードエラー：\($0)" },
    errRequestFailed: "リクエストに失敗しました",
    errAuthFailed: "認証に失敗しました",
    errEmptyFile: "ファイルが空です",
    errVideoUploadStart: "動画のアップロードを開始できませんでした",
    errVideoUploadLocation: "動画アップロード先が見つかりません",
    errVideoUploadFailed: "動画のアップロードに失敗しました",
    errAvatarUploadFailed: "アバターのアップロードに失敗しました",
    errUploadFailed: "アップロードに失敗しました",
    errDownloadUnavailable: "ダウンロードは現在利用できません"
)

extension L10n {
    static var settings: SettingsStrings {
        switch lang {
        case .en: settingsEN
        case .zhCN: settingsZhCN
        case .zhTW: settingsZhTW
        case .ja: settingsJA
        }
    }
}
