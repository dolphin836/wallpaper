import Foundation

struct AppStrings {
    let home: String
    let discover: String
    let weekly: String
    let collections: String
    let favorites: String
    let viewAll: String
    let seeMore: String
    let latestWallpapers: String
    let latestCollections: String
    let weeklyKicker: String
    let recentWeekly: String
    let wallpapersCount: String
    let picksCount: String
    let collectionsKicker: String
    let weeklyArchiveKicker: String
    let pastWeeks: String
    let collectionListTitle: String
    let collectionListKicker: String
    let emptyCollection: String
    let emptyFavoritesTitle: String
    let emptyFavoritesMessage: String
    let signInFavorites: String
    let signInRegister: String
    let settings: String
    let language: String
    let appearance: String
    let lockPreview: String
    let upload: String
    let editProfile: String
    let password: String
    let signOut: String
    let coins: String
    let coinHint: String
    let preview: String
    let downloadOneCoin: String
    let saving: String
    let savedToPhotos: String
    let notEnoughCoins: String
    let downloadFailed: String
    let signInRequired: String
    let signInDetailMessage: String
    let ok: String
    let cancel: String
    let addToCollection: String
    let newCollection: String
    let collectionName: String
    let create: String
    let myCollections: String
    let noCollectionsYet: String
    let done: String
    let week: String
    let year: String
    let noMatches: String
    let noMatchesMessage: String
    let endOfArchive: String
    let searchWallpapers: String
    let all: String
    let latest: String
    let popular: String
    let forYou: String
    let ai: String
    let system: String
    let light: String
    let dark: String
}

enum L10n {
    static func strings(for language: AppLanguage) -> AppStrings {
        switch language.resolved {
        case .zhHans, .system:
            return zhHans
        case .zhHant:
            return zhHant
        case .ja:
            return ja
        case .en:
            return en
        }
    }

    static func languageName(_ language: AppLanguage, strings: AppStrings) -> String {
        switch language {
        case .system: return strings.system
        case .en: return "English"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .ja: return "日本語"
        }
    }

    static func appearanceName(_ appearance: AppearancePref, strings: AppStrings) -> String {
        switch appearance {
        case .system: return strings.system
        case .light: return strings.light
        case .dark: return strings.dark
        }
    }

    private static let zhHans = AppStrings(
        home: "首页",
        discover: "发现页",
        weekly: "每周推荐",
        collections: "合集",
        favorites: "我的收藏",
        viewAll: "查看全部",
        seeMore: "查看更多",
        latestWallpapers: "最新壁纸",
        latestCollections: "最新合集",
        weeklyKicker: "最近四周",
        recentWeekly: "每周推荐相册",
        wallpapersCount: "%d 张壁纸",
        picksCount: "%d 张精选",
        collectionsKicker: "社区整理",
        weeklyArchiveKicker: "往期精选",
        pastWeeks: "全部周刊",
        collectionListTitle: "全部合集",
        collectionListKicker: "可收藏的主题书架",
        emptyCollection: "这个合集还没有壁纸。",
        emptyFavoritesTitle: "还没有收藏",
        emptyFavoritesMessage: "你收藏的壁纸会出现在这里。",
        signInFavorites: "登录后查看和管理你的收藏、下载与个人设置。",
        signInRegister: "登录 / 注册",
        settings: "设置",
        language: "语言",
        appearance: "外观",
        lockPreview: "锁屏预览",
        upload: "上传",
        editProfile: "编辑资料",
        password: "密码",
        signOut: "退出",
        coins: "金币",
        coinHint: "上传获得 1 枚，下载消耗 1 枚",
        preview: "预览",
        downloadOneCoin: "下载 · 1 金币",
        saving: "保存中…",
        savedToPhotos: "已保存到照片",
        notEnoughCoins: "金币不足",
        downloadFailed: "下载失败",
        signInRequired: "需要登录",
        signInDetailMessage: "请在我的收藏页登录后再点赞、收藏或下载壁纸。",
        ok: "好的",
        cancel: "取消",
        addToCollection: "加入合集",
        newCollection: "新合集",
        collectionName: "合集名称",
        create: "创建",
        myCollections: "我的合集",
        noCollectionsYet: "还没有合集",
        done: "完成",
        week: "第 %d 周",
        year: "%d 年",
        noMatches: "没有匹配结果",
        noMatchesMessage: "当前筛选下还没有合适的壁纸。",
        endOfArchive: "已到归档末尾",
        searchWallpapers: "搜索壁纸",
        all: "全部",
        latest: "最新",
        popular: "热门",
        forYou: "为你推荐",
        ai: "AI",
        system: "跟随系统",
        light: "浅色",
        dark: "深色"
    )

