import Foundation

// Strings for the account surface: AccountView (tabs, header, ledger,
// privacy banners, pagination) and the public ProfileView. The four
// instances share one memberwise init, so a missing translation fails
// the build.

struct AccountStrings {
    // ── Account tabs ──
    let tabSettings: String
    let tabUploads: String
    let tabCollections: String
    let tabFavorites: String
    let tabLikes: String
    let tabDownloads: String
    let tabLedger: String

    // ── Header kickers + date formatting ──
    let contributorSince: (String) -> String
    let uploaderSince: (String) -> String
    /// DateFormatter pattern for "member since" on AccountView.
    let memberSinceFormatLong: String
    /// DateFormatter pattern for "member since" on ProfileView.
    let memberSinceFormatShort: String
    /// Locale identifier driving month names in formatted dates.
    let dateLocaleID: String

    // ── Owner header: editing + pills + balance + password sheet ──
    let nicknamePlaceholder: String
    let bioPlaceholder: String
    let save: String
    let editProfile: String
    let password: String
    let upload: String
    let balanceKicker: String
    let coinsUnit: String
    let changePasswordTitle: String
    let currentPassword: String
    let newPasswordPlaceholder: String
    let saving: String
    let newPasswordTooShort: String

    // ── Section head labels (mono kickers) ──
    let headCreated: String
    let headFavorites: String
    let headLikes: String
    let headDownloads: String
    let headPending: String
    let headPublished: String
    let headLedger: String

    // ── Empty states ──
    let emptyFavorites: String
    let emptyLikes: String
    let emptyDownloads: String
    let emptyPublished: String
    let nothingHere: String
    let emptySectionMessage: String
    let emptyCollectionsTitle: String
    let emptyCollectionsMessage: String

    // ── Auto-shuffle panel ──
    let autoShuffleKicker: String
    let autoShuffleTitle: String
    let autoShuffleLocalStatus: (String) -> String
    let autoShuffleInterval: String
    let autoShuffleCustom: String
    let autoShuffleStepDetail: String
    let collectionAutoPlay: String
    let collectionAutoPlayActive: String
    let collectionAutoPlayPreparing: String
    let collectionAutoPlayStop: String
    let collectionAutoPlayStatus: (String) -> String
    let collectionAutoPlayFallback: String
    let collectionAutoPlayDownloadTitle: String
    let collectionAutoPlayDownloadMessage: (Int) -> String
    let collectionAutoPlayDownloadConfirm: String

    // ── Privacy banner ──
    let nounFavorites: String
    let nounLikes: String
    let nounDownloads: String
    let privacyStatus: (String, Bool) -> String
    let privacyPublicDesc: String
    let privacyPrivateDesc: String
    let makePublic: String
    let makePrivate: String

    // ── Coin ledger ──
    let lifetimeBalance: String
    let kickerEarned: String
    let kickerSpent: String
    let kickerNextEarn: String
    let thisPage: String
    let perUpload: String
    let txErrorTitle: String
    let txEmptyTitle: String
    let txEmptyMessage: String
    let txWelcomeBonus: String
    let txUploadReward: String
    let txDownload: String
    let txDownloadReceived: String
    let txAdminGrant: String

    // ── Relative time (ledger rows) ──
    let justNow: String
    let minAgo: (Int) -> String
    let hrAgo: (Int) -> String
    let daysAgo: (Int) -> String
    let monthsAgo: (Int) -> String
    let yearsAgo: (Int) -> String

    // ── Pagination ──
    let pagePrev: String
    let pageNext: String
    let pageOf: (Int, Int) -> String

    // ── Public profile (ProfileView) ──
    let profileTabUploaded: String
    let profileTabLiked: String
    let profileTabFavorited: String
    let statUploads: String
    let statDownloads: String
    let statLikes: String
    let statCollections: String
}

