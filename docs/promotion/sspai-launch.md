# 想要更好的 macOS 动态壁纸？我做了一个开放的社区

> 本文准备发布到少数派 sspai.com，作者自述视角。

我从 macOS Mojave 出来 Dynamic Desktop 那年开始用动态壁纸。那种白天到夜晚自动变化的氛围感，比静态壁纸高了不止一个档次。但用了几年我发现一件挺反直觉的事：**整个互联网上，几乎没有一个像样的地方让你能系统性地找到、下载、分享 macOS 动态壁纸**。

24KPixel 早就停更，Dynamic Wallpaper Club 时灵时不灵，Reddit 上的 `r/macOSWallpapers` 翻得手酸也只能看到那几张老物件。最离谱的是，很多论坛贴的 HEIC 文件根本没保留 solar 元数据 —— 下载下来 Mac 当成静态图处理，整个动态体验丢了。

我做了 [WallpaperExchange](https://wallpaperexchange.com) 就是想解决这个问题。这是一个**把 macOS 动态壁纸放在第一位的壁纸社区**，同时也兼顾常规高清壁纸。

## 它做对了的几件事

### 1. 正确处理 HEIC 动态壁纸的元数据

苹果在 HEIC 的 metadata 里塞了一段 base64 编码的 plist，定义了"光线变化时刻"或"appearance 模式"。绝大多数图床上传 HEIC 时会把这段 metadata 抹掉，结果你下载下来，Mac 把它当成普通的单帧 HEIC，自动切换没了。

WallpaperExchange 直接读取原始 HEIC，自动识别三种动态类型：

- **Solar**（基于经纬度 + 时刻的太阳位置切换）
- **H24**（24 小时按时间点切换）
- **Appearance**（仅深色 / 浅色模式两张图）

你上传一个动态 HEIC，它会自动检测、保留所有元数据、并在详情页打上对应的标签。后台还会用 `heif-convert` 把里面的每一帧拆出来生成 WebP 预览 —— 你不下载就能看清这张动态壁纸"从早到晚"长什么样。

### 2. 自动按你的屏幕给你最合适的尺寸

这是这个站点最让我自豪的小细节。

传统壁纸站给你的"4K 高清"通常是一张 5120×2880 的原图，不管你是 27 寸 5K iMac、14 寸 MacBook Pro 还是 iPhone，都给你同一张。手机用户下几 MB 浪费流量，5K 屏用户拿到一张满足不了 retina 的图。

WallpaperExchange 给每张壁纸**自动生成多个尺寸变体**（按主流设备的 native 分辨率），Mac 客户端下载时会把你屏幕的 width × height 发给后端，后端挑一张**最小的、能覆盖你屏幕的**变体回传给你。下载小、显示清，两边都满足。

变体编码用的是 WebP q=80，比 JPEG q=85 还小 25–30%，**视觉上看不出区别**。这件事对存储成本和移动端流量都有显著好处。

### 3. 一个安静的 Mac 客户端

我做了一个住在 menu bar 上的小图标应用（macOS 14+，SwiftPM 写的），点开是一个 popover：浏览、收藏、下载、一键设为壁纸。**没有 Dock 图标、没有主窗口、不打扰**。

下载的壁纸放在 `~/Library/Application Support/WallpaperExchange/Downloads/`，你可以随时备份、迁移。支持多屏 —— 每个屏幕可以单独设一张。

下载入口：[wallpaperexchange.com/download/mac](https://wallpaperexchange.com/download/mac)

### 4. 每周编辑精选 + AI 主题合集

很多壁纸站的"热门"算法只看下载数，越流行越靠前，结果首页永远是那几张。

我做了一个 **Weekly Drop** 机制：每周（按 ISO 周）从近期上传里挑出 10 张做精选；与此同时，让 Anthropic 的 Claude 看完一个候选池后挑出一个**有共同主题的子集**，组成一个有名字的合集。比如本周（2026 W21）是 *Moody Mountain Solitude*（雾气山脉孤独感）—— 不是随机挑十张山，而是确实有共同的氛围、构图、色调。

每张壁纸**只会被精选一次**，所以你每周看到的都是新的。历史精选都归档在 [/weekly-picks](https://wallpaperexchange.com/weekly-picks)，可以慢慢翻。

### 5. AI 自动打标 + 质量审核

新上传的壁纸会被 Claude 看一眼，自动归类（自然 / 抽象 / 二次元 / 等），并生成 5–8 个描述性 tag —— 用户不需要自己写。低质内容（模糊、噪点严重、明显 AI 残影）会被标记进审核队列。

这些都是后台自动跑的，对用户透明 —— 你只会感觉到搜索、相关推荐变更准了。

## 关于隐私和开放

WallpaperExchange 没有广告、不向第三方分享数据、不需要注册就能浏览和下载。

注册账号的好处只是能点赞、收藏、自己上传 —— **服务器只在你点过的内容上做相关性推荐，对外不输出任何画像**。我自己平时也用它，把它当作我私人的壁纸图书馆，只是顺便开放给了所有人。

后端 Go + PostgreSQL + MinIO，前端 React + TailwindCSS v4，全自托管，不依赖任何 SaaS 第三方。

## 你能怎么参与

**直接用** —— 浏览：[wallpaperexchange.com](https://wallpaperexchange.com)；Mac 客户端：[/download/mac](https://wallpaperexchange.com/download/mac)

**上传你的收藏** —— 特别欢迎那种"老但好"的动态壁纸（macOS Mojave / Catalina 时代的官方 + 民间制作）。注册后到 [/upload](https://wallpaperexchange.com/upload) 拖拽即可，上传成功一张拿 1 个 coin（暂时是纪念意义，后面会有兑换计划）。

**发现重复 / 低质内容** —— 详情页有 Report 按钮，反馈直接进我审核队列。

## 未来一段时间的打算

- **iOS 客户端**（今年内，主要解决 iPhone / iPad Live 壁纸的发现 + 下载）
- **更细的搜索**（按色调、风格、设备适配，目前 v1 还没上）
- **用户主题策划**（让真人也能创建合集，不只是 AI）
- **更多动态格式支持**（包括 Live Photo 风格）

如果你也喜欢动态壁纸，或者纯粹想要一个安静、克制、长期维护的壁纸去处，欢迎来玩。看到喜欢的觉得"哎，这张我有更高清的"，记得上传分享一下。

—

封面图：本周精选的 [Misty Frosted Pine Forest on Mountain Slopes](https://wallpaperexchange.com/wallpaper/item-0ad08733)。
