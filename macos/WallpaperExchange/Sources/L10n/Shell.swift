import Foundation

// Window-shell strings: MainWindow sidebar items + toolbar, MainSidebar
// section headers / identity footer, the AppDelegate status-bar menu,
// and the App.swift "Open Wallpaper Exchange" command. The four
// instances share one memberwise init, so a missing translation fails
// the build.

struct ShellStrings {
    // Sidebar items (also reused as toolbar labels / tooltips).
    let home: String
    let discover: String
    let weekly: String
    let collections: String
    let generative: String
    let myUploads: String
    let myCollections: String
    let myDownloads: String
    let myFavorites: String
    let myLikes: String
    let myCoins: String
    let upload: String
    let settings: String

    // Sidebar section headers (rendered as caps kickers).
    let browseSection: String
    let myLibrarySection: String

    // Identity footer / signed-out states.
    let signIn: String
    let notSignedIn: String
    let signInToViewLibrary: String
    let signInToViewAccount: String

    // Toolbar tooltips.
    let back: String
    let forward: String
    let refreshPage: String
    let switchToLight: String
    let switchToDark: String
    let expandSidebar: String
    let collapseSidebar: String
    let resourceUsage: String
    let currentProcess: String
    let cpuUsage: String
    let memoryUsage: String

    // Status-bar menu (AppDelegate) + App.swift command.
    let openApp: String
    let launchAtLogin: String
    let launchAtLoginNeedsApproval: String
    let checkForUpdates: String
    let quitApp: String

    // Launch-at-login failure alert.
    let launchErrorTitle: String
    let launchErrorHint: String
    let ok: String
}

private let shellEN = ShellStrings(
    home: "Home",
    discover: "Discover",
    weekly: "Weekly",
    collections: "Collections",
    generative: "Generative",
    myUploads: "My Uploads",
    myCollections: "My Collections",
    myDownloads: "My Downloads",
    myFavorites: "My Favorites",
    myLikes: "My Likes",
    myCoins: "My Coins",
    upload: "Upload",
    settings: "Settings",
    browseSection: "BROWSE",
    myLibrarySection: "MY LIBRARY",
    signIn: "Sign in",
    notSignedIn: "Not signed in",
    signInToViewLibrary: "Sign in to view My Library",
    signInToViewAccount: "Sign in to view your account.",
    back: "Back",
    forward: "Forward",
    refreshPage: "Refresh current page",
    switchToLight: "Switch to light theme",
    switchToDark: "Switch to dark theme",
    expandSidebar: "Expand sidebar",
    collapseSidebar: "Collapse sidebar",
    resourceUsage: "Resource usage",
    currentProcess: "Current app process",
    cpuUsage: "CPU",
    memoryUsage: "Memory",
    openApp: "Open Wallpaper Exchange",
    launchAtLogin: "Launch at Login",
    launchAtLoginNeedsApproval: "Launch at Login (needs approval in System Settings)",
    checkForUpdates: "Check for Updates…",
    quitApp: "Quit Wallpaper Exchange",
    launchErrorTitle: "Couldn't update launch-at-login setting",
    launchErrorHint: "Make sure Wallpaper Exchange lives in /Applications and try again.",
    ok: "OK"
)

private let shellZhCN = ShellStrings(
    home: "首页",
    discover: "发现",
    weekly: "每周精选",
    collections: "合集",
    generative: "生成",
    myUploads: "我的上传",
    myCollections: "我的合集",
    myDownloads: "我的下载",
    myFavorites: "我的收藏",
    myLikes: "我的点赞",
    myCoins: "我的金币",
    upload: "上传",
    settings: "设置",
    browseSection: "浏览",
    myLibrarySection: "我的资料库",
    signIn: "登录",
    notSignedIn: "未登录",
    signInToViewLibrary: "登录后查看我的资料库",
    signInToViewAccount: "登录后即可查看你的账户。",
    back: "后退",
    forward: "前进",
    refreshPage: "刷新当前页面",
    switchToLight: "切换到浅色主题",
    switchToDark: "切换到深色主题",
    expandSidebar: "展开侧边栏",
    collapseSidebar: "收起侧边栏",
    resourceUsage: "资源占用",
    currentProcess: "当前应用进程",
    cpuUsage: "CPU",
    memoryUsage: "内存",
    openApp: "打开 Wallpaper Exchange",
    launchAtLogin: "登录时启动",
    launchAtLoginNeedsApproval: "登录时启动（需在系统设置中批准）",
    checkForUpdates: "检查更新…",
    quitApp: "退出 Wallpaper Exchange",
    launchErrorTitle: "无法更新登录时启动设置",
    launchErrorHint: "请确认 Wallpaper Exchange 已位于 /Applications 文件夹，然后重试。",
    ok: "好"
)

