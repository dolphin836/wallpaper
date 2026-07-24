import Foundation

// Strings for UploadView (drop zone, queue, pending uploads, tiles).
// The four instances share one memberwise init, so a missing
// translation fails the build.

struct UploadStrings {
    let headerKicker: String
    let titleLead: String
    let titleAccent: String
    let intro: (Int) -> String
    let reviewKicker: String
    let reviewBody: String
    let dropActive: String
    let dropIdle: String
    let orWord: String
    let pickFromComputer: String
    let maxFilesChip: (Int) -> String
	let videoMinimum: String
    let addMore: (Int, Int) -> String
    let queueLabel: (Int) -> String
    let doneCount: (Int) -> String
    let failedCount: (Int) -> String
    let pendingLabel: String
    let pendingBody: String
    let pendingLoadErrorTitle: String
    let allDoneMessage: String
    let readySummary: (Int, Int) -> String
    let uploadingTitle: String
    let retryFailed: String
    let uploadN: (Int) -> String
    let signedOutTitle: String
    let signedOutBody: String
    let signIn: String
    let maxFilesMessage: (Int) -> String
    let oversizedSkipped: (Int) -> String
    let oneVideoAtATime: String
    let clearImagesFirst: String
    let onlyOneVideo: String
    let clearVideoFirst: String
	let checkingVideoResolution: String
	let lowResolutionBlocked: String
	let unreadableVideoResolution: String
    let receivedOne: String
    let receivedMany: (Int) -> String
    let resultSummary: (Int, Int) -> String
    let videoBadge: String
    let fileBadge: String
    let imageBadge: String
    let vidShort: String
    let imgShort: String
    let wallpaperFallback: (String) -> String
    let statusProcessing: String
    let statusPendingReview: String
    let statusPending: String
    let subProcessing: String
    let subPendingReview: String
    let subPending: String
    let badgeProcessing: String
    let badgeReview: String
    let badgePending: String
}

private let uploadEN = UploadStrings(
    headerKicker: "Contribute · Wallpaper Exchange",
    titleLead: "Share ",
    titleAccent: "what's on your screen.",
    intro: { n in "Drop images (JPG / PNG / HEIC, up to \(n) at a time) or a single video (MP4 / MOV / WebM / MKV). Each file capped at 200 MB. Every upload earns one coin once it clears review." },
    reviewKicker: "ADMIN REVIEW",
    reviewBody: "Everything goes through review before showing up publicly. You can see status on your profile; videos may take a minute longer because we transcode them.",
    dropActive: "Drop them here",
    dropIdle: "Drop images here",
    orWord: "or",
    pickFromComputer: "click to pick from your computer",
    maxFilesChip: { n in "Up to \(n) files" },
	videoMinimum: "Video ≥ 1920 × 1080",
    addMore: { count, max in "Add more · \(count) / \(max)" },
    queueLabel: { n in "QUEUE · \(n)" },
    doneCount: { n in "· \(n) done" },
    failedCount: { n in "· \(n) failed" },
    pendingLabel: "PENDING",
    pendingBody: "Wallpapers still being processed or waiting on admin review. Each tile shows its exact stage; they enter the public archive once approved.",
    pendingLoadErrorTitle: "Could not load pending uploads",
    allDoneMessage: "All set. Your uploads are pending review.",
    readySummary: { pending, errors in
        let base = "\(pending) \(pending == 1 ? "file" : "files") ready to upload"
        return errors > 0 ? "\(base) · \(errors) need a retry" : base
    },
    uploadingTitle: "Uploading",
    retryFailed: "Retry failed",
    uploadN: { n in "Upload \(n) \(n == 1 ? "file" : "files") →" },
    signedOutTitle: "Sign in to share",
    signedOutBody: "Uploads need a Wallpaper Exchange account.",
    signIn: "Sign in",
    maxFilesMessage: { n in "Maximum \(n) files allowed." },
    oversizedSkipped: { n in "\(n) file\(n == 1 ? "" : "s") exceed 200 MB and were skipped." },
    oneVideoAtATime: "Drop one video at a time.",
    clearImagesFirst: "Clear the image batch before adding a video.",
    onlyOneVideo: "Only one video per upload.",
    clearVideoFirst: "Clear the queued video before adding images.",
	checkingVideoResolution: "Reading video resolution…",
	lowResolutionBlocked: "Low resolution · at least 1920 × 1080 required",
	unreadableVideoResolution: "Could not read the video resolution",
    receivedOne: "Upload received. It will appear after review.",
    receivedMany: { n in "\(n) uploads received. They will appear after review." },
    resultSummary: { ok, failed in "\(ok) succeeded, \(failed) failed." },
    videoBadge: "VIDEO",
    fileBadge: "FILE",
    imageBadge: "IMAGE",
    vidShort: "VID",
    imgShort: "IMG",
    wallpaperFallback: { id in "Wallpaper \(id)" },
    statusProcessing: "Processing",
    statusPendingReview: "Pending admin review",
    statusPending: "Pending",
    subProcessing: "Generating device variants",
    subPendingReview: "Usually within a few hours",
    subPending: "Waiting for the next step",
    badgeProcessing: "PROC",
    badgeReview: "REV",
    badgePending: "PEND"
)