private let accountEN = AccountStrings(
    tabSettings: "Settings",
    tabUploads: "Uploads",
    tabCollections: "Collections",
    tabFavorites: "Favorites",
    tabLikes: "Likes",
    tabDownloads: "Downloads",
    tabLedger: "Coin ledger",
    contributorSince: { "Contributor · Member since \($0)" },
    uploaderSince: { "Uploader · Member since \($0)" },
    memberSinceFormatLong: "MMMM yyyy",
    memberSinceFormatShort: "MMM yyyy",
    dateLocaleID: "en_US",
    nicknamePlaceholder: "Nickname",
    bioPlaceholder: "Bio",
    save: "Save",
    editProfile: "Edit profile",
    password: "Password",
    upload: "Upload",
    balanceKicker: "BALANCE",
    coinsUnit: "COINS",
    changePasswordTitle: "CHANGE PASSWORD",
    currentPassword: "Current password",
    newPasswordPlaceholder: "New password (min 8 chars)",
    saving: "Saving…",
    newPasswordTooShort: "New password must be at least 8 characters.",
    headCreated: "CREATED",
    headFavorites: "FAVORITES",
    headLikes: "LIKES",
    headDownloads: "DOWNLOADS",
    headPending: "PENDING",
    headPublished: "PUBLISHED",
    headLedger: "LEDGER",
    emptyFavorites: "No favorites yet.",
    emptyLikes: "No likes yet.",
    emptyDownloads: "No downloads yet.",
    emptyPublished: "No published wallpapers yet.",
    nothingHere: "Nothing here yet.",
    emptySectionMessage: "This section will fill in once matching activity appears.",
    emptyCollectionsTitle: "No collections yet.",
    emptyCollectionsMessage: "Collections will appear here when this user starts grouping wallpapers into sets.",
    autoShuffleKicker: "AUTO-SHUFFLE",
    autoShuffleTitle: "Auto-shuffle",
    autoShuffleLocalStatus: { "Switch to a random downloaded wallpaper every \($0)" },
    autoShuffleInterval: "Interval",
    autoShuffleCustom: "Custom",
    autoShuffleStepDetail: "15-minute steps",
    collectionAutoPlay: "Auto-play",
    collectionAutoPlayActive: "Playing",
    collectionAutoPlayPreparing: "Preparing…",
    collectionAutoPlayStop: "Use downloads",
    collectionAutoPlayStatus: { "Auto-play is prioritizing “\($0)”." },
    collectionAutoPlayFallback: "No collection is prioritized. Auto-shuffle falls back to all local downloads.",
    collectionAutoPlayDownloadTitle: "Download collection wallpapers?",
    collectionAutoPlayDownloadMessage: { count in
        count == 1
            ? "1 wallpaper in this collection is not local yet. Wallpaper Exchange will download it before enabling auto-play."
            : "\(count) wallpapers in this collection are not local yet. Wallpaper Exchange will download them before enabling auto-play."
    },
    collectionAutoPlayDownloadConfirm: "Download and enable",
    nounFavorites: "favorites",
    nounLikes: "likes",
    nounDownloads: "downloads",
    privacyStatus: { noun, isPublic in "Your \(noun) are \(isPublic ? "public" : "private")" },
    privacyPublicDesc: "Anyone can see this list on your profile.",
    privacyPrivateDesc: "Only you can see this list.",
    makePublic: "Make public",
    makePrivate: "Make private",
    lifetimeBalance: "Lifetime balance",
    kickerEarned: "EARNED",
    kickerSpent: "SPENT",
    kickerNextEarn: "NEXT EARN",
    thisPage: "This page",
    perUpload: "Per upload",
    txErrorTitle: "Could not load transactions",
    txEmptyTitle: "No transactions yet.",
    txEmptyMessage: "Coin activity will show here after uploads, trades, and system grants.",
    txWelcomeBonus: "Welcome bonus",
    txUploadReward: "Upload reward",
    txDownload: "Download",
    txDownloadReceived: "Download received",
    txAdminGrant: "Admin grant",
    justNow: "just now",
    minAgo: { "\($0) min ago" },
    hrAgo: { "\($0) hr ago" },
    daysAgo: { "\($0)d ago" },
    monthsAgo: { "\($0)mo ago" },
    yearsAgo: { "\($0)y ago" },
    pagePrev: "PREV",
    pageNext: "NEXT",
    pageOf: { "PAGE \($0) OF \($1)" },
    profileTabUploaded: "Uploaded",
    profileTabLiked: "Liked",
    profileTabFavorited: "Favorited",
    statUploads: "UPLOADS",
    statDownloads: "DOWNLOADS",
    statLikes: "LIKES",
    statCollections: "COLLECTIONS"
)

