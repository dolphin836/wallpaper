import Foundation

// Browse-surface strings: Discover, Categories, Uploaders, Devices, the
// device preview banner, grid tiles, shared skeleton/error states and the
// My Library pages. Same pattern as Common.swift — one struct, four
// instances sharing the memberwise init so a missing translation fails
// the build. Interpolated strings are closures so each language can
// phrase counts and prompts naturally.

struct BrowseStrings {
    // ── Discover: filter dropdown + toolbar ──
    let filterLatest: String
    let filterTrending: String
    let filterForYou: String
    let filterLive: String
    let filterAI: String
    let chipAll: String
    let filterKicker: String
    let resolutionKicker: String
    let currentScreen: String
    let colorKicker: String
    let facetAll: String
    let colorName: (String) -> String

    // ── Discover: feed footer + empty states ──
    let loadingMore: String
    let loadMoreFailed: String
    let loadMore: String
    let endOfFeed: (Int) -> String
    let emptyTitle: String
    let emptyMessage: String
    let searchEmptyTitle: String
    let searchEmptyMessage: String

    // ── Categories ──
    let categoriesKicker: String
    let categoriesTitle: String
    let categoryFeedKicker: (String) -> String

    // ── Uploaders ──
    let uploadersKicker: String
    let uploadersTitle: String
    let sortTrending: String
    let sortNewest: String
    let sortDownloads: String
    let metricUploads: String
    let metricDownloads: String

    // ── Devices ──
    let devicesKicker: String
    let devicesTitle: String
    let platformLabel: (String) -> String
    let wallpapersCount: (Int) -> String
    let deviceEmptyTitle: String
    let deviceEmptyMessage: String

    // ── Device preview banner / monitor mockup ──
    let modePlain: String
    let modeHome: String
    let modeLock: String
    /// DateFormatter pattern for the lock-screen date line.
    let lockDateFormat: String
    /// Locale identifier driving day/month names in formatted dates.
    let dateLocaleID: String

    // ── Grid tile action rail + chips ──
    let tipFavorite: String
    let tipUnfavorite: String
    let tipLike: String
    let tipUnlike: String
    let tipSetWallpaper: String
    let tipDownload: String
    let tipGotIt: String
    let tipTradeForOne: String
    let chipLive: String
    let chipMissing: String

    // ── Shared remote-load error state ──
    let errorTitle: String

    // ── My Library ──
    let signInPrompt: (String) -> String
    let libUploads: String
    let libDownloads: String
    let libFavorites: String
    let libLikes: String
    let libCollections: String
    let libCoinBalance: String
    let nothingHere: String
    let noCollectionsYet: String
    let collectionCount: (Int) -> String
    let signIn: String
    let balanceKicker: String
    let earnHint: String
    let txHistory: String
    let txErrorTitle: String
    let txEmptyTitle: String
    let txEmptyMessage: String
    let txUploadReward: String
    let txDownloadReceived: String
    let txDownloadSpent: String
    let txAdminGrant: String
    let balanceAfter: (Int) -> String
    /// DateFormatter pattern for ledger rows.
    let ledgerDateFormat: String
}