private let uploadZhCN = UploadStrings(
    headerKicker: "投稿 · Wallpaper Exchange",
    titleLead: "分享",
    titleAccent: "你屏幕上的风景。",
    intro: { n in "拖入图片（JPG / PNG / HEIC，一次最多 \(n) 张）或单个视频（MP4 / MOV / WebM / MKV）。单个文件不超过 200 MB。每次上传通过审核后可获得 1 金币。" },
    reviewKicker: "管理员审核",
    reviewBody: "所有内容都会先经过审核才会公开展示。你可以在个人主页查看状态；视频需要转码，可能会多花一点时间。",
    dropActive: "松手放到这里",
    dropIdle: "把图片拖到这里",
    orWord: "或",
    pickFromComputer: "点击从电脑中选择",
    maxFilesChip: { n in "最多 \(n) 个文件" },
	videoMinimum: "视频 ≥ 1920 × 1080",
    addMore: { count, max in "继续添加 · \(count) / \(max)" },
    queueLabel: { n in "队列 · \(n)" },
    doneCount: { n in "· \(n) 已完成" },
    failedCount: { n in "· \(n) 失败" },
    pendingLabel: "待发布",
    pendingBody: "这些壁纸正在处理或等待管理员审核。每张卡片会显示当前阶段；审核通过后即会进入公开壁纸库。",
    pendingLoadErrorTitle: "无法加载待发布列表",
    allDoneMessage: "全部完成。你的上传正在等待审核。",
    readySummary: { pending, errors in
        errors > 0 ? "\(pending) 个文件待上传 · \(errors) 个需要重试" : "\(pending) 个文件待上传"
    },
    uploadingTitle: "上传中",
    retryFailed: "重试失败项",
    uploadN: { n in "上传 \(n) 个文件 →" },
    signedOutTitle: "登录后即可分享",
    signedOutBody: "上传需要 Wallpaper Exchange 账号。",
    signIn: "登录",
    maxFilesMessage: { n in "最多只能添加 \(n) 个文件。" },
    oversizedSkipped: { n in "\(n) 个文件超过 200 MB，已被跳过。" },
    oneVideoAtATime: "一次只能拖入一个视频。",
    clearImagesFirst: "请先清空图片队列，再添加视频。",
    onlyOneVideo: "每次上传只能包含一个视频。",
    clearVideoFirst: "请先移除队列中的视频，再添加图片。",
	checkingVideoResolution: "正在读取视频分辨率…",
	lowResolutionBlocked: "低分辨率 · 至少需要 1920 × 1080",
	unreadableVideoResolution: "无法读取视频分辨率",
    receivedOne: "已收到上传，审核通过后即会展示。",
    receivedMany: { n in "已收到 \(n) 个上传，审核通过后即会展示。" },
    resultSummary: { ok, failed in "\(ok) 个成功，\(failed) 个失败。" },
    videoBadge: "视频",
    fileBadge: "文件",
    imageBadge: "图片",
    vidShort: "视频",
    imgShort: "图片",
    wallpaperFallback: { id in "壁纸 \(id)" },
    statusProcessing: "处理中",
    statusPendingReview: "等待管理员审核",
    statusPending: "等待中",
    subProcessing: "正在生成设备适配版本",
    subPendingReview: "通常几小时内完成",
    subPending: "等待下一步处理",
    badgeProcessing: "处理",
    badgeReview: "审核",
    badgePending: "等待"
)