    private static let zhHant = AppStrings(
        home: "首頁",
        discover: "發現頁",
        weekly: "每週推薦",
        collections: "合集",
        favorites: "我的收藏",
        viewAll: "查看全部",
        seeMore: "查看更多",
        latestWallpapers: "最新桌布",
        latestCollections: "最新合集",
        weeklyKicker: "最近四週",
        recentWeekly: "每週推薦相簿",
        wallpapersCount: "%d 張桌布",
        picksCount: "%d 張精選",
        collectionsKicker: "社群整理",
        weeklyArchiveKicker: "往期精選",
        pastWeeks: "全部週刊",
        collectionListTitle: "全部合集",
        collectionListKicker: "可收藏的主題書架",
        emptyCollection: "這個合集還沒有桌布。",
        emptyFavoritesTitle: "還沒有收藏",
        emptyFavoritesMessage: "你收藏的桌布會出現在這裡。",
        signInFavorites: "登入後查看和管理你的收藏、下載與個人設定。",
        signInRegister: "登入 / 註冊",
        settings: "設定",
        language: "語言",
        appearance: "外觀",
        lockPreview: "鎖定畫面預覽",
        upload: "上傳",
        editProfile: "編輯資料",
        password: "密碼",
        signOut: "登出",
        coins: "金幣",
        coinHint: "上傳獲得 1 枚，下載消耗 1 枚",
        preview: "預覽",
        downloadOneCoin: "下載 · 1 金幣",
        saving: "儲存中…",
        savedToPhotos: "已儲存到照片",
        notEnoughCoins: "金幣不足",
        downloadFailed: "下載失敗",
        signInRequired: "需要登入",
        signInDetailMessage: "請在我的收藏頁登入後再按讚、收藏或下載桌布。",
        ok: "好",
        cancel: "取消",
        addToCollection: "加入合集",
        newCollection: "新合集",
        collectionName: "合集名稱",
        create: "建立",
        myCollections: "我的合集",
        noCollectionsYet: "還沒有合集",
        done: "完成",
        week: "第 %d 週",
        year: "%d 年",
        noMatches: "沒有符合結果",
        noMatchesMessage: "目前篩選下還沒有合適的桌布。",
        endOfArchive: "已到歸檔末尾",
        searchWallpapers: "搜尋桌布",
        all: "全部",
        latest: "最新",
        popular: "熱門",
        forYou: "為你推薦",
        ai: "AI",
        system: "跟隨系統",
        light: "淺色",
        dark: "深色"
    )

