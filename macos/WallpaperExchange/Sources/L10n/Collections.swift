import Foundation

// Strings for the Collections surfaces: the public collections list,
// the collection detail page (hero, byline, framed grid), the
// create-collection sheet, and the inline owner edit form. Same pattern
// as Common.swift — one memberwise init shared by four instances, so a
// missing translation fails the build.

struct CollectionsStrings {
    // List header
    let kicker: String
    let title: String
    let subtitle: String
    let filterAll: String
    let filterYours: String
    let newButton: String

    // Pagination
    let prevPage: String
    let nextPage: String
    let pageLabel: (Int) -> String

    // Empty states (list)
    let emptyAllTitle: String
    let emptyAllMessage: String
    let emptyYoursTitle: String
    let emptyYoursMessage: String

    // Cards
    let newCollection: String
    let kickerEditorTheme: String
    let kickerCollection: String
    let privateLabel: String
    let untitledSet: String
    let wallpaperCountCaps: (Int) -> String
    let noCoverYet: String

    // Create sheet
    let titlePlaceholder: String
    let publicToggle: String
    let creating: String
    let create: String
    let createFailed: String

    // Detail page
    let theSet: String
    let countOfTotalCaps: (Int, Int) -> String
    let piecesCaps: (Int) -> String
    let emptyDetailTitle: String
    let emptyDetailMessage: String
    let edit: String
    let setBy: (String) -> String
    let wallpaperCountLower: (Int) -> String
    let updatedAgo: (String) -> String

    // Edit form
    let descPlaceholder: String
    let togglePublicOn: String
    let togglePublicOff: String
    let saving: String
    let save: String

    // Framed tile (chips + action rail tooltips)
    let liveChip: String
    let favorite: String
    let unfavorite: String
    let like: String
    let unlike: String
    let downloadGotIt: String
    let download: String
    let tradeForOne: String
    let setAsWallpaper: String

    // Relative time (collection byline)
    let timeJustNow: String
    let timeMinAgo: (Int) -> String
    let timeHrAgo: (Int) -> String
    let timeDaysAgo: (Int) -> String
    let timeMonthsAgo: (Int) -> String
    let timeYearsAgo: (Int) -> String
}

private let collectionsEN = CollectionsStrings(
    kicker: "The Library",
    title: "Crates, curated.",
    subtitle: "Themed sets put together by the community and the editors. Each collection has its own colour, voice, and pace.",
    filterAll: "All",
    filterYours: "Yours",
    newButton: "New",
    prevPage: "‹ Prev",
    nextPage: "Next ›",
    pageLabel: { "Page \($0)" },
    emptyAllTitle: "No collections yet.",
    emptyAllMessage: "Curated sets will appear here once the library has something to group.",
    emptyYoursTitle: "No collections from you yet.",
    emptyYoursMessage: "Create a set when you want to group wallpapers by mood, device, or project.",
    newCollection: "New collection",
    kickerEditorTheme: "Editor Theme",
    kickerCollection: "Collection",
    privateLabel: "Private",
    untitledSet: "Untitled set",
    wallpaperCountCaps: { "\($0) \($0 == 1 ? "WALLPAPER" : "WALLPAPERS")" },
    noCoverYet: "NO COVER YET",
    titlePlaceholder: "Title",
    publicToggle: "Public",
    creating: "Creating…",
    create: "Create",
    createFailed: "Couldn't create. Try again.",
    theSet: "THE SET",
    countOfTotalCaps: { "\($0) OF \($1)" },
    piecesCaps: { "\($0) \($0 == 1 ? "PIECE" : "PIECES")" },
    emptyDetailTitle: "No wallpapers in this collection yet.",
    emptyDetailMessage: "This set is ready, but it does not have any wallpapers attached right now.",
    edit: "Edit",
    setBy: { "A set by @\($0)" },
    wallpaperCountLower: { "\($0) \($0 == 1 ? "wallpaper" : "wallpapers")" },
    updatedAgo: { "updated \($0)" },
    descPlaceholder: "Optional description",
    togglePublicOn: "Public · anyone can find this set",
    togglePublicOff: "Private · only you can see it",
    saving: "Saving…",
    save: "Save",
    liveChip: "Live",
    favorite: "Favorite",
    unfavorite: "Unfavorite",
    like: "Like",
    unlike: "Unlike",
    downloadGotIt: "Got it",
    download: "Download",
    tradeForOne: "Trade for 1",
    setAsWallpaper: "Set as wallpaper",
    timeJustNow: "just now",
    timeMinAgo: { "\($0) min ago" },
    timeHrAgo: { "\($0) hr ago" },
    timeDaysAgo: { "\($0) \($0 == 1 ? "day" : "days") ago" },
    timeMonthsAgo: { "\($0) \($0 == 1 ? "month" : "months") ago" },
    timeYearsAgo: { "\($0) \($0 == 1 ? "year" : "years") ago" }
)