private let uploadZhTW = UploadStrings(
    headerKicker: "投稿 · Wallpaper Exchange",
    titleLead: "分享",
    titleAccent: "你螢幕上的風景。",
    intro: { n in "拖入圖片（JPG / PNG / HEIC，一次最多 \(n) 張）或單一影片（MP4 / MOV / WebM / MKV）。單一檔案不得超過 200 MB。每次上傳通過審核後可獲得 1 金幣。" },
    reviewKicker: "管理員審核",
    reviewBody: "所有內容都會先經過審核才會公開顯示。你可以在個人頁面查看狀態；影片需要轉檔，可能會多花一點時間。",
    dropActive: "放開即可加入",
    dropIdle: "把圖片拖到這裡",
    orWord: "或",
    pickFromComputer: "點按從電腦中選擇",
    maxFilesChip: { n in "最多 \(n) 個檔案" },
	videoMinimum: "影片 ≥ 1920 × 1080",
    addMore: { count, max in "繼續加入 · \(count) / \(max)" },
    queueLabel: { n in "佇列 · \(n)" },
    doneCount: { n in "· \(n) 已完成" },
    failedCount: { n in "· \(n) 失敗" },
    pendingLabel: "待發佈",
    pendingBody: "這些桌布正在處理或等待管理員審核。每張卡片會顯示目前階段；審核通過後即會進入公開桌布庫。",
    pendingLoadErrorTitle: "無法載入待發佈清單",
    allDoneMessage: "全部完成。你的上傳正在等待審核。",
    readySummary: { pending, errors in
        errors > 0 ? "\(pending) 個檔案待上傳 · \(errors) 個需要重試" : "\(pending) 個檔案待上傳"
    },
    uploadingTitle: "上傳中",
    retryFailed: "重試失敗項目",
    uploadN: { n in "上傳 \(n) 個檔案 →" },
    signedOutTitle: "登入後即可分享",
    signedOutBody: "上傳需要 Wallpaper Exchange 帳號。",
    signIn: "登入",
    maxFilesMessage: { n in "最多只能加入 \(n) 個檔案。" },
    oversizedSkipped: { n in "\(n) 個檔案超過 200 MB，已略過。" },
    oneVideoAtATime: "一次只能拖入一個影片。",
    clearImagesFirst: "請先清空圖片佇列，再加入影片。",
    onlyOneVideo: "每次上傳只能包含一個影片。",
    clearVideoFirst: "請先移除佇列中的影片，再加入圖片。",
	checkingVideoResolution: "正在讀取影片解析度…",
	lowResolutionBlocked: "低解析度 · 至少需要 1920 × 1080",
	unreadableVideoResolution: "無法讀取影片解析度",
    receivedOne: "已收到上傳，審核通過後即會顯示。",
    receivedMany: { n in "已收到 \(n) 個上傳，審核通過後即會顯示。" },
    resultSummary: { ok, failed in "\(ok) 個成功，\(failed) 個失敗。" },
    videoBadge: "影片",
    fileBadge: "檔案",
    imageBadge: "圖片",
    vidShort: "影片",
    imgShort: "圖片",
    wallpaperFallback: { id in "桌布 \(id)" },
    statusProcessing: "處理中",
    statusPendingReview: "等待管理員審核",
    statusPending: "等待中",
    subProcessing: "正在產生裝置適配版本",
    subPendingReview: "通常數小時內完成",
    subPending: "等待下一步處理",
    badgeProcessing: "處理",
    badgeReview: "審核",
    badgePending: "等待"
)