private let accountZhCN = AccountStrings(
    tabSettings: "设置",
    tabUploads: "上传",
    tabCollections: "合集",
    tabFavorites: "收藏",
    tabLikes: "点赞",
    tabDownloads: "下载",
    tabLedger: "金币流水",
    contributorSince: { "贡献者 · \($0)加入" },
    uploaderSince: { "创作者 · \($0)加入" },
    memberSinceFormatLong: "yyyy年M月",
    memberSinceFormatShort: "yyyy年M月",
    dateLocaleID: "zh_CN",
    nicknamePlaceholder: "昵称",
    bioPlaceholder: "个人简介",
    save: "保存",
    editProfile: "编辑资料",
    password: "密码",
    upload: "上传",
    balanceKicker: "余额",
    coinsUnit: "金币",
    changePasswordTitle: "修改密码",
    currentPassword: "当前密码",
    newPasswordPlaceholder: "新密码（至少 8 位）",
    saving: "保存中…",
    newPasswordTooShort: "新密码至少需要 8 个字符。",
    headCreated: "已创建",
    headFavorites: "收藏",
    headLikes: "点赞",
    headDownloads: "下载",
    headPending: "待发布",
    headPublished: "已发布",
    headLedger: "金币流水",
    emptyFavorites: "还没有收藏。",
    emptyLikes: "还没有点赞。",
    emptyDownloads: "还没有下载记录。",
    emptyPublished: "还没有已发布的壁纸。",
    nothingHere: "这里还什么都没有。",
    emptySectionMessage: "一旦有相关动态，这里就会展示出来。",
    emptyCollectionsTitle: "还没有合集。",
    emptyCollectionsMessage: "当该用户开始把壁纸整理成合集时，就会显示在这里。",
    autoShuffleKicker: "自动轮换",
    autoShuffleTitle: "自动轮换",
    autoShuffleLocalStatus: { "每 \($0) 随机切换一张已下载壁纸" },
    autoShuffleInterval: "间隔",
    autoShuffleCustom: "自定义",
    autoShuffleStepDetail: "每次调整 15 分钟",
    collectionAutoPlay: "自动播放",
    collectionAutoPlayActive: "播放中",
    collectionAutoPlayPreparing: "准备中…",
    collectionAutoPlayStop: "使用下载列表",
    collectionAutoPlayStatus: { "自动播放会优先使用「\($0)」。" },
    collectionAutoPlayFallback: "当前没有指定合集，自动轮换会使用全部本地下载壁纸。",
    collectionAutoPlayDownloadTitle: "下载合集内壁纸？",
    collectionAutoPlayDownloadMessage: { "该合集有 \($0) 张壁纸还没有下载到本地。启用自动播放前，会先自动下载这些壁纸。" },
    collectionAutoPlayDownloadConfirm: "下载并启用",
    nounFavorites: "收藏",
    nounLikes: "点赞",
    nounDownloads: "下载记录",
    privacyStatus: { noun, isPublic in "你的\(noun)当前为\(isPublic ? "公开" : "私密")" },
    privacyPublicDesc: "任何人都可以在你的主页看到这个列表。",
    privacyPrivateDesc: "只有你自己可以看到这个列表。",
    makePublic: "设为公开",
    makePrivate: "设为私密",
    lifetimeBalance: "累计余额",
    kickerEarned: "收入",
    kickerSpent: "支出",
    kickerNextEarn: "下次收益",
    thisPage: "本页",
    perUpload: "每次上传",
    txErrorTitle: "交易记录加载失败",
    txEmptyTitle: "暂无交易记录。",
    txEmptyMessage: "上传、兑换或系统发放后，金币流水会显示在这里。",
    txWelcomeBonus: "注册奖励",
    txUploadReward: "上传奖励",
    txDownload: "下载",
    txDownloadReceived: "被下载奖励",
    txAdminGrant: "管理员发放",
    justNow: "刚刚",
    minAgo: { "\($0) 分钟前" },
    hrAgo: { "\($0) 小时前" },
    daysAgo: { "\($0) 天前" },
    monthsAgo: { "\($0) 个月前" },
    yearsAgo: { "\($0) 年前" },
    pagePrev: "上一页",
    pageNext: "下一页",
    pageOf: { "第 \($0) / \($1) 页" },
    profileTabUploaded: "上传",
    profileTabLiked: "点赞",
    profileTabFavorited: "收藏",
    statUploads: "上传",
    statDownloads: "下载",
    statLikes: "点赞",
    statCollections: "合集"
)

