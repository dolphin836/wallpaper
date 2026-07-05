import Foundation

// Home / Weekly / Mac App page strings (HomeView, WeeklyView,
// MacAppView). Section titles are split into an accent word and the
// rest — titleText renders them back-to-back, so the EN rest strings
// carry their own leading space while CJK joins without one. The four
// instances share one memberwise init, so a missing translation fails
// the build.

struct HomeStrings {
    // Home feed.
    let homeFeedError: String
    let weeklyKicker: (Int) -> String        // "Curation · Week N"
    let weeklyKickerFallback: String
    let weeklyTitleAccent: String
    let weeklyTitleRest: String
    let viewArchive: String
    let browseMore: String
    let liveKicker: String
    let liveTitleAccent: String
    let liveTitleRest: String
    let allLive: String
    let aiKicker: String
    let aiTitleAccent: String
    let aiTitleRest: String
    let allAI: String
    let collectionsKicker: String
    let collectionsTitleAccent: String
    let collectionsTitleRest: String
    let allCollections: String

    // Hero card / live tile.
    let heroKicker: (Int, Int) -> String     // (week, year) — caps kicker
    let tradeForOne: String
    let liveBadge: String

    // Weekly archive.
    let archiveKicker: String
    let archiveTitle: String
    let archiveIntro: String
    let archiveEmptyTitle: String
    let archiveEmptyMessage: String
    let issueLabel: String
    let picksCountCaps: (Int) -> String      // "N PICKS" — caps meta line
    let viewAllPicks: (Int) -> String
    let weekTitle: (Int) -> String

    // Mac App tab.
    let runningKicker: String
    let appBlurb: String
    let checkForUpdates: String
    let openWebApp: String
    let releaseNotesKicker: String
    let releaseNotesErrorTitle: String
    let currentBadge: String
    let releaseNotesEmptyTitle: String
    let releaseNotesEmptyMessage: String
}

private let homeEN = HomeStrings(
    homeFeedError: "The home feed could not load. Please try again.",
    weeklyKicker: { "Curation · Week \($0)" },
    weeklyKickerFallback: "Curated each Friday",
    weeklyTitleAccent: "This week's",
    weeklyTitleRest: " picks.",
    viewArchive: "View archive →",
    browseMore: "Browse more →",
    liveKicker: "Motion · hover to preview",
    liveTitleAccent: "Live",
    liveTitleRest: " wallpapers.",
    allLive: "All live wallpapers →",
    aiKicker: "AI Lab · synthetic samples",
    aiTitleAccent: "Generated",
    aiTitleRest: " this week.",
    allAI: "All AI wallpapers →",
    collectionsKicker: "Editorial sets · themed bundles",
    collectionsTitleAccent: "Themed",
    collectionsTitleRest: " collections.",
    allCollections: "All collections →",
    heroKicker: { week, year in "CURATION · WEEK \(week) · \(year)" },
    tradeForOne: "Trade for 1",
    liveBadge: "LIVE",
    archiveKicker: "The Archive",
    archiveTitle: "Every Friday, a new ten.",
    archiveIntro: "We publish ten wallpapers each ISO week. Once a piece lands in a drop it never returns. Pick an issue from the timeline.",
    archiveEmptyTitle: "No weekly drops yet.",
    archiveEmptyMessage: "The archive will appear once the first weekly curation has been published.",
    issueLabel: "ISSUE",
    picksCountCaps: { "\($0) PICKS" },
    viewAllPicks: { "View all \($0) picks" },
    weekTitle: { "Week \($0)" },
    runningKicker: "You're running",
    appBlurb: "Native menu-bar quick actions plus a Dock-visible main window. Drag wallpapers straight to your desktop, set per-display in detail, or let auto-shuffle rotate on your own schedule.",
    checkForUpdates: "Check for updates",
    openWebApp: "Open the web app",
    releaseNotesKicker: "Release notes",
    releaseNotesErrorTitle: "Could not load release notes",
    currentBadge: "CURRENT",
    releaseNotesEmptyTitle: "No release notes available.",
    releaseNotesEmptyMessage: "Version history will appear here when the release feed is available."
)

