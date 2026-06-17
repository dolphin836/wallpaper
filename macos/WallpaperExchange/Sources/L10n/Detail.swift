import Foundation

// DetailPage strings (full-page wallpaper detail: stage panel, action bar,
// notices, meta grid, recommendations, live video preview). One memberwise
// init shared by the four instances — a missing translation fails the build.

struct DetailStrings {
    // Preview mode picker
    let previewWallpaper: String
    let previewPlain: String
    let previewHome: String
    let previewLock: String

    // Breadcrumb kicker
    let specimen: (Int) -> String

    // Download progress bar
    let downloadingOriginal: String
    let preparingOriginal: String

    // Download notices
    let uploadToEarn: String
    let noticeDownloadedTitle: String
    let noticeSetTitle: String
    let noticeInsufficientCoinsTitle: String
    let noticeUnavailableTitle: String
    let noticeFailedTitle: String
    let noticeSuccessMessage: (String, String) -> String   // (file label, size)
    let noticeSetMessage: String
    let noticeInsufficientCoinsMessage: (Int) -> String    // (coin balance)
    let noticeUnavailableMessage: String

    // Hero chips
    let chipLive: String

    // Social actions
    let liked: String
    let like: String
    let saved: String
    let favorite: String
    let addToList: String
    let noCollections: String

    // Stats strip kickers
    let statDownloads: String
    let statLikes: String
    let statFavorited: String
    let statViews: String

    // Meta grid
    let uploadedBy: String
    let viewProfile: String
    let unknownUploader: String
    let about: String
    let wallpaperTitle: String
    let palette: String
    let paletteColors: (Int) -> String                     // (color count)
    let dominant: (String) -> String                       // (hex code)

    // Recommendations
    let relatedArchive: String
    let moreLikeThis: String
    let picksCount: (Int) -> String                        // (pick count)

    // Download buttons
    let gotIt: String
    let downloading: String
    let tradeForOne: String
    let download: String
    let setAsWallpaper: String
    let downloadAndSetCoin: String
    let downloadAndSet: String
    let wallpaperPickerTitle: String
    let wallpaperSurfaceDesktop: String
    let wallpaperSurfaceLockScreen: String
    let wallpaperSurfaceBoth: String
    let wallpaperChooseDisplay: String
    let wallpaperAllDisplays: String
    let wallpaperAllDisplaysDetail: (Int) -> String        // (display count)
    let wallpaperMainDisplay: String
    let wallpaperSecondaryDisplay: String
    let wallpaperApply: String
    let wallpaperApplying: String
    let wallpaperPanelHint: String
    let wallpaperVideoLockUnavailable: String
    let lockScreenUnavailable: String

    // Download errors
    let signInToDownload: String
    let signInToDownloadAndSet: String
    let signInAgain: String
    let serverCouldNotPrepare: String
    let downloadFailedFallback: String

    // Live video preview
    let pausePreview: String
    let playPreview: String
    let previewFailed: String
}