private let accountZhTW = AccountStrings(
    tabSettings: "設定",
    tabUploads: "上傳",
    tabCollections: "合輯",
    tabFavorites: "收藏",
    tabLikes: "按讚",
    tabDownloads: "下載",
    tabLedger: "金幣紀錄",
    contributorSince: { "貢獻者 · \($0)加入" },
    uploaderSince: { "創作者 · \($0)加入" },
    memberSinceFormatLong: "yyyy年M月",
    memberSinceFormatShort: "yyyy年M月",
    dateLocaleID: "zh_TW",
    nicknamePlaceholder: "暱稱",
    bioPlaceholder: "個人簡介",
    save: "儲存",
    editProfile: "編輯個人資料",
    password: "密碼",
    upload: "上傳",
    balanceKicker: "餘額",
    coinsUnit: "金幣",
    changePasswordTitle: "變更密碼",
    currentPassword: "目前密碼",
    newPasswordPlaceholder: "新密碼（至少 8 個字元）",
    saving: "儲存中…",
    newPasswordTooShort: "新密碼至少需要 8 個字元。",
    headCreated: "已建立",
    headFavorites: "收藏",
    headLikes: "按讚",
    headDownloads: "下載",
    headPending: "待發佈",
    headPublished: "已發佈",
    headLedger: "金幣紀錄",
    emptyFavorites: "還沒有收藏。",
    emptyLikes: "還沒有按讚的桌布。",
    emptyDownloads: "還沒有下載記錄。",
    emptyPublished: "還沒有已發佈的桌布。",
    nothingHere: "這裡還什麼都沒有。",
    emptySectionMessage: "一旦有相關動態，這裡就會顯示出來。",
    emptyCollectionsTitle: "還沒有合輯。",
    emptyCollectionsMessage: "當這位使用者開始把桌布整理成合輯時，就會顯示在這裡。",
    autoShuffleKicker: "自動輪換",
    autoShuffleTitle: "自動輪換",
    autoShuffleLocalStatus: { "每 \($0) 隨機切換一張已下載桌布" },
    autoShuffleInterval: "間隔",
    autoShuffleCustom: "自訂",
    autoShuffleStepDetail: "每次調整 15 分鐘",
    collectionAutoPlay: "自動播放",
    collectionAutoPlayActive: "播放中",
    collectionAutoPlayPreparing: "準備中…",
    collectionAutoPlayStop: "使用下載清單",
    collectionAutoPlayStatus: { "自動播放會優先使用「\($0)」。" },
    collectionAutoPlayFallback: "目前沒有指定合輯，自動輪換會使用全部本機下載桌布。",
    collectionAutoPlayDownloadTitle: "下載合輯內桌布？",
    collectionAutoPlayDownloadMessage: { "此合輯有 \($0) 張桌布尚未下載到本機。啟用自動播放前，會先自動下載這些桌布。" },
    collectionAutoPlayDownloadConfirm: "下載並啟用",
    nounFavorites: "收藏",
    nounLikes: "按讚",
    nounDownloads: "下載記錄",
    privacyStatus: { noun, isPublic in "你的\(noun)目前為\(isPublic ? "公開" : "私人")" },
    privacyPublicDesc: "任何人都可以在你的個人頁面看到這個清單。",
    privacyPrivateDesc: "只有你自己看得到這個清單。",
    makePublic: "設為公開",
    makePrivate: "設為私人",
    lifetimeBalance: "累計餘額",
    kickerEarned: "收入",
    kickerSpent: "支出",
    kickerNextEarn: "下次收益",
    thisPage: "本頁",
    perUpload: "每次上傳",
    txErrorTitle: "交易記錄載入失敗",
    txEmptyTitle: "尚無交易記錄。",
    txEmptyMessage: "上傳、兌換或系統發放後，金幣紀錄會顯示在這裡。",
    txWelcomeBonus: "註冊獎勵",
    txUploadReward: "上傳獎勵",
    txDownload: "下載",
    txDownloadReceived: "被下載獎勵",
    txAdminGrant: "管理員發放",
    justNow: "剛剛",
    minAgo: { "\($0) 分鐘前" },
    hrAgo: { "\($0) 小時前" },
    daysAgo: { "\($0) 天前" },
    monthsAgo: { "\($0) 個月前" },
    yearsAgo: { "\($0) 年前" },
    pagePrev: "上一頁",
    pageNext: "下一頁",
    pageOf: { "第 \($0) / \($1) 頁" },
    profileTabUploaded: "上傳",
    profileTabLiked: "按讚",
    profileTabFavorited: "收藏",
    statUploads: "上傳",
    statDownloads: "下載",
    statLikes: "按讚",
    statCollections: "合輯"
)

