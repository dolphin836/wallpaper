# Show HN 发布草稿

> **使用时机**：建议跟 Mac 客户端 1.3（或某个有"news value"的里程碑版本）一起发，单纯发"我做了个壁纸站"在 HN 噪音里会被淹没。
>
> **发布时段**：UTC 08:00 – 14:00（美东早 4–10 点 / 美西早 1–7 点），HN 这个窗口流量最高，但首页竞争最激烈。如果想 underrated 的安静窗口，UTC 18:00 – 22:00 也不错。
>
> **重要**：发布后头 1 小时是关键 —— Show HN 的 ranking 取决于"前 1 小时 upvote / 评论速度"。准备好把链接发给几个朋友请他们看一眼（**不是机器人，不要互投**）。

---

## Title（≤ 80 chars）

```
Show HN: Wallpaper Exchange – a community for macOS dynamic wallpapers
```

候选备选：
- `Show HN: I built a wallpaper site that preserves macOS HEIC dynamic metadata`
- `Show HN: WallpaperExchange – first-class macOS solar/h24 wallpaper support`

## URL

```
https://wallpaperexchange.com
```

## Body（HN 帖子正文 —— 不要 markdown 渲染，纯文本即可）

```
Hey HN — I made WallpaperExchange because the existing wallpaper sites
treat macOS dynamic wallpapers as second-class citizens. Most strip the
"apple_desktop" HEIC metadata on upload, so the file you download looks
like a static image to your Mac.

What's different about this one:

1. Preserves HEIC apple_desktop metadata so dynamic wallpapers keep
   their solar/h24/appearance behavior. The backend reads the embedded
   plist directly and tags the wallpaper with its dynamic type.

2. Extracts each frame of a dynamic wallpaper as a WebP preview, so you
   can see how the wallpaper looks "from morning to night" without
   downloading it.

3. Variant-aware downloads. Each wallpaper gets multiple WebP variants
   at common screen sizes. The Mac client sends your display dimensions
   and the server returns the smallest variant that still covers your
   screen — small download, sharp result.

4. A menu-bar Mac app (no Dock icon, no main window) — browse,
   favorite, apply with one click. Supports per-display wallpapers.

5. Every ISO week, 10 hand-picked + an editor-curated themed collection.
   Past weeks are permanently archived. No wallpaper is featured twice.

6. AI auto-tagging via Claude vision — search and "related"
   recommendations actually work.

Stack: Go + PostgreSQL + MinIO + Kafka workers + React 19 SPA + SwiftPM
menu-bar app. No ads, no tracking, no third-party data sharing. Free.

Open to feedback on the dynamic-wallpaper handling especially — there's
a long tail of edge cases (HDR variants, older Mojave-era files, etc.)
where I'd love to know what other Mac people have run into.

Web: https://wallpaperexchange.com
Mac client: https://wallpaperexchange.com/download/mac
```

## 准备好回复的常见 HN 提问

**"Why not just use [Unsplash / Pexels]?"**
> Unsplash and Pexels are photography-first and don't preserve `apple_desktop` HEIC metadata — try downloading any HEIC dynamic wallpaper from them, the timestamps are gone. Wallpaper Exchange is built specifically around that file format.

**"How do you handle copyright?"**
> Public uploads only; users assert they have the right to share what they upload. Reports go straight to a moderation queue. Pre-launch we seeded with public-domain + Creative Commons + Mojave-era Apple-distributed wallpapers (legal grey area but historic preservation).

**"Open source?"**
> Mac client will be open-sourced once the API is stable (currently 0.9.x, semver matters). Backend is self-hosted and not yet open-sourced — happy to share the architecture in detail though.

**"Any plans for iOS?"**
> Yes, this year. Mainly for iPhone / iPad Live wallpaper discovery + download. Same per-display variant logic.

**"How is it sustainable without ads?"**
> Cheap VPS + R2/MinIO storage. The site is small enough that hosting costs less than a takeout meal per month. If it grows large enough to need real money, donation-based first, never ads.

---

## 备注

Show HN 的 guideline (https://news.ycombinator.com/showhn.html) 要求：
- 必须是你做的东西
- URL 必须能让人直接看到/玩到（我们已经满足）
- 不能"showcasing video" 取代实际产品
- 标题不要写 "Show HN: I made..." 全大写 → 我们用的格式合规

**永远不要刷票**。HN 的反作弊系统看得很严，刷票 = 沉帖 + 账号 shadowban。