private let detailEN = DetailStrings(
    previewWallpaper: "Wallpaper",
    previewPlain: "Plain",
    previewHome: "Home",
    previewLock: "Lock",
    specimen: { id in "Specimen №\(id)" },
    downloadingOriginal: "DOWNLOADING ORIGINAL",
    preparingOriginal: "PREPARING ORIGINAL",
    uploadToEarn: "Upload to earn",
    noticeDownloadedTitle: "Downloaded",
    noticeSetTitle: "Wallpaper set",
    noticeInsufficientCoinsTitle: "Insufficient coins",
    noticeUnavailableTitle: "Not ready to download",
    noticeFailedTitle: "Download failed",
    noticeSuccessMessage: { name, size in "\(name) · \(size) saved to your Wallpaper Exchange downloads." },
    noticeSetMessage: "Applied your wallpaper settings from the local Wallpaper Exchange file.",
    noticeInsufficientCoinsMessage: { n in "Your balance is \(n) coin\(n == 1 ? "" : "s"). Upload wallpapers to earn more and keep downloading." },
    noticeUnavailableMessage: "The original file is still being prepared or is temporarily unavailable. Try again in a moment.",
    chipLive: "LIVE",
    liked: "Liked",
    like: "Like",
    saved: "Saved",
    favorite: "Favorite",
    addToList: "Add to list",
    noCollections: "No collections yet",
    statDownloads: "DOWNLOADS",
    statLikes: "LIKES",
    statFavorited: "FAVORITED",
    statViews: "VIEWS",
    uploadedBy: "Uploaded by",
    viewProfile: "VIEW PROFILE →",
    unknownUploader: "Unknown",
    about: "About",
    wallpaperTitle: "Wallpaper",
    palette: "Palette",
    paletteColors: { n in "Palette · \(n) colors" },
    dominant: { hex in "DOMINANT · \(hex)" },
    relatedArchive: "Related archive",
    moreLikeThis: "More like this",
    picksCount: { n in "\(n) PICKS" },
    gotIt: "Got it",
    downloading: "Downloading",
    tradeForOne: "Trade for 1",
    download: "Download",
    setAsWallpaper: "Set as wallpaper",
    downloadAndSetCoin: "Download & set · 1 coin",
    downloadAndSet: "Download & set",
    wallpaperPickerTitle: "Set wallpaper",
    wallpaperSurfaceDesktop: "Desktop",
    wallpaperSurfaceLockScreen: "Lock screen",
    wallpaperSurfaceBoth: "Both",
    wallpaperChooseDisplay: "Choose display",
    wallpaperAllDisplays: "All displays",
    wallpaperAllDisplaysDetail: { n in n == 1 ? "1 connected display" : "\(n) connected displays" },
    wallpaperMainDisplay: "Main",
    wallpaperSecondaryDisplay: "Display",
    wallpaperApply: "Apply",
    wallpaperApplying: "Applying",
    wallpaperPanelHint: "Desktop wallpapers can be applied per display. Lock screen wallpaper is not exposed through a reliable macOS app API yet.",
    wallpaperVideoLockUnavailable: "Video wallpapers can be applied to the desktop only.",
    lockScreenUnavailable: "macOS does not expose a reliable lock screen wallpaper API to regular apps.",
    signInToDownload: "Please sign in to download this wallpaper.",
    signInToDownloadAndSet: "Please sign in to download and set this wallpaper.",
    signInAgain: "Please sign in again to download this wallpaper.",
    serverCouldNotPrepare: "The server could not prepare this download.",
    downloadFailedFallback: "Download failed.",
    pausePreview: "Pause preview",
    playPreview: "Play preview",
    previewFailed: "Preview failed"
)

private let detailZhCN = DetailStrings(
    previewWallpaper: "壁纸",
    previewPlain: "纯净",
    previewHome: "桌面",
    previewLock: "锁屏",
    specimen: { id in "藏品 №\(id)" },
    downloadingOriginal: "正在下载原图",
    preparingOriginal: "正在准备原图",
    uploadToEarn: "上传赚金币",
    noticeDownloadedTitle: "下载完成",
    noticeSetTitle: "壁纸已设置",
    noticeInsufficientCoinsTitle: "金币不足",
    noticeUnavailableTitle: "暂不可下载",
    noticeFailedTitle: "下载失败",
    noticeSuccessMessage: { name, size in "\(name) · \(size) 已保存到你的 Wallpaper Exchange 下载目录。" },
    noticeSetMessage: "已使用本地 Wallpaper Exchange 文件应用你的壁纸设置。",
    noticeInsufficientCoinsMessage: { n in "你的余额为 \(n) 金币。上传壁纸即可赚取更多金币，继续下载。" },
    noticeUnavailableMessage: "原图仍在准备中或暂时不可用，请稍后再试。",
    chipLive: "动态",
    liked: "已点赞",
    like: "点赞",
    saved: "已收藏",
    favorite: "收藏",
    addToList: "加入合集",
    noCollections: "还没有合集",
    statDownloads: "下载",
    statLikes: "点赞",
    statFavorited: "收藏",
    statViews: "浏览",
    uploadedBy: "上传者",
    viewProfile: "查看主页 →",
    unknownUploader: "未知",
    about: "关于",
    wallpaperTitle: "壁纸",
    palette: "调色板",
    paletteColors: { n in "调色板 · \(n) 色" },
    dominant: { hex in "主色 · \(hex)" },
    relatedArchive: "相关档案",
    moreLikeThis: "更多相似壁纸",
    picksCount: { n in "精选 \(n) 张" },
    gotIt: "已获取",
    downloading: "下载中",
    tradeForOne: "1 金币兑换",
    download: "下载",
    setAsWallpaper: "设为壁纸",
    downloadAndSetCoin: "下载并设置 · 1 金币",
    downloadAndSet: "下载并设置",
    wallpaperPickerTitle: "设置壁纸",
    wallpaperSurfaceDesktop: "桌面",
    wallpaperSurfaceLockScreen: "锁屏",
    wallpaperSurfaceBoth: "同时",
    wallpaperChooseDisplay: "选择显示器",
    wallpaperAllDisplays: "全部显示器",
    wallpaperAllDisplaysDetail: { n in "已连接 \(n) 个显示器" },
    wallpaperMainDisplay: "主显示器",
    wallpaperSecondaryDisplay: "显示器",
    wallpaperApply: "应用",
    wallpaperApplying: "应用中",
    wallpaperPanelHint: "桌面壁纸可以按显示器应用；macOS 暂未给普通 App 开放可靠的锁屏壁纸接口。",
    wallpaperVideoLockUnavailable: "视频壁纸只能应用到桌面。",
    lockScreenUnavailable: "macOS 暂未给普通 App 开放可靠的锁屏壁纸接口。",
    signInToDownload: "请登录后再下载这张壁纸。",
    signInToDownloadAndSet: "请登录后再下载并设置这张壁纸。",
    signInAgain: "请重新登录后再下载这张壁纸。",
    serverCouldNotPrepare: "服务器暂时无法准备此下载。",
    downloadFailedFallback: "下载失败。",
    pausePreview: "暂停预览",
    playPreview: "播放预览",
    previewFailed: "预览失败"
)