private let accountJA = AccountStrings(
    tabSettings: "設定",
    tabUploads: "アップロード",
    tabCollections: "コレクション",
    tabFavorites: "お気に入り",
    tabLikes: "いいね",
    tabDownloads: "ダウンロード",
    tabLedger: "コイン履歴",
    contributorSince: { "コントリビューター · \($0)から参加" },
    uploaderSince: { "アップローダー · \($0)から参加" },
    memberSinceFormatLong: "yyyy年M月",
    memberSinceFormatShort: "yyyy年M月",
    dateLocaleID: "ja_JP",
    nicknamePlaceholder: "ニックネーム",
    bioPlaceholder: "自己紹介",
    save: "保存",
    editProfile: "プロフィールを編集",
    password: "パスワード",
    upload: "アップロード",
    balanceKicker: "残高",
    coinsUnit: "コイン",
    changePasswordTitle: "パスワードを変更",
    currentPassword: "現在のパスワード",
    newPasswordPlaceholder: "新しいパスワード（8 文字以上）",
    saving: "保存中…",
    newPasswordTooShort: "新しいパスワードは 8 文字以上にしてください。",
    headCreated: "作成済み",
    headFavorites: "お気に入り",
    headLikes: "いいね",
    headDownloads: "ダウンロード",
    headPending: "公開待ち",
    headPublished: "公開済み",
    headLedger: "コイン履歴",
    emptyFavorites: "まだお気に入りがありません。",
    emptyLikes: "まだいいねがありません。",
    emptyDownloads: "まだダウンロードがありません。",
    emptyPublished: "公開済みの壁紙はまだありません。",
    nothingHere: "まだ何もありません。",
    emptySectionMessage: "該当するアクティビティがあると、ここに表示されます。",
    emptyCollectionsTitle: "コレクションはまだありません。",
    emptyCollectionsMessage: "このユーザーが壁紙をコレクションにまとめると、ここに表示されます。",
    autoShuffleKicker: "自動シャッフル",
    autoShuffleTitle: "自動シャッフル",
    autoShuffleLocalStatus: { "\($0)ごとにダウンロード済み壁紙をランダムに切り替えます" },
    autoShuffleInterval: "間隔",
    autoShuffleCustom: "カスタム",
    autoShuffleStepDetail: "15分単位で調整",
    collectionAutoPlay: "自動再生",
    collectionAutoPlayActive: "再生中",
    collectionAutoPlayPreparing: "準備中…",
    collectionAutoPlayStop: "ダウンロードを使用",
    collectionAutoPlayStatus: { "自動再生は「\($0)」を優先します。" },
    collectionAutoPlayFallback: "優先コレクションはありません。自動シャッフルはローカルの全ダウンロードを使用します。",
    collectionAutoPlayDownloadTitle: "コレクションの壁紙をダウンロードしますか？",
    collectionAutoPlayDownloadMessage: { "\($0)枚の壁紙がまだローカルにありません。自動再生を有効にする前にダウンロードします。" },
    collectionAutoPlayDownloadConfirm: "ダウンロードして有効化",
    nounFavorites: "お気に入り",
    nounLikes: "いいね",
    nounDownloads: "ダウンロード履歴",
    privacyStatus: { noun, isPublic in "あなたの\(noun)は\(isPublic ? "公開" : "非公開")です" },
    privacyPublicDesc: "このリストはプロフィール上で誰でも見られます。",
    privacyPrivateDesc: "このリストはあなただけが見られます。",
    makePublic: "公開する",
    makePrivate: "非公開にする",
    lifetimeBalance: "累計残高",
    kickerEarned: "獲得",
    kickerSpent: "消費",
    kickerNextEarn: "次の獲得",
    thisPage: "このページ",
    perUpload: "アップロードごと",
    txErrorTitle: "取引履歴を読み込めませんでした",
    txEmptyTitle: "まだ取引はありません。",
    txEmptyMessage: "アップロード・交換・システム付与があると、コインの履歴がここに表示されます。",
    txWelcomeBonus: "登録ボーナス",
    txUploadReward: "アップロード報酬",
    txDownload: "ダウンロード",
    txDownloadReceived: "ダウンロード報酬",
    txAdminGrant: "管理者付与",
    justNow: "たった今",
    minAgo: { "\($0)分前" },
    hrAgo: { "\($0)時間前" },
    daysAgo: { "\($0)日前" },
    monthsAgo: { "\($0)か月前" },
    yearsAgo: { "\($0)年前" },
    pagePrev: "前へ",
    pageNext: "次へ",
    pageOf: { "\($0) / \($1) ページ" },
    profileTabUploaded: "アップロード",
    profileTabLiked: "いいね",
    profileTabFavorited: "お気に入り",
    statUploads: "アップロード",
    statDownloads: "ダウンロード",
    statLikes: "いいね",
    statCollections: "コレクション"
)

extension L10n {
    static var account: AccountStrings {
        switch lang {
        case .en: accountEN
        case .zhCN: accountZhCN
        case .zhTW: accountZhTW
        case .ja: accountJA
        }
    }
}