private let collectionsZhCN = CollectionsStrings(
    kicker: "合集库",
    title: "精心编排的合集。",
    subtitle: "由社区和编辑共同整理的主题合集。每个合集都有自己的色彩、风格与节奏。",
    filterAll: "全部",
    filterYours: "我的",
    newButton: "新建",
    prevPage: "‹ 上一页",
    nextPage: "下一页 ›",
    pageLabel: { "第 \($0) 页" },
    emptyAllTitle: "还没有合集。",
    emptyAllMessage: "等内容库有可归类的作品后，精选合集就会出现在这里。",
    emptyYoursTitle: "你还没有创建合集。",
    emptyYoursMessage: "想按氛围、设备或项目整理壁纸时，就创建一个合集吧。",
    newCollection: "新建合集",
    kickerEditorTheme: "编辑主题",
    kickerCollection: "合集",
    privateLabel: "私密",
    untitledSet: "未命名合集",
    wallpaperCountCaps: { "\($0) 张壁纸" },
    noCoverYet: "暂无封面",
    titlePlaceholder: "标题",
    publicToggle: "公开",
    creating: "创建中…",
    create: "创建",
    createFailed: "创建失败，请重试。",
    theSet: "全部作品",
    countOfTotalCaps: { "\($0) / 共 \($1)" },
    piecesCaps: { "共 \($0) 件" },
    emptyDetailTitle: "这个合集还没有壁纸。",
    emptyDetailMessage: "合集已就绪，但目前还没有收录任何壁纸。",
    edit: "编辑",
    setBy: { "由 @\($0) 整理" },
    wallpaperCountLower: { "\($0) 张壁纸" },
    updatedAgo: { "更新于 \($0)" },
    descPlaceholder: "描述（可选）",
    togglePublicOn: "公开 · 任何人都能找到这个合集",
    togglePublicOff: "私密 · 只有你能看到",
    saving: "保存中…",
    save: "保存",
    liveChip: "动态",
    favorite: "收藏",
    unfavorite: "取消收藏",
    like: "点赞",
    unlike: "取消点赞",
    downloadGotIt: "已拥有",
    download: "下载",
    tradeForOne: "用 1 金币兑换",
    setAsWallpaper: "设为壁纸",
    timeJustNow: "刚刚",
    timeMinAgo: { "\($0) 分钟前" },
    timeHrAgo: { "\($0) 小时前" },
    timeDaysAgo: { "\($0) 天前" },
    timeMonthsAgo: { "\($0) 个月前" },
    timeYearsAgo: { "\($0) 年前" }
)