private let browseEN = BrowseStrings(
    filterLatest: "Latest",
    filterTrending: "Trending",
    filterForYou: "For You",
    filterLive: "Live",
    filterAI: "AI Generated",
    chipAll: "All",
    filterKicker: "FILTER",
    resolutionKicker: "RESOLUTION",
    currentScreen: "Current screen",
    colorKicker: "COLOR",
    facetAll: "All",
    colorName: {
        switch $0 {
        case "red": "Red"; case "orange": "Orange"; case "yellow": "Yellow"
        case "green": "Green"; case "cyan": "Cyan"; case "blue": "Blue"
        case "purple": "Purple"; case "pink": "Pink"; case "brown": "Brown"
        case "black": "Black"; case "gray": "Gray"; case "white": "White"
        default: $0.capitalized
        }
    },
    loadingMore: "Loading more…",
    loadMoreFailed: "Couldn't load more",
    loadMore: "Load more",
    endOfFeed: { "\($0) wallpaper\($0 == 1 ? "" : "s") · You've reached the end" },
    emptyTitle: "No wallpapers yet.",
    emptyMessage: "New uploads will appear here as soon as the archive has something for this filter.",
    searchEmptyTitle: "No wallpapers match.",
    searchEmptyMessage: "Try a broader search or switch filters to keep browsing.",
    categoriesKicker: "Browse by topic",
    categoriesTitle: "Categories",
    categoryFeedKicker: { "Category · \($0)" },
    uploadersKicker: "Top contributors · this week",
    uploadersTitle: "Uploaders",
    sortTrending: "Trending",
    sortNewest: "Newest",
    sortDownloads: "Downloads",
    metricUploads: "UPLOADS",
    metricDownloads: "DOWNLOADS",
    devicesKicker: "Find wallpapers sized for your hardware",
    devicesTitle: "Devices",
    platformLabel: { $0.uppercased() },
    wallpapersCount: { "\($0) wallpaper\($0 == 1 ? "" : "s")" },
    deviceEmptyTitle: "No wallpapers for this device yet.",
    deviceEmptyMessage: "When matching wallpapers are published, they will appear here automatically.",
    modePlain: "Plain",
    modeHome: "Home",
    modeLock: "Lock",
    lockDateFormat: "EEEE, MMM d",
    dateLocaleID: "en_US",
    tipFavorite: "Favorite",
    tipUnfavorite: "Unfavorite",
    tipLike: "Like",
    tipUnlike: "Unlike",
    tipSetWallpaper: "Set as wallpaper",
    tipDownload: "Download",
    tipGotIt: "Got it",
    tipTradeForOne: "Trade for 1",
    chipLive: "LIVE",
    chipMissing: "MISS",
    errorTitle: "Could not load this page",
    signInPrompt: { "Sign in to view your \($0)." },
    libUploads: "uploads",
    libDownloads: "downloads",
    libFavorites: "favorites",
    libLikes: "likes",
    libCollections: "collections",
    libCoinBalance: "coin balance",
    nothingHere: "Nothing here yet.",
    noCollectionsYet: "You haven't created any collections yet.",
    collectionCount: { "\($0) WALLPAPER\($0 == 1 ? "" : "S")" },
    signIn: "Sign in",
    balanceKicker: "Your balance",
    earnHint: "Earn +1 for each upload and +1 each time someone downloads yours.",
    txHistory: "Transaction history",
    txErrorTitle: "Could not load transactions",
    txEmptyTitle: "No transactions yet.",
    txEmptyMessage: "Coin activity will show here after uploads, trades, and system grants.",
    txUploadReward: "Reward · upload published",
    txDownloadReceived: "Reward · someone downloaded yours",
    txDownloadSpent: "Spent · downloaded a wallpaper",
    txAdminGrant: "Admin grant",
    balanceAfter: { "Bal · \($0)" },
    ledgerDateFormat: "MMM d · HH:mm"
)

