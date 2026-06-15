import Foundation

struct AppStrings {
    let home: String
    let discover: String
    let weekly: String
    let collections: String
    let favorites: String
    let me: String
    let accountKicker: String
    let accountLibraryTitle: String
    let myDownloads: String
    let myLikes: String
    let myCoins: String
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
    let emptyDownloadsTitle: String
    let emptyDownloadsMessage: String
    let emptyLikesTitle: String
    let emptyLikesMessage: String
    let emptyCollectionsMessage: String
    let signInFavorites: String
    let signInRegister: String
    let authSignInTitle: String
    let authRegisterTitle: String
    let authUsername: String
    let authEmail: String
    let authPassword: String
    let authUsernamePlaceholder: String
    let authEmailPlaceholder: String
    let authUsernameHelp: String
    let authPasswordHelp: String
    let authSignInSubmit: String
    let authCreateAccountSubmit: String
    let authSigningIn: String
    let authCreating: String
    let authSwitchToRegister: String
    let authSwitchToLogin: String
    let authAcceptLegal: String
    let authLegalIntro: String
    let settings: String
    let language: String
    let appearance: String
    let legal: String
    let termsTitle: String
    let privacyTitle: String
    let dmcaTitle: String
    let legalBodyNote: String
    let lastUpdated: String
    let legalVersion: String
    let about: String
    let appVersion: String
    let lockPreview: String
    let upload: String
    let uploadKicker: String
    let uploadSignedOutMessage: String
    let uploadChoosePhoto: String
    let uploadChooseDifferentPhoto: String
    let uploadProgress: String
    let uploadPendingReview: String
    let uploadPendingMessage: String
    let uploadAnother: String
    let uploadTryAgain: String
    let uploadRulesTitle: String
    let uploadRuleLicensed: String
    let uploadRuleNoWatermarks: String
    let uploadRuleResolution: String
    let uploadRuleReview: String
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
        me: "我的",
        accountKicker: "个人空间",
        accountLibraryTitle: "我的内容",
        myDownloads: "我的下载",
        myLikes: "我的喜欢",
        myCoins: "我的金币",
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
        emptyDownloadsTitle: "还没有下载",
        emptyDownloadsMessage: "你下载过的壁纸会出现在这里。",
        emptyLikesTitle: "还没有喜欢",
        emptyLikesMessage: "你喜欢过的壁纸会出现在这里。",
        emptyCollectionsMessage: "你创建或收藏的合集会出现在这里。",
        signInFavorites: "登录后查看和管理你的收藏、下载与个人设置。",
        signInRegister: "登录 / 注册",
        authSignInTitle: "登录",
        authRegisterTitle: "注册",
        authUsername: "用户名",
        authEmail: "邮箱",
        authPassword: "密码",
        authUsernamePlaceholder: "archivist",
        authEmailPlaceholder: "you@example.com",
        authUsernameHelp: "3-32 个字符，支持字母、数字、点和下划线",
        authPasswordHelp: "至少 6 个字符",
        authSignInSubmit: "登录",
        authCreateAccountSubmit: "创建账号",
        authSigningIn: "正在登录…",
        authCreating: "正在创建…",
        authSwitchToRegister: "还没有账号？注册",
        authSwitchToLogin: "已经有账号？登录",
        authAcceptLegal: "我已阅读并同意服务条款、隐私政策和 DMCA 政策。",
        authLegalIntro: "注册即表示你理解这些条款。法律正文以英文为准。",
        settings: "设置",
        language: "语言",
        appearance: "外观",
        legal: "法律",
        termsTitle: "服务条款",
        privacyTitle: "隐私政策",
        dmcaTitle: "版权 / DMCA",
        legalBodyNote: "以下法律正文沿用官网英文版本，页面标题跟随你的语言设置。",
        lastUpdated: "最后更新",
        legalVersion: "版本",
        about: "关于",
        appVersion: "当前版本",
        lockPreview: "锁屏预览",
        upload: "上传",
        uploadKicker: "分享并赚取金币",
        uploadSignedOutMessage: "登录后即可分享壁纸并赚取金币。",
        uploadChoosePhoto: "选择照片",
        uploadChooseDifferentPhoto: "换一张照片",
        uploadProgress: "上传中… %d%%",
        uploadPendingReview: "已上传，等待审核",
        uploadPendingMessage: "审核通过后，这张壁纸会公开展示；上传奖励会在处理完成后到账。",
        uploadAnother: "继续上传",
        uploadTryAgain: "重试",
        uploadRulesTitle: "上传规则",
        uploadRuleLicensed: "仅上传原创或已获得授权的图片",
        uploadRuleNoWatermarks: "不要上传水印、文字覆盖或人物照片",
        uploadRuleResolution: "高分辨率会获得更好展示，建议 4K 以上",
        uploadRuleReview: "所有上传内容发布前都会经过审核",
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
        signInDetailMessage: "请在我的页登录后再点赞、收藏或下载壁纸。",
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
        me: "我的",
        accountKicker: "個人空間",
        accountLibraryTitle: "我的內容",
        myDownloads: "我的下載",
        myLikes: "我的喜歡",
        myCoins: "我的金幣",
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
        emptyDownloadsTitle: "還沒有下載",
        emptyDownloadsMessage: "你下載過的桌布會出現在這裡。",
        emptyLikesTitle: "還沒有喜歡",
        emptyLikesMessage: "你喜歡過的桌布會出現在這裡。",
        emptyCollectionsMessage: "你建立或收藏的合集會出現在這裡。",
        signInFavorites: "登入後查看和管理你的收藏、下載與個人設定。",
        signInRegister: "登入 / 註冊",
        authSignInTitle: "登入",
        authRegisterTitle: "註冊",
        authUsername: "使用者名稱",
        authEmail: "電子郵件",
        authPassword: "密碼",
        authUsernamePlaceholder: "archivist",
        authEmailPlaceholder: "you@example.com",
        authUsernameHelp: "3-32 個字元，支援字母、數字、點和底線",
        authPasswordHelp: "至少 6 個字元",
        authSignInSubmit: "登入",
        authCreateAccountSubmit: "建立帳號",
        authSigningIn: "正在登入…",
        authCreating: "正在建立…",
        authSwitchToRegister: "還沒有帳號？註冊",
        authSwitchToLogin: "已經有帳號？登入",
        authAcceptLegal: "我已閱讀並同意服務條款、隱私政策和 DMCA 政策。",
        authLegalIntro: "註冊即表示你理解這些條款。法律正文以英文為準。",
        settings: "設定",
        language: "語言",
        appearance: "外觀",
        legal: "法律",
        termsTitle: "服務條款",
        privacyTitle: "隱私政策",
        dmcaTitle: "版權 / DMCA",
        legalBodyNote: "以下法律正文沿用官網英文版本，頁面標題會跟隨你的語言設定。",
        lastUpdated: "最後更新",
        legalVersion: "版本",
        about: "關於",
        appVersion: "目前版本",
        lockPreview: "鎖定畫面預覽",
        upload: "上傳",
        uploadKicker: "分享並賺取金幣",
        uploadSignedOutMessage: "登入後即可分享桌布並賺取金幣。",
        uploadChoosePhoto: "選擇照片",
        uploadChooseDifferentPhoto: "換一張照片",
        uploadProgress: "上傳中… %d%%",
        uploadPendingReview: "已上傳，等待審核",
        uploadPendingMessage: "審核通過後，這張桌布會公開展示；上傳獎勵會在處理完成後入帳。",
        uploadAnother: "繼續上傳",
        uploadTryAgain: "重試",
        uploadRulesTitle: "上傳規則",
        uploadRuleLicensed: "僅上傳原創或已獲授權的圖片",
        uploadRuleNoWatermarks: "不要上傳浮水印、文字覆蓋或人物照片",
        uploadRuleResolution: "高解析度會獲得更好展示，建議 4K 以上",
        uploadRuleReview: "所有上傳內容發布前都會經過審核",
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
        signInDetailMessage: "請在我的頁登入後再按讚、收藏或下載桌布。",
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
        me: "マイページ",
        accountKicker: "パーソナル",
        accountLibraryTitle: "マイライブラリ",
        myDownloads: "ダウンロード",
        myLikes: "いいね",
        myCoins: "コイン",
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
        emptyDownloadsTitle: "ダウンロードはまだありません",
        emptyDownloadsMessage: "ダウンロードした壁紙がここに表示されます。",
        emptyLikesTitle: "いいねはまだありません",
        emptyLikesMessage: "いいねした壁紙がここに表示されます。",
        emptyCollectionsMessage: "作成または保存したコレクションがここに表示されます。",
        signInFavorites: "ログインするとお気に入り、ダウンロード、設定を管理できます。",
        signInRegister: "ログイン / 登録",
        authSignInTitle: "ログイン",
        authRegisterTitle: "新規登録",
        authUsername: "ユーザー名",
        authEmail: "メールアドレス",
        authPassword: "パスワード",
        authUsernamePlaceholder: "archivist",
        authEmailPlaceholder: "you@example.com",
        authUsernameHelp: "3〜32文字。英数字、ドット、アンダースコアが使えます",
        authPasswordHelp: "6文字以上",
        authSignInSubmit: "ログイン",
        authCreateAccountSubmit: "アカウントを作成",
        authSigningIn: "ログイン中…",
        authCreating: "作成中…",
        authSwitchToRegister: "はじめての方は登録",
        authSwitchToLogin: "アカウントをお持ちの方はログイン",
        authAcceptLegal: "利用規約、プライバシーポリシー、DMCAポリシーに同意します。",
        authLegalIntro: "登録すると、これらの条件を理解したものとみなされます。法的本文は英語版を正文とします。",
        settings: "設定",
        language: "言語",
        appearance: "表示",
        legal: "法務",
        termsTitle: "利用規約",
        privacyTitle: "プライバシーポリシー",
        dmcaTitle: "著作権 / DMCA",
        legalBodyNote: "以下の法的本文は公式サイトの英語版を使用しています。ページ見出しは言語設定に合わせて表示されます。",
        lastUpdated: "最終更新",
        legalVersion: "バージョン",
        about: "このアプリについて",
        appVersion: "現在のバージョン",
        lockPreview: "ロック画面プレビュー",
        upload: "アップロード",
        uploadKicker: "共有してコインを獲得",
        uploadSignedOutMessage: "ログインすると壁紙を共有してコインを獲得できます。",
        uploadChoosePhoto: "写真を選択",
        uploadChooseDifferentPhoto: "別の写真を選択",
        uploadProgress: "アップロード中… %d%%",
        uploadPendingReview: "アップロード済み、審査待ち",
        uploadPendingMessage: "承認されると壁紙が公開されます。アップロード報酬は処理完了後に反映されます。",
        uploadAnother: "別の壁紙をアップロード",
        uploadTryAgain: "再試行",
        uploadRulesTitle: "アップロードルール",
        uploadRuleLicensed: "オリジナル、または適切に許諾された画像のみ",
        uploadRuleNoWatermarks: "透かし、文字入れ、人物写真は避けてください",
        uploadRuleResolution: "高解像度ほど表示されやすくなります。4K以上を推奨",
        uploadRuleReview: "すべてのアップロードは公開前に審査されます",
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
        signInDetailMessage: "壁紙のいいね、保存、ダウンロードにはマイページからログインしてください。",
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
        me: "Me",
        accountKicker: "Personal space",
        accountLibraryTitle: "My library",
        myDownloads: "My downloads",
        myLikes: "My likes",
        myCoins: "My coins",
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
        emptyDownloadsTitle: "No downloads yet",
        emptyDownloadsMessage: "Wallpapers you download will appear here.",
        emptyLikesTitle: "No likes yet",
        emptyLikesMessage: "Wallpapers you like will appear here.",
        emptyCollectionsMessage: "Collections you create or save will appear here.",
        signInFavorites: "Sign in to manage your favorites, downloads and preferences.",
        signInRegister: "Sign In / Register",
        authSignInTitle: "Sign in",
        authRegisterTitle: "Register",
        authUsername: "Username",
        authEmail: "Email",
        authPassword: "Password",
        authUsernamePlaceholder: "archivist",
        authEmailPlaceholder: "you@example.com",
        authUsernameHelp: "3-32 characters: letters, numbers, dot and underscore",
        authPasswordHelp: "At least 6 characters",
        authSignInSubmit: "Sign in",
        authCreateAccountSubmit: "Create account",
        authSigningIn: "Signing in…",
        authCreating: "Creating…",
        authSwitchToRegister: "New here? Register",
        authSwitchToLogin: "Already have an account? Sign in",
        authAcceptLegal: "I have read and agree to the Terms of Service, Privacy Policy and DMCA policy.",
        authLegalIntro: "By registering, you acknowledge these terms. The legal body text is authoritative in English.",
        settings: "Settings",
        language: "Language",
        appearance: "Appearance",
        legal: "Legal",
        termsTitle: "Terms of Service",
        privacyTitle: "Privacy Policy",
        dmcaTitle: "Copyright / DMCA",
        legalBodyNote: "The legal body text below mirrors the English website version. Page chrome follows your language setting.",
        lastUpdated: "Last updated",
        legalVersion: "Version",
        about: "About",
        appVersion: "Current version",
        lockPreview: "Lock Preview",
        upload: "Upload",
        uploadKicker: "Share and earn a coin",
        uploadSignedOutMessage: "Sign in to share wallpapers and earn coins.",
        uploadChoosePhoto: "Choose a photo",
        uploadChooseDifferentPhoto: "Choose a different photo",
        uploadProgress: "Uploading… %d%%",
        uploadPendingReview: "Uploaded, pending review",
        uploadPendingMessage: "Your wallpaper will appear publicly once approved. The upload reward lands after processing.",
        uploadAnother: "Upload another",
        uploadTryAgain: "Try again",
        uploadRulesTitle: "House rules",
        uploadRuleLicensed: "Original or properly licensed images only",
        uploadRuleNoWatermarks: "No watermarks, text overlays or people",
        uploadRuleResolution: "Higher resolution ranks better, 4K+ preferred",
        uploadRuleReview: "Every upload goes through review before publishing",
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
        signInDetailMessage: "Log in from Me to like, favorite and download wallpapers.",
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