private let shellZhTW = ShellStrings(
    home: "首頁",
    discover: "探索",
    weekly: "每週精選",
    collections: "合輯",
    generative: "生成",
    myUploads: "我的上傳",
    myCollections: "我的合輯",
    myDownloads: "我的下載",
    myFavorites: "我的收藏",
    myLikes: "我的按讚",
    myCoins: "我的金幣",
    upload: "上傳",
    settings: "設定",
    browseSection: "瀏覽",
    myLibrarySection: "我的資料庫",
    signIn: "登入",
    notSignedIn: "未登入",
    signInToViewLibrary: "登入後查看我的資料庫",
    signInToViewAccount: "登入後即可查看你的帳戶。",
    back: "返回",
    forward: "前進",
    refreshPage: "重新整理目前頁面",
    switchToLight: "切換至淺色主題",
    switchToDark: "切換至深色主題",
    expandSidebar: "展開側邊欄",
    collapseSidebar: "收合側邊欄",
    resourceUsage: "資源占用",
    currentProcess: "目前應用程式程序",
    cpuUsage: "CPU",
    memoryUsage: "記憶體",
    openApp: "開啟 Wallpaper Exchange",
    launchAtLogin: "登入時啟動",
    launchAtLoginNeedsApproval: "登入時啟動（需在系統設定中核准）",
    checkForUpdates: "檢查更新…",
    quitApp: "結束 Wallpaper Exchange",
    launchErrorTitle: "無法更新登入時啟動設定",
    launchErrorHint: "請確認 Wallpaper Exchange 已位於 /Applications 資料夾，然後再試一次。",
    ok: "好"
)

private let shellJA = ShellStrings(
    home: "ホーム",
    discover: "発見",
    weekly: "ウィークリー",
    collections: "コレクション",
    generative: "生成",
    myUploads: "マイアップロード",
    myCollections: "マイコレクション",
    myDownloads: "マイダウンロード",
    myFavorites: "お気に入り",
    myLikes: "いいね",
    myCoins: "マイコイン",
    upload: "アップロード",
    settings: "設定",
    browseSection: "ブラウズ",
    myLibrarySection: "マイライブラリ",
    signIn: "サインイン",
    notSignedIn: "未サインイン",
    signInToViewLibrary: "サインインしてマイライブラリを表示",
    signInToViewAccount: "サインインするとアカウントを表示できます。",
    back: "戻る",
    forward: "進む",
    refreshPage: "現在のページを再読み込み",
    switchToLight: "ライトテーマに切り替え",
    switchToDark: "ダークテーマに切り替え",
    expandSidebar: "サイドバーを展開",
    collapseSidebar: "サイドバーを折りたたむ",
    resourceUsage: "リソース使用量",
    currentProcess: "現在のアプリプロセス",
    cpuUsage: "CPU",
    memoryUsage: "メモリ",
    openApp: "Wallpaper Exchange を開く",
    launchAtLogin: "ログイン時に起動",
    launchAtLoginNeedsApproval: "ログイン時に起動（システム設定での承認が必要）",
    checkForUpdates: "アップデートを確認…",
    quitApp: "Wallpaper Exchange を終了",
    launchErrorTitle: "ログイン時に起動の設定を変更できませんでした",
    launchErrorHint: "Wallpaper Exchange が /Applications にあることを確認して、もう一度お試しください。",
    ok: "OK"
)

extension L10n {
    static var shell: ShellStrings {
        switch lang {
        case .en: shellEN
        case .zhCN: shellZhCN
        case .zhTW: shellZhTW
        case .ja: shellJA
        }
    }
}