private let browseZhCN = BrowseStrings(
    filterLatest: "最新",
    filterTrending: "热门",
    filterForYou: "为你推荐",
    filterLive: "动态",
    filterAI: "AI 生成",
    chipAll: "全部",
    filterKicker: "筛选",
    resolutionKicker: "分辨率",
    currentScreen: "当前屏幕",
    colorKicker: "颜色",
    facetAll: "全部",
    colorName: {
        switch $0 {
        case "red": "红色"; case "orange": "橙色"; case "yellow": "黄色"
        case "green": "绿色"; case "cyan": "青色"; case "blue": "蓝色"
        case "purple": "紫色"; case "pink": "粉色"; case "brown": "棕色"
        case "black": "黑色"; case "gray": "灰色"; case "white": "白色"
        default: $0
        }
    },
    loadingMore: "正在加载更多…",
    loadMoreFailed: "加载更多失败",
    loadMore: "加载更多",
    endOfFeed: { "共 \($0) 张壁纸 · 已经到底啦" },
    emptyTitle: "还没有壁纸。",
    emptyMessage: "一旦有符合此筛选的新上传，就会出现在这里。",
    searchEmptyTitle: "没有匹配的壁纸。",
    searchEmptyMessage: "试试更宽泛的关键词，或切换筛选条件继续浏览。",
    categoriesKicker: "按主题浏览",
    categoriesTitle: "分类",
    categoryFeedKicker: { "分类 · \($0)" },
    uploadersKicker: "热门创作者 · 本周",
    uploadersTitle: "创作者",
    sortTrending: "热门",
    sortNewest: "最新",
    sortDownloads: "下载量",
    metricUploads: "上传",
    metricDownloads: "下载",
    devicesKicker: "找到适配你设备分辨率的壁纸",
    devicesTitle: "设备",
    platformLabel: { p in
        switch p {
        case "desktop": "台式机"
        case "laptop": "笔记本"
        case "tablet": "平板"
        case "phone": "手机"
        case "watch": "手表"
        case "tv": "电视"
        case "other": "其他"
        default: p.uppercased()
        }
    },
    wallpapersCount: { "\($0) 张壁纸" },
    deviceEmptyTitle: "这台设备还没有适配的壁纸。",
    deviceEmptyMessage: "一旦有匹配的壁纸发布，就会自动出现在这里。",
    modePlain: "原图",
    modeHome: "桌面",
    modeLock: "锁屏",
    lockDateFormat: "M月d日 EEEE",
    dateLocaleID: "zh_CN",
    tipFavorite: "收藏",
    tipUnfavorite: "取消收藏",
    tipLike: "点赞",
    tipUnlike: "取消点赞",
    tipSetWallpaper: "设为壁纸",
    tipDownload: "下载",
    tipGotIt: "已获取",
    tipTradeForOne: "1 金币兑换",
    chipLive: "动态",
    chipMissing: "缺失",
    errorTitle: "页面加载失败",
    signInPrompt: { "登录后即可查看\($0)。" },
    libUploads: "我的上传",
    libDownloads: "我的下载",
    libFavorites: "我的收藏",
    libLikes: "我的点赞",
    libCollections: "我的合集",
    libCoinBalance: "金币余额",
    nothingHere: "这里还什么都没有。",
    noCollectionsYet: "你还没有创建任何合集。",
    collectionCount: { "\($0) 张壁纸" },
    signIn: "登录",
    balanceKicker: "金币余额",
    earnHint: "每次上传 +1 金币；你的壁纸每被下载一次再 +1。",
    txHistory: "交易记录",
    txErrorTitle: "交易记录加载失败",
    txEmptyTitle: "暂无交易记录。",
    txEmptyMessage: "上传、兑换或系统发放后，金币流水会显示在这里。",
    txUploadReward: "奖励 · 上传已发布",
    txDownloadReceived: "奖励 · 你的壁纸被下载",
    txDownloadSpent: "支出 · 下载壁纸",
    txAdminGrant: "管理员发放",
    balanceAfter: { "余额 · \($0)" },
    ledgerDateFormat: "M月d日 · HH:mm"
)