private let homeZhCN = HomeStrings(
    homeFeedError: "首页内容加载失败，请重试。",
    weeklyKicker: { "精选 · 第 \($0) 周" },
    weeklyKickerFallback: "每周五更新",
    weeklyTitleAccent: "本周",
    weeklyTitleRest: "精选。",
    viewArchive: "查看往期 →",
    browseMore: "浏览更多 →",
    liveKicker: "动态 · 悬停预览",
    liveTitleAccent: "动态",
    liveTitleRest: "壁纸。",
    allLive: "全部动态壁纸 →",
    aiKicker: "AI 实验室 · 生成样片",
    aiTitleAccent: "AI 生成",
    aiTitleRest: "新作。",
    allAI: "全部 AI 壁纸 →",
    collectionsKicker: "编辑精选 · 主题套组",
    collectionsTitleAccent: "主题",
    collectionsTitleRest: "合集。",
    allCollections: "全部合集 →",
    heroKicker: { week, year in "精选 · 第 \(week) 周 · \(year)" },
    tradeForOne: "1 金币兑换",
    liveBadge: "动态",
    archiveKicker: "往期档案",
    archiveTitle: "每周五，全新十张。",
    archiveIntro: "我们每个 ISO 周发布十张壁纸。作品一旦入选某期便不再重复出现。从时间线中挑选一期吧。",
    archiveEmptyTitle: "暂无每周精选。",
    archiveEmptyMessage: "首期每周精选发布后，档案将显示在这里。",
    issueLabel: "期号",
    picksCountCaps: { "\($0) 张精选" },
    viewAllPicks: { "查看全部 \($0) 张" },
    weekTitle: { "第 \($0) 周" },
    runningKicker: "正在运行",
    appBlurb: "原生菜单栏快捷操作，加上常驻 Dock 的主窗口。把壁纸直接拖到桌面、在详情页为每台显示器单独设置，或让自动轮换按你的节奏更换壁纸。",
    checkForUpdates: "检查更新",
    openWebApp: "打开网页版",
    releaseNotesKicker: "更新日志",
    releaseNotesErrorTitle: "无法加载更新日志",
    currentBadge: "当前",
    releaseNotesEmptyTitle: "暂无更新日志。",
    releaseNotesEmptyMessage: "发布源可用后，版本历史将显示在这里。"
)

private let homeZhTW = HomeStrings(
    homeFeedError: "首頁內容載入失敗，請再試一次。",
    weeklyKicker: { "精選 · 第 \($0) 週" },
    weeklyKickerFallback: "每週五更新",
    weeklyTitleAccent: "本週",
    weeklyTitleRest: "精選。",
    viewArchive: "查看往期 →",
    browseMore: "瀏覽更多 →",
    liveKicker: "動態 · 游標移入預覽",
    liveTitleAccent: "動態",
    liveTitleRest: "桌布。",
    allLive: "全部動態桌布 →",
    aiKicker: "AI 實驗室 · 生成樣片",
    aiTitleAccent: "AI 生成",
    aiTitleRest: "新作。",
    allAI: "全部 AI 桌布 →",
    collectionsKicker: "編輯精選 · 主題套組",
    collectionsTitleAccent: "主題",
    collectionsTitleRest: "合輯。",
    allCollections: "全部合輯 →",
    heroKicker: { week, year in "精選 · 第 \(week) 週 · \(year)" },
    tradeForOne: "1 金幣兌換",
    liveBadge: "動態",
    archiveKicker: "往期檔案",
    archiveTitle: "每週五，全新十張。",
    archiveIntro: "我們每個 ISO 週發佈十張桌布。作品一旦入選某期便不再重複出現。從時間軸中挑選一期吧。",
    archiveEmptyTitle: "暫無每週精選。",
    archiveEmptyMessage: "首期每週精選發佈後，檔案將顯示在這裡。",
    issueLabel: "期號",
    picksCountCaps: { "\($0) 張精選" },
    viewAllPicks: { "查看全部 \($0) 張" },
    weekTitle: { "第 \($0) 週" },
    runningKicker: "正在執行",
    appBlurb: "原生選單列快速操作，加上常駐 Dock 的主視窗。將桌布直接拖到桌面、在詳情頁為每台顯示器分別設定，或讓自動輪換依你的排程更換桌布。",
    checkForUpdates: "檢查更新",
    openWebApp: "開啟網頁版",
    releaseNotesKicker: "更新日誌",
    releaseNotesErrorTitle: "無法載入更新日誌",
    currentBadge: "目前",
    releaseNotesEmptyTitle: "暫無更新日誌。",
    releaseNotesEmptyMessage: "發佈來源可用後，版本歷程將顯示在這裡。"
)