private let detailZhTW = DetailStrings(
    previewWallpaper: "桌布",
    previewPlain: "純淨",
    previewHome: "桌面",
    previewLock: "鎖定畫面",
    specimen: { id in "藏品 №\(id)" },
    downloadingOriginal: "正在下載原圖",
    preparingOriginal: "正在準備原圖",
    uploadToEarn: "上傳賺金幣",
    noticeDownloadedTitle: "下載完成",
    noticeSetTitle: "桌布已設定",
    noticeInsufficientCoinsTitle: "金幣不足",
    noticeUnavailableTitle: "暫不可下載",
    noticeFailedTitle: "下載失敗",
    noticeSuccessMessage: { name, size in "\(name) · \(size) 已儲存到你的 Wallpaper Exchange 下載資料夾。" },
    noticeSetMessage: "已使用本機 Wallpaper Exchange 檔案套用你的桌布設定。",
    noticeInsufficientCoinsMessage: { n in "你的餘額為 \(n) 金幣。上傳桌布即可賺取更多金幣，繼續下載。" },
    noticeUnavailableMessage: "原圖仍在準備中或暫時無法使用，請稍後再試。",
    chipLive: "動態",
    liked: "已按讚",
    like: "按讚",
    saved: "已收藏",
    favorite: "收藏",
    addToList: "加入合輯",
    noCollections: "還沒有合輯",
    statDownloads: "下載",
    statLikes: "按讚",
    statFavorited: "收藏",
    statViews: "瀏覽",
    uploadedBy: "上傳者",
    viewProfile: "檢視個人檔案 →",
    unknownUploader: "未知",
    about: "關於",
    wallpaperTitle: "桌布",
    palette: "調色盤",
    paletteColors: { n in "調色盤 · \(n) 色" },
    dominant: { hex in "主色 · \(hex)" },
    relatedArchive: "相關檔案",
    moreLikeThis: "更多相似桌布",
    picksCount: { n in "精選 \(n) 張" },
    gotIt: "已取得",
    downloading: "下載中",
    tradeForOne: "1 金幣兌換",
    download: "下載",
    setAsWallpaper: "設為桌布",
    downloadAndSetCoin: "下載並設定 · 1 金幣",
    downloadAndSet: "下載並設定",
    wallpaperPickerTitle: "設定桌布",
    wallpaperSurfaceDesktop: "桌面",
    wallpaperSurfaceLockScreen: "鎖定畫面",
    wallpaperSurfaceBoth: "同時",
    wallpaperChooseDisplay: "選擇顯示器",
    wallpaperAllDisplays: "全部顯示器",
    wallpaperAllDisplaysDetail: { n in "已連接 \(n) 個顯示器" },
    wallpaperMainDisplay: "主顯示器",
    wallpaperSecondaryDisplay: "顯示器",
    wallpaperApply: "套用",
    wallpaperApplying: "套用中",
    wallpaperPanelHint: "桌面桌布可以按顯示器套用；macOS 尚未提供一般 App 可可靠使用的鎖定畫面桌布介面。",
    wallpaperVideoLockUnavailable: "影片桌布只能套用到桌面。",
    lockScreenUnavailable: "macOS 尚未提供一般 App 可可靠使用的鎖定畫面桌布介面。",
    signInToDownload: "請登入後再下載這張桌布。",
    signInToDownloadAndSet: "請登入後再下載並設定這張桌布。",
    signInAgain: "請重新登入後再下載這張桌布。",
    serverCouldNotPrepare: "伺服器暫時無法準備此下載。",
    downloadFailedFallback: "下載失敗。",
    pausePreview: "暫停預覽",
    playPreview: "播放預覽",
    previewFailed: "預覽失敗"
)