private let uploadJA = UploadStrings(
    headerKicker: "投稿 · Wallpaper Exchange",
    titleLead: "あなたの画面を",
    titleAccent: "シェアしよう。",
    intro: { n in "画像（JPG / PNG / HEIC、一度に最大 \(n) 枚）または動画 1 本（MP4 / MOV / WebM / MKV）をドロップしてください。1 ファイルあたり 200 MB まで。アップロードが審査を通過するごとに 1 コインがもらえます。" },
    reviewKicker: "管理者による審査",
    reviewBody: "すべての投稿は審査を経てから公開されます。ステータスはプロフィールで確認できます。動画はトランスコードのため少し時間がかかることがあります。",
    dropActive: "ここにドロップ",
    dropIdle: "ここに画像をドロップ",
    orWord: "または",
    pickFromComputer: "クリックしてコンピュータから選択",
    maxFilesChip: { n in "最大 \(n) ファイル" },
	videoMinimum: "動画 ≥ 1920 × 1080",
    addMore: { count, max in "さらに追加 · \(count) / \(max)" },
    queueLabel: { n in "キュー · \(n)" },
    doneCount: { n in "· \(n) 完了" },
    failedCount: { n in "· \(n) 失敗" },
    pendingLabel: "公開待ち",
    pendingBody: "処理中または管理者の審査待ちの壁紙です。各タイルに現在のステージが表示され、承認されると公開アーカイブに追加されます。",
    pendingLoadErrorTitle: "公開待ち一覧を読み込めませんでした",
    allDoneMessage: "完了しました。アップロードは審査待ちです。",
    readySummary: { pending, errors in
        errors > 0 ? "アップロード待ち \(pending) ファイル · \(errors) 件は再試行が必要" : "アップロード待ち \(pending) ファイル"
    },
    uploadingTitle: "アップロード中",
    retryFailed: "失敗分を再試行",
    uploadN: { n in "\(n) ファイルをアップロード →" },
    signedOutTitle: "ログインしてシェア",
    signedOutBody: "アップロードには Wallpaper Exchange アカウントが必要です。",
    signIn: "ログイン",
    maxFilesMessage: { n in "追加できるのは最大 \(n) ファイルです。" },
    oversizedSkipped: { n in "\(n) ファイルが 200 MB を超えていたためスキップしました。" },
    oneVideoAtATime: "動画は一度に 1 本だけドロップできます。",
    clearImagesFirst: "動画を追加する前に画像のキューを空にしてください。",
    onlyOneVideo: "1 回のアップロードに動画は 1 本までです。",
    clearVideoFirst: "画像を追加する前にキューの動画を削除してください。",
	checkingVideoResolution: "動画の解像度を確認中…",
	lowResolutionBlocked: "低解像度 · 1920 × 1080 以上が必要です",
	unreadableVideoResolution: "動画の解像度を読み取れませんでした",
    receivedOne: "アップロードを受け付けました。審査後に公開されます。",
    receivedMany: { n in "\(n) 件のアップロードを受け付けました。審査後に公開されます。" },
    resultSummary: { ok, failed in "成功 \(ok) 件、失敗 \(failed) 件。" },
    videoBadge: "動画",
    fileBadge: "ファイル",
    imageBadge: "画像",
    vidShort: "動画",
    imgShort: "画像",
    wallpaperFallback: { id in "壁紙 \(id)" },
    statusProcessing: "処理中",
    statusPendingReview: "管理者の審査待ち",
    statusPending: "待機中",
    subProcessing: "デバイス向けバリアントを生成中",
    subPendingReview: "通常は数時間以内",
    subPending: "次のステップを待っています",
    badgeProcessing: "処理",
    badgeReview: "審査",
    badgePending: "待機"
)

extension L10n {
    static var upload: UploadStrings {
        switch lang {
        case .en: uploadEN
        case .zhCN: uploadZhCN
        case .zhTW: uploadZhTW
        case .ja: uploadJA
        }
    }
}