private let browseZhTW = BrowseStrings(
    filterLatest: "最新",
    filterTrending: "熱門",
    filterForYou: "為你推薦",
    filterLive: "動態",
    filterAI: "AI 生成",
    chipAll: "全部",
    filterKicker: "篩選",
    resolutionKicker: "解析度",
    currentScreen: "目前螢幕",
    colorKicker: "顏色",
    facetAll: "全部",
    colorName: {
        switch $0 {
        case "red": "紅色"; case "orange": "橙色"; case "yellow": "黃色"
        case "green": "綠色"; case "cyan": "青色"; case "blue": "藍色"
        case "purple": "紫色"; case "pink": "粉紅色"; case "brown": "棕色"
        case "black": "黑色"; case "gray": "灰色"; case "white": "白色"
        default: $0
        }
    },
    loadingMore: "正在載入更多…",
    loadMoreFailed: "載入更多失敗",
    loadMore: "載入更多",
    endOfFeed: { "共 \($0) 張桌布 · 已經到底了" },
    emptyTitle: "還沒有桌布。",
    emptyMessage: "一旦有符合此篩選的新上傳，就會出現在這裡。",
    searchEmptyTitle: "沒有符合的桌布。",
    searchEmptyMessage: "試試更廣泛的關鍵字，或切換篩選條件繼續瀏覽。",
    categoriesKicker: "依主題瀏覽",
    categoriesTitle: "分類",
    categoryFeedKicker: { "分類 · \($0)" },
    uploadersKicker: "熱門創作者 · 本週",
    uploadersTitle: "創作者",
    sortTrending: "熱門",
    sortNewest: "最新",
    sortDownloads: "下載量",
    metricUploads: "上傳",
    metricDownloads: "下載",
    devicesKicker: "找到適合你裝置解析度的桌布",
    devicesTitle: "裝置",
    platformLabel: { p in
        switch p {
        case "desktop": "桌上型電腦"
        case "laptop": "筆記型電腦"
        case "tablet": "平板"
        case "phone": "手機"
        case "watch": "手錶"
        case "tv": "電視"
        case "other": "其他"
        default: p.uppercased()
        }
    },
    wallpapersCount: { "\($0) 張桌布" },
    deviceEmptyTitle: "這部裝置還沒有合適的桌布。",
    deviceEmptyMessage: "一旦有符合的桌布發佈，就會自動出現在這裡。",
    modePlain: "原圖",
    modeHome: "桌面",
    modeLock: "鎖定畫面",
    lockDateFormat: "M月d日 EEEE",
    dateLocaleID: "zh_TW",
    tipFavorite: "收藏",
    tipUnfavorite: "取消收藏",
    tipLike: "按讚",
    tipUnlike: "收回讚",
    tipSetWallpaper: "設為桌布",
    tipDownload: "下載",
    tipGotIt: "已取得",
    tipTradeForOne: "1 金幣兌換",
    chipLive: "動態",
    chipMissing: "缺失",
    errorTitle: "頁面載入失敗",
    signInPrompt: { "登入後即可查看\($0)。" },
    libUploads: "我的上傳",
    libDownloads: "我的下載",
    libFavorites: "我的收藏",
    libLikes: "我的按讚",
    libCollections: "我的合輯",
    libCoinBalance: "金幣餘額",
    nothingHere: "這裡還什麼都沒有。",
    noCollectionsYet: "你還沒有建立任何合輯。",
    collectionCount: { "\($0) 張桌布" },
    signIn: "登入",
    balanceKicker: "金幣餘額",
    earnHint: "每次上傳 +1 金幣；你的桌布每被下載一次再 +1。",
    txHistory: "交易記錄",
    txErrorTitle: "交易記錄載入失敗",
    txEmptyTitle: "尚無交易記錄。",
    txEmptyMessage: "上傳、兌換或系統發放後，金幣紀錄會顯示在這裡。",
    txUploadReward: "獎勵 · 上傳已發佈",
    txDownloadReceived: "獎勵 · 你的桌布被下載",
    txDownloadSpent: "支出 · 下載桌布",
    txAdminGrant: "管理員發放",
    balanceAfter: { "餘額 · \($0)" },
    ledgerDateFormat: "M月d日 · HH:mm"
)

