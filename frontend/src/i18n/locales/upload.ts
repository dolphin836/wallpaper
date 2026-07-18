// `upload` namespace — UploadPage (dropzone, queue, status bar, toasts).
// `en` is the source of truth; the other languages are typed against it so
// a missing or extra key fails `tsc`.
const en = {
  meta: {
    pageTitle: 'Upload',
  },
  header: {
    kicker: 'Contribute · Wallpaper Exchange',
    heading: "Share <0>what's on your screen.</0>",
    intro: 'Drop images (JPG / PNG / HEIC, up to {{maxFiles}} at a time) or a single video (MP4 / MOV / WebM / MKV). Each file capped at 200 MB. Every upload earns one coin once it clears review.',
  },
  notice: {
    kicker: 'Admin review',
    body: 'Everything goes through review before showing up publicly. You can see status on your profile — videos may take a minute longer because we transcode them.',
  },
  dropzone: {
    dropActive: 'Drop them here',
    dropIdle: 'Drop images here',
    orPick: 'or <0>click to pick from your computer</0>',
    upToFiles: 'Up to {{max}} files',
    addMore: 'Add more · {{current}} / {{max}}',
  },
  queue: {
    label: 'Queue · {{num}}',
    done: '{{num}} done',
    failed: '{{num}} failed',
    confirming: 'Waiting for server…',
    remove: 'Remove',
  },
  bar: {
    allDone: 'All set, redirecting to your profile…',
    readyOne: '1 file ready to upload',
    ready: '{{num}} files ready to upload',
    needRetry: '{{num}} need a retry',
    cancel: 'Cancel',
    uploading: 'Uploading',
    retryFailed: 'Retry failed',
    done: 'Done',
    uploadOne: 'Upload 1 file →',
    uploadMany: 'Upload {{num}} files →',
  },
  toast: {
    maxFiles: 'Maximum {{max}} files allowed',
    oversized: '{{num}} file(s) exceed 200MB and were skipped',
    oneVideoAtATime: "Drop one video at a time — combining files in a single batch isn't supported",
    clearImagesFirst: 'Clear the image batch before adding a video',
    onlyOneVideo: 'Only one video per upload — remove the current one first',
    clearVideoFirst: 'Clear the queued video before adding images',
    selectAtLeastOne: 'Please select at least one image',
    successOne: "Upload received — pending admin review. You'll see it in your profile once approved.",
    successMany: '{{num}} uploads received — pending admin review.',
    partialFail: '{{success}} succeeded, {{failed}} failed — retry the failed rows below.',
  },
  errors: {
    uploadFailed: 'Upload failed',
    network: 'Network error',
    timeout: 'Upload timeout',
    signInFirst: 'Please sign in first',
  },
};

const zhCN: typeof en = {
  meta: {
    pageTitle: '上传',
  },
  header: {
    kicker: '投稿 · Wallpaper Exchange',
    heading: '分享<0>你屏幕上的风景。</0>',
    intro: '拖入图片（JPG / PNG / HEIC，一次最多 {{maxFiles}} 张），或单个视频（MP4 / MOV / WebM / MKV）。单个文件上限 200 MB。每次上传通过审核后可赚 1 枚金币。',
  },
  notice: {
    kicker: '管理员审核',
    body: '所有内容都会先经过审核再公开展示。你可以在个人主页查看状态——视频需要转码，可能会多等一会儿。',
  },
  dropzone: {
    dropActive: '松手放到这里',
    dropIdle: '把图片拖到这里',
    orPick: '或者<0>点击从电脑中选择</0>',
    upToFiles: '最多 {{max}} 个文件',
    addMore: '继续添加 · {{current}} / {{max}}',
  },
  queue: {
    label: '队列 · {{num}}',
    done: '{{num}} 个完成',
    failed: '{{num}} 个失败',
    confirming: '等待服务器确认…',
    remove: '移除',
  },
  bar: {
    allDone: '全部完成，正在跳转到你的主页…',
    readyOne: '1 个文件待上传',
    ready: '{{num}} 个文件待上传',
    needRetry: '{{num}} 个需要重试',
    cancel: '取消',
    uploading: '上传中',
    retryFailed: '重试失败项',
    done: '完成',
    uploadOne: '上传 1 个文件 →',
    uploadMany: '上传 {{num}} 个文件 →',
  },
  toast: {
    maxFiles: '最多允许 {{max}} 个文件',
    oversized: '{{num}} 个文件超过 200MB，已被跳过',
    oneVideoAtATime: '一次只能拖入一个视频——不支持在同一批里混合文件',
    clearImagesFirst: '请先清空图片队列，再添加视频',
    onlyOneVideo: '每次只能上传一个视频——请先移除当前这个',
    clearVideoFirst: '请先清空排队中的视频，再添加图片',
    selectAtLeastOne: '请至少选择一张图片',
    successOne: '已收到上传，等待管理员审核。通过后即可在你的主页看到。',
    successMany: '已收到 {{num}} 个上传，等待管理员审核。',
    partialFail: '{{success}} 个成功，{{failed}} 个失败——请在下方重试失败的条目。',
  },
  errors: {
    uploadFailed: '上传失败',
    network: '网络错误',
    timeout: '上传超时',
    signInFirst: '请先登录',
  },
};