private let homeJA = HomeStrings(
    homeFeedError: "ホームフィードを読み込めませんでした。もう一度お試しください。",
    weeklyKicker: { "キュレーション · 第\($0)週" },
    weeklyKickerFallback: "毎週金曜更新",
    weeklyTitleAccent: "今週の",
    weeklyTitleRest: "ピックアップ。",
    viewArchive: "アーカイブを見る →",
    browseMore: "もっと見る →",
    liveKicker: "モーション · ホバーでプレビュー",
    liveTitleAccent: "ライブ",
    liveTitleRest: "壁紙。",
    allLive: "ライブ壁紙をすべて見る →",
    aiKicker: "AI ラボ · 生成サンプル",
    aiTitleAccent: "AI 生成",
    aiTitleRest: "の新作。",
    allAI: "AI 壁紙をすべて見る →",
    collectionsKicker: "エディトリアル · テーマ別セット",
    collectionsTitleAccent: "テーマ別",
    collectionsTitleRest: "コレクション。",
    allCollections: "コレクションをすべて見る →",
    heroKicker: { week, year in "キュレーション · 第\(week)週 · \(year)" },
    tradeForOne: "コイン1枚で交換",
    liveBadge: "ライブ",
    archiveKicker: "アーカイブ",
    archiveTitle: "毎週金曜、新しい10枚。",
    archiveIntro: "毎 ISO 週に10枚の壁紙を公開しています。一度ドロップに掲載された作品は二度と登場しません。タイムラインから号を選んでください。",
    archiveEmptyTitle: "ウィークリードロップはまだありません。",
    archiveEmptyMessage: "最初のウィークリーキュレーションが公開されると、アーカイブがここに表示されます。",
    issueLabel: "号",
    picksCountCaps: { "全\($0)枚" },
    viewAllPicks: { "\($0)枚をすべて見る" },
    weekTitle: { "第\($0)週" },
    runningKicker: "実行中",
    appBlurb: "メニューバーのクイック操作に加え、Dock に表示されるメインウィンドウ。壁紙をデスクトップへ直接ドラッグしたり、詳細ページでディスプレイごとに設定したり、自動シャッフルで好きなスケジュールに合わせて切り替えたりできます。",
    checkForUpdates: "アップデートを確認",
    openWebApp: "ウェブ版を開く",
    releaseNotesKicker: "リリースノート",
    releaseNotesErrorTitle: "リリースノートを読み込めませんでした",
    currentBadge: "現在",
    releaseNotesEmptyTitle: "リリースノートはまだありません。",
    releaseNotesEmptyMessage: "リリースフィードが利用可能になると、バージョン履歴がここに表示されます。"
)

extension L10n {
    static var home: HomeStrings {
        switch lang {
        case .en: homeEN
        case .zhCN: homeZhCN
        case .zhTW: homeZhTW
        case .ja: homeJA
        }
    }
}