private let detailJA = DetailStrings(
    previewWallpaper: "壁紙",
    previewPlain: "プレーン",
    previewHome: "ホーム",
    previewLock: "ロック",
    specimen: { id in "作品 №\(id)" },
    downloadingOriginal: "オリジナルをダウンロード中",
    preparingOriginal: "オリジナルを準備中",
    uploadToEarn: "アップロードでコイン獲得",
    noticeDownloadedTitle: "ダウンロード完了",
    noticeSetTitle: "壁紙を設定しました",
    noticeInsufficientCoinsTitle: "コイン不足",
    noticeUnavailableTitle: "ダウンロード準備中",
    noticeFailedTitle: "ダウンロード失敗",
    noticeSuccessMessage: { name, size in "\(name) · \(size) を Wallpaper Exchange のダウンロードに保存しました。" },
    noticeSetMessage: "ローカルの Wallpaper Exchange ファイルから、壁紙設定を適用しました。",
    noticeInsufficientCoinsMessage: { n in "残高は \(n) コインです。壁紙をアップロードしてコインを獲得すると、引き続きダウンロードできます。" },
    noticeUnavailableMessage: "オリジナルファイルは準備中か、一時的に利用できません。しばらくしてからもう一度お試しください。",
    chipLive: "ライブ",
    liked: "いいね済み",
    like: "いいね",
    saved: "お気に入り済み",
    favorite: "お気に入り",
    addToList: "コレクションに追加",
    noCollections: "コレクションはまだありません",
    statDownloads: "ダウンロード",
    statLikes: "いいね",
    statFavorited: "お気に入り",
    statViews: "閲覧",
    uploadedBy: "投稿者",
    viewProfile: "プロフィールを見る →",
    unknownUploader: "不明",
    about: "概要",
    wallpaperTitle: "壁紙",
    palette: "パレット",
    paletteColors: { n in "パレット · \(n)色" },
    dominant: { hex in "メインカラー · \(hex)" },
    relatedArchive: "関連アーカイブ",
    moreLikeThis: "似ている壁紙",
    picksCount: { n in "おすすめ \(n) 件" },
    gotIt: "取得済み",
    downloading: "ダウンロード中",
    tradeForOne: "1コインで交換",
    download: "ダウンロード",
    setAsWallpaper: "壁紙に設定",
    downloadAndSetCoin: "ダウンロードして設定 · 1コイン",
    downloadAndSet: "ダウンロードして設定",
    wallpaperPickerTitle: "壁紙を設定",
    wallpaperSurfaceDesktop: "デスクトップ",
    wallpaperSurfaceLockScreen: "ロック画面",
    wallpaperSurfaceBoth: "両方",
    wallpaperChooseDisplay: "ディスプレイを選択",
    wallpaperAllDisplays: "すべてのディスプレイ",
    wallpaperAllDisplaysDetail: { n in "接続中のディスプレイ \(n) 台" },
    wallpaperMainDisplay: "メイン",
    wallpaperSecondaryDisplay: "ディスプレイ",
    wallpaperApply: "適用",
    wallpaperApplying: "適用中",
    wallpaperPanelHint: "デスクトップ壁紙はディスプレイごとに適用できます。macOS は通常のアプリ向けに信頼できるロック画面壁紙 API を公開していません。",
    wallpaperVideoLockUnavailable: "ビデオ壁紙はデスクトップにのみ適用できます。",
    lockScreenUnavailable: "macOS は通常のアプリ向けに信頼できるロック画面壁紙 API を公開していません。",
    signInToDownload: "この壁紙をダウンロードするにはサインインしてください。",
    signInToDownloadAndSet: "この壁紙をダウンロードして設定するにはサインインしてください。",
    signInAgain: "もう一度サインインしてから、この壁紙をダウンロードしてください。",
    serverCouldNotPrepare: "サーバーがこのダウンロードを準備できませんでした。",
    downloadFailedFallback: "ダウンロードに失敗しました。",
    pausePreview: "プレビューを一時停止",
    playPreview: "プレビューを再生",
    previewFailed: "プレビュー失敗"
)

extension L10n {
    static var detail: DetailStrings {
        switch lang {
        case .en: detailEN
        case .zhCN: detailZhCN
        case .zhTW: detailZhTW
        case .ja: detailJA
        }
    }
}
