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
    let lockScreenBackup: String
    let lockScreenBackupDetail: String
    let lockScreenRestore: String
    let lockScreenRestoreConfirmTitle: String
    let lockScreenRestoreConfirmMessage: String
    let lockScreenRestoreSucceeded: String
    let lockScreenRestoreUnavailable: String
    let lockScreenRestoreFailed: (String) -> String

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
    lockScreenBackup: "Apple lock screen",
    lockScreenBackupDetail: "Restore the original Apple Aerial files backed up before custom lock screens were applied.",
    lockScreenRestore: "Restore original",
    lockScreenRestoreConfirmTitle: "Restore the original Apple lock screen?",
    lockScreenRestoreConfirmMessage: "This removes the custom lock screen and restores every Apple Aerial file changed by Wallpaper Exchange.",
    lockScreenRestoreSucceeded: "The original Apple lock screen has been restored.",
    lockScreenRestoreUnavailable: "No Apple lock screen backup is available.",
    lockScreenRestoreFailed: { "Could not restore the Apple lock screen: \($0)" },
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
    lockScreenBackup: "Apple 锁屏",
    lockScreenBackupDetail: "恢复设置自定义锁屏前备份的 Apple 航拍原始文件。",
    lockScreenRestore: "恢复原始锁屏",
    lockScreenRestoreConfirmTitle: "恢复 Apple 原始锁屏？",
    lockScreenRestoreConfirmMessage: "会移除自定义锁屏，并恢复 Wallpaper Exchange 修改过的所有 Apple 航拍文件。",
    lockScreenRestoreSucceeded: "已恢复 Apple 原始锁屏。",
    lockScreenRestoreUnavailable: "当前没有可恢复的 Apple 锁屏备份。",
    lockScreenRestoreFailed: { "恢复 Apple 锁屏失败：\($0)" },
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
    lockScreenBackup: "Apple 鎖定畫面",
    lockScreenBackupDetail: "還原套用自訂鎖定畫面前備份的 Apple 空拍原始檔案。",
    lockScreenRestore: "還原原始鎖定畫面",
    lockScreenRestoreConfirmTitle: "還原 Apple 原始鎖定畫面？",
    lockScreenRestoreConfirmMessage: "會移除自訂鎖定畫面，並還原 Wallpaper Exchange 修改過的所有 Apple 空拍檔案。",
    lockScreenRestoreSucceeded: "已還原 Apple 原始鎖定畫面。",
    lockScreenRestoreUnavailable: "目前沒有可還原的 Apple 鎖定畫面備份。",
    lockScreenRestoreFailed: { "還原 Apple 鎖定畫面失敗：\($0)" },
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
    lockScreenBackup: "Apple ロック画面",
    lockScreenBackupDetail: "カスタムロック画面の適用前にバックアップした Apple Aerial の元ファイルを復元します。",
    lockScreenRestore: "元に戻す",
    lockScreenRestoreConfirmTitle: "Apple の元のロック画面を復元しますか？",
    lockScreenRestoreConfirmMessage: "カスタムロック画面を削除し、Wallpaper Exchange が変更したすべての Apple Aerial ファイルを復元します。",
    lockScreenRestoreSucceeded: "Apple の元のロック画面を復元しました。",
    lockScreenRestoreUnavailable: "復元できる Apple ロック画面のバックアップがありません。",
    lockScreenRestoreFailed: { "Apple ロック画面を復元できませんでした：\($0)" },
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