private let browseJA = BrowseStrings(
    filterLatest: "新着",
    filterTrending: "人気",
    filterForYou: "おすすめ",
    filterLive: "ライブ",
    filterAI: "AI生成",
    chipAll: "すべて",
    filterKicker: "フィルター",
    resolutionKicker: "解像度",
    currentScreen: "現在の画面",
    colorKicker: "カラー",
    facetAll: "すべて",
    colorName: {
        switch $0 {
        case "red": "赤"; case "orange": "オレンジ"; case "yellow": "黄"
        case "green": "緑"; case "cyan": "シアン"; case "blue": "青"
        case "purple": "紫"; case "pink": "ピンク"; case "brown": "茶"
        case "black": "黒"; case "gray": "グレー"; case "white": "白"
        default: $0
        }
    },
    loadingMore: "さらに読み込み中…",
    loadMoreFailed: "読み込みに失敗しました",
    loadMore: "もっと見る",
    endOfFeed: { "全\($0)枚 · これで全部です" },
    emptyTitle: "まだ壁紙がありません。",
    emptyMessage: "この条件に合う壁紙がアップロードされると、ここに表示されます。",
    searchEmptyTitle: "一致する壁紙が見つかりません。",
    searchEmptyMessage: "キーワードを広げるか、絞り込み条件を変えてみてください。",
    categoriesKicker: "トピックから探す",
    categoriesTitle: "カテゴリ",
    categoryFeedKicker: { "カテゴリ · \($0)" },
    uploadersKicker: "トップアップローダー · 今週",
    uploadersTitle: "アップローダー",
    sortTrending: "人気",
    sortNewest: "新着",
    sortDownloads: "ダウンロード数",
    metricUploads: "アップロード",
    metricDownloads: "ダウンロード",
    devicesKicker: "お使いのデバイスにぴったりの壁紙を探す",
    devicesTitle: "デバイス",
    platformLabel: { p in
        switch p {
        case "desktop": "デスクトップ"
        case "laptop": "ノートPC"
        case "tablet": "タブレット"
        case "phone": "スマートフォン"
        case "watch": "ウォッチ"
        case "tv": "テレビ"
        case "other": "その他"
        default: p.uppercased()
        }
    },
    wallpapersCount: { "壁紙\($0)枚" },
    deviceEmptyTitle: "このデバイス向けの壁紙はまだありません。",
    deviceEmptyMessage: "対応する壁紙が公開されると、自動的にここに表示されます。",
    modePlain: "プレーン",
    modeHome: "ホーム",
    modeLock: "ロック",
    lockDateFormat: "M月d日 EEEE",
    dateLocaleID: "ja_JP",
    tipFavorite: "お気に入り",
    tipUnfavorite: "お気に入り解除",
    tipLike: "いいね",
    tipUnlike: "いいね解除",
    tipSetWallpaper: "壁紙に設定",
    tipDownload: "ダウンロード",
    tipGotIt: "取得済み",
    tipTradeForOne: "コイン1枚で交換",
    chipLive: "ライブ",
    chipMissing: "未保存",
    errorTitle: "ページを読み込めませんでした",
    signInPrompt: { "サインインすると\($0)を確認できます。" },
    libUploads: "アップロードした壁紙",
    libDownloads: "ダウンロード履歴",
    libFavorites: "お気に入り",
    libLikes: "いいねした壁紙",
    libCollections: "コレクション",
    libCoinBalance: "コイン残高",
    nothingHere: "まだ何もありません。",
    noCollectionsYet: "コレクションはまだ作成されていません。",
    collectionCount: { "壁紙\($0)枚" },
    signIn: "サインイン",
    balanceKicker: "コイン残高",
    earnHint: "アップロードごとに+1、あなたの壁紙がダウンロードされるたびに+1獲得できます。",
    txHistory: "取引履歴",
    txErrorTitle: "取引履歴を読み込めませんでした",
    txEmptyTitle: "まだ取引はありません。",
    txEmptyMessage: "アップロード・交換・システム付与があると、コインの履歴がここに表示されます。",
    txUploadReward: "報酬 · アップロード公開",
    txDownloadReceived: "報酬 · あなたの壁紙がダウンロードされました",
    txDownloadSpent: "消費 · 壁紙をダウンロード",
    txAdminGrant: "管理者付与",
    balanceAfter: { "残高 · \($0)" },
    ledgerDateFormat: "M月d日 · HH:mm"
)

extension L10n {
    static var browse: BrowseStrings {
        switch lang {
        case .en: browseEN
        case .zhCN: browseZhCN
        case .zhTW: browseZhTW
        case .ja: browseJA
        }
    }
}