const zhTW: typeof en = {
  meta: {
    pageTitle: '上傳',
  },
  header: {
    kicker: '投稿 · Wallpaper Exchange',
    heading: '分享<0>你螢幕上的風景。</0>',
    intro: '拖入圖片（JPG / PNG / HEIC，一次最多 {{maxFiles}} 張），或單支影片（MP4 / MOV / WebM / MKV）。單一檔案上限 200 MB。每次上傳通過審核後可賺 1 枚金幣。',
  },
  notice: {
    kicker: '管理員審核',
    body: '所有內容都會先經過審核再公開顯示。你可以在個人主頁查看狀態——影片需要轉檔，可能會多等一下。',
  },
  dropzone: {
    dropActive: '鬆手放到這裡',
    dropIdle: '把圖片拖到這裡',
    orPick: '或者<0>點擊從電腦中選擇</0>',
    upToFiles: '最多 {{max}} 個檔案',
    addMore: '繼續加入 · {{current}} / {{max}}',
  },
  queue: {
    label: '佇列 · {{num}}',
    done: '{{num}} 個完成',
    failed: '{{num}} 個失敗',
    confirming: '等待伺服器確認…',
    remove: '移除',
  },
  bar: {
    allDone: '全部完成，正在前往你的主頁…',
    readyOne: '1 個檔案待上傳',
    ready: '{{num}} 個檔案待上傳',
    needRetry: '{{num}} 個需要重試',
    cancel: '取消',
    uploading: '上傳中',
    retryFailed: '重試失敗項',
    done: '完成',
    uploadOne: '上傳 1 個檔案 →',
    uploadMany: '上傳 {{num}} 個檔案 →',
  },
  toast: {
    maxFiles: '最多允許 {{max}} 個檔案',
    oversized: '{{num}} 個檔案超過 200MB，已略過',
    oneVideoAtATime: '一次只能拖入一支影片——不支援在同一批裡混合檔案',
    clearImagesFirst: '請先清空圖片佇列，再加入影片',
    onlyOneVideo: '每次只能上傳一支影片——請先移除目前這支',
    clearVideoFirst: '請先清空排隊中的影片，再加入圖片',
    selectAtLeastOne: '請至少選擇一張圖片',
    successOne: '已收到上傳，等待管理員審核。通過後就能在你的主頁看到。',
    successMany: '已收到 {{num}} 個上傳，等待管理員審核。',
    partialFail: '{{success}} 個成功，{{failed}} 個失敗——請在下方重試失敗的項目。',
  },
  errors: {
    uploadFailed: '上傳失敗',
    network: '網路錯誤',
    timeout: '上傳逾時',
    signInFirst: '請先登入',
  },
};

const ja: typeof en = {
  meta: {
    pageTitle: 'アップロード',
  },
  header: {
    kicker: '投稿 · Wallpaper Exchange',
    heading: 'いま画面にあるものを、<0>そのままシェア。</0>',
    intro: '画像（JPG / PNG / HEIC、一度に最大 {{maxFiles}} 枚）または動画 1 本（MP4 / MOV / WebM / MKV）をドロップ。1 ファイルの上限は 200 MB。アップロードは審査を通過するごとにコインを 1 枚獲得できます。',
  },
  notice: {
    kicker: '管理者による審査',
    body: 'すべてのコンテンツは審査を経てから公開されます。ステータスはプロフィールで確認できます。動画はトランスコードのため少し時間がかかることがあります。',
  },
  dropzone: {
    dropActive: 'ここにドロップ',
    dropIdle: 'ここに画像をドロップ',
    orPick: 'または<0>クリックしてパソコンから選択</0>',
    upToFiles: '最大 {{max}} ファイル',
    addMore: 'さらに追加 · {{current}} / {{max}}',
  },
  queue: {
    label: 'キュー · {{num}}',
    done: '{{num}} 件完了',
    failed: '{{num}} 件失敗',
    confirming: 'サーバーの確認待ち…',
    remove: '削除',
  },
  bar: {
    allDone: '完了です。プロフィールへ移動します…',
    readyOne: 'アップロード待ち 1 ファイル',
    ready: 'アップロード待ち {{num}} ファイル',
    needRetry: '{{num}} 件は再試行が必要',
    cancel: 'キャンセル',
    uploading: 'アップロード中',
    retryFailed: '失敗分を再試行',
    done: '完了',
    uploadOne: '1 ファイルをアップロード →',
    uploadMany: '{{num}} ファイルをアップロード →',
  },
  toast: {
    maxFiles: 'ファイルは最大 {{max}} 個までです',
    oversized: '{{num}} 個のファイルが 200MB を超えていたためスキップしました',
    oneVideoAtATime: '動画は 1 本ずつドロップしてください — 同じバッチでの混在には対応していません',
    clearImagesFirst: '動画を追加する前に画像のバッチをクリアしてください',
    onlyOneVideo: '1 回のアップロードにつき動画は 1 本まで — 先に現在の動画を削除してください',
    clearVideoFirst: '画像を追加する前にキュー内の動画をクリアしてください',
    selectAtLeastOne: '画像を 1 枚以上選択してください',
    successOne: 'アップロードを受け付けました — 管理者の審査待ちです。承認されるとプロフィールに表示されます。',
    successMany: '{{num}} 件のアップロードを受け付けました — 管理者の審査待ちです。',
    partialFail: '成功 {{success}} 件、失敗 {{failed}} 件 — 下の失敗した項目を再試行してください。',
  },
  errors: {
    uploadFailed: 'アップロードに失敗しました',
    network: 'ネットワークエラー',
    timeout: 'アップロードがタイムアウトしました',
    signInFirst: '先にログインしてください',
  },
};

export default { en, 'zh-CN': zhCN, 'zh-TW': zhTW, ja } as const;