    private static let ja = AppStrings(
        home: "ホーム",
        discover: "発見",
        weekly: "週間おすすめ",
        collections: "コレクション",
        favorites: "お気に入り",
        viewAll: "すべて見る",
        seeMore: "もっと見る",
        latestWallpapers: "新着壁紙",
        latestCollections: "新着コレクション",
        weeklyKicker: "直近 4 週",
        recentWeekly: "週間アルバム",
        wallpapersCount: "%d 枚の壁紙",
        picksCount: "%d 枚のおすすめ",
        collectionsKicker: "コミュニティ編集",
        weeklyArchiveKicker: "過去のおすすめ",
        pastWeeks: "すべての週",
        collectionListTitle: "すべてのコレクション",
        collectionListKicker: "保存できるテーマ棚",
        emptyCollection: "このコレクションにはまだ壁紙がありません。",
        emptyFavoritesTitle: "お気に入りはまだありません",
        emptyFavoritesMessage: "お気に入りにした壁紙がここに表示されます。",
        signInFavorites: "ログインするとお気に入り、ダウンロード、設定を管理できます。",
        signInRegister: "ログイン / 登録",
        settings: "設定",
        language: "言語",
        appearance: "表示",
        lockPreview: "ロック画面プレビュー",
        upload: "アップロード",
        editProfile: "プロフィール編集",
        password: "パスワード",
        signOut: "ログアウト",
        coins: "コイン",
        coinHint: "アップロードで 1 枚獲得、ダウンロードで 1 枚使用",
        preview: "プレビュー",
        downloadOneCoin: "ダウンロード · 1 コイン",
        saving: "保存中…",
        savedToPhotos: "写真に保存済み",
        notEnoughCoins: "コイン不足",
        downloadFailed: "ダウンロード失敗",
        signInRequired: "ログインが必要です",
        signInDetailMessage: "壁紙のいいね、保存、ダウンロードにはお気に入りタブからログインしてください。",
        ok: "OK",
        cancel: "キャンセル",
        addToCollection: "コレクションに追加",
        newCollection: "新規コレクション",
        collectionName: "コレクション名",
        create: "作成",
        myCollections: "自分のコレクション",
        noCollectionsYet: "コレクションはまだありません",
        done: "完了",
        week: "第 %d 週",
        year: "%d 年",
        noMatches: "一致する壁紙はありません",
        noMatchesMessage: "この条件に合う壁紙はまだありません。",
        endOfArchive: "アーカイブの最後です",
        searchWallpapers: "壁紙を検索",
        all: "すべて",
        latest: "新着",
        popular: "人気",
        forYou: "おすすめ",
        ai: "AI",
        system: "システム",
        light: "ライト",
        dark: "ダーク"
    )

    private static let en = AppStrings(
        home: "Home",
        discover: "Discover",
        weekly: "Weekly",
        collections: "Collections",
        favorites: "Favorites",
        viewAll: "View all",
        seeMore: "See more",
        latestWallpapers: "Latest Wallpapers",
        latestCollections: "Latest Collections",
        weeklyKicker: "Last four weeks",
        recentWeekly: "Weekly Albums",
        wallpapersCount: "%d wallpapers",
        picksCount: "%d picks",
        collectionsKicker: "Community shelves",
        weeklyArchiveKicker: "Back catalogue",
        pastWeeks: "Past Weeks",
        collectionListTitle: "All Collections",
        collectionListKicker: "Theme shelves worth saving",
        emptyCollection: "This collection has no wallpapers yet.",
        emptyFavoritesTitle: "No favorites yet",
        emptyFavoritesMessage: "Wallpapers you favorite will appear here.",
        signInFavorites: "Sign in to manage your favorites, downloads and preferences.",
        signInRegister: "Sign In / Register",
        settings: "Settings",
        language: "Language",
        appearance: "Appearance",
        lockPreview: "Lock Preview",
        upload: "Upload",
        editProfile: "Edit Profile",
        password: "Password",
        signOut: "Sign Out",
        coins: "Coins",
        coinHint: "Earn 1 per upload, downloads cost 1",
        preview: "Preview",
        downloadOneCoin: "Download · 1 coin",
        saving: "Saving…",
        savedToPhotos: "Saved to Photos",
        notEnoughCoins: "Not enough coins",
        downloadFailed: "Download failed",
        signInRequired: "Sign in required",
        signInDetailMessage: "Log in from Favorites to like, favorite and download wallpapers.",
        ok: "OK",
        cancel: "Cancel",
        addToCollection: "Add to Collection",
        newCollection: "New collection",
        collectionName: "Collection name",
        create: "Create",
        myCollections: "My collections",
        noCollectionsYet: "No collections yet",
        done: "Done",
        week: "Week %d",
        year: "%d",
        noMatches: "No matches",
        noMatchesMessage: "Nothing in the archive fits those filters yet.",
        endOfArchive: "End of archive",
        searchWallpapers: "Search wallpapers",
        all: "All",
        latest: "Latest",
        popular: "Popular",
        forYou: "For You",
        ai: "AI",
        system: "System",
        light: "Light",
        dark: "Dark"
    )
}