private let collectionsZhTW = CollectionsStrings(
    kicker: "合輯庫",
    title: "精心編排的合輯。",
    subtitle: "由社群與編輯共同整理的主題合輯。每個合輯都有自己的色彩、風格與節奏。",
    filterAll: "全部",
    filterYours: "我的",
    newButton: "新增",
    prevPage: "‹ 上一頁",
    nextPage: "下一頁 ›",
    pageLabel: { "第 \($0) 頁" },
    emptyAllTitle: "還沒有合輯。",
    emptyAllMessage: "等內容庫有可歸類的作品後，精選合輯就會出現在這裡。",
    emptyYoursTitle: "你還沒有建立合輯。",
    emptyYoursMessage: "想按氛圍、裝置或專案整理桌布時，就建立一個合輯吧。",
    newCollection: "新增合輯",
    kickerEditorTheme: "編輯主題",
    kickerCollection: "合輯",
    privateLabel: "私人",
    untitledSet: "未命名合輯",
    wallpaperCountCaps: { "\($0) 張桌布" },
    noCoverYet: "尚無封面",
    titlePlaceholder: "標題",
    publicToggle: "公開",
    creating: "建立中…",
    create: "建立",
    createFailed: "建立失敗，請重試。",
    theSet: "全部作品",
    countOfTotalCaps: { "\($0) / 共 \($1)" },
    piecesCaps: { "共 \($0) 件" },
    emptyDetailTitle: "這個合輯還沒有桌布。",
    emptyDetailMessage: "合輯已就緒，但目前還沒有收錄任何桌布。",
    edit: "編輯",
    setBy: { "由 @\($0) 整理" },
    wallpaperCountLower: { "\($0) 張桌布" },
    updatedAgo: { "更新於 \($0)" },
    descPlaceholder: "描述（選填）",
    togglePublicOn: "公開 · 任何人都能找到這個合輯",
    togglePublicOff: "私人 · 只有你能看到",
    saving: "儲存中…",
    save: "儲存",
    liveChip: "動態",
    favorite: "收藏",
    unfavorite: "取消收藏",
    like: "按讚",
    unlike: "收回讚",
    downloadGotIt: "已擁有",
    download: "下載",
    tradeForOne: "用 1 金幣兌換",
    setAsWallpaper: "設為桌布",
    timeJustNow: "剛剛",
    timeMinAgo: { "\($0) 分鐘前" },
    timeHrAgo: { "\($0) 小時前" },
    timeDaysAgo: { "\($0) 天前" },
    timeMonthsAgo: { "\($0) 個月前" },
    timeYearsAgo: { "\($0) 年前" }
)

private let collectionsJA = CollectionsStrings(
    kicker: "ライブラリ",
    title: "選び抜かれたコレクション。",
    subtitle: "コミュニティとエディターがまとめたテーマ別セット。それぞれのコレクションに固有の色、声、リズムがあります。",
    filterAll: "すべて",
    filterYours: "自分の",
    newButton: "新規",
    prevPage: "‹ 前へ",
    nextPage: "次へ ›",
    pageLabel: { "ページ \($0)" },
    emptyAllTitle: "まだコレクションがありません。",
    emptyAllMessage: "ライブラリにまとめられる作品が揃うと、キュレーションされたセットがここに表示されます。",
    emptyYoursTitle: "まだコレクションを作成していません。",
    emptyYoursMessage: "気分・デバイス・プロジェクトごとに壁紙をまとめたいときは、コレクションを作りましょう。",
    newCollection: "新しいコレクション",
    kickerEditorTheme: "エディターテーマ",
    kickerCollection: "コレクション",
    privateLabel: "非公開",
    untitledSet: "無題のセット",
    wallpaperCountCaps: { "壁紙 \($0) 枚" },
    noCoverYet: "カバー未設定",
    titlePlaceholder: "タイトル",
    publicToggle: "公開",
    creating: "作成中…",
    create: "作成",
    createFailed: "作成できませんでした。もう一度お試しください。",
    theSet: "収録作品",
    countOfTotalCaps: { "\($1) 点中 \($0) 点" },
    piecesCaps: { "全 \($0) 点" },
    emptyDetailTitle: "このコレクションにはまだ壁紙がありません。",
    emptyDetailMessage: "セットは用意されていますが、現在壁紙は登録されていません。",
    edit: "編集",
    setBy: { "@\($0) によるセット" },
    wallpaperCountLower: { "壁紙 \($0) 枚" },
    updatedAgo: { "\($0)に更新" },
    descPlaceholder: "説明（任意）",
    togglePublicOn: "公開 · 誰でもこのセットを見つけられます",
    togglePublicOff: "非公開 · 自分だけが閲覧できます",
    saving: "保存中…",
    save: "保存",
    liveChip: "ライブ",
    favorite: "お気に入り",
    unfavorite: "お気に入り解除",
    like: "いいね",
    unlike: "いいねを取り消す",
    downloadGotIt: "入手済み",
    download: "ダウンロード",
    tradeForOne: "コイン1枚と交換",
    setAsWallpaper: "壁紙に設定",
    timeJustNow: "たった今",
    timeMinAgo: { "\($0)分前" },
    timeHrAgo: { "\($0)時間前" },
    timeDaysAgo: { "\($0)日前" },
    timeMonthsAgo: { "\($0)か月前" },
    timeYearsAgo: { "\($0)年前" }
)

extension L10n {
    static var collections: CollectionsStrings {
        switch lang {
        case .en: collectionsEN
        case .zhCN: collectionsZhCN
        case .zhTW: collectionsZhTW
        case .ja: collectionsJA
        }
    }
}
