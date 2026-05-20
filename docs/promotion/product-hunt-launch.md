# Product Hunt 发布草稿

> **使用时机**：建议跟 Mac 客户端 1.3 同步发，"new Mac app + new platform" 双重 hook 更容易拿到 PH 首页位置。
>
> **发布时间**：太平洋时间 **周二 / 周三 00:01 AM PT** 最佳。PH 的 ranking 按"发布当天 24h 内的票数"算，凌晨发能让你有完整 24h 攒票。
>
> **重要**：发布前一天找 1–2 个 PH 上有信誉的"hunter"（粉丝多 + 历史发产品多的）帮你"hunt"会显著提高曝光。可以去 PH 探索一下"Top Hunters of the Week"。

---

## 基本字段

**Name**: `Wallpaper Exchange`

**Tagline** (60 chars max — 这是首页卡片上你能看到的唯一一行):
```
A wallpaper community made for macOS dynamic wallpapers
```
候选：
- `Open wallpaper community with first-class macOS dynamic support`（59 chars）
- `Discover, share & auto-apply macOS dynamic wallpapers, beautifully`（65 — 太长）
- `Where macOS dynamic wallpapers live: discover, share, auto-apply`（63 — 太长）
- ✅ 选 `A wallpaper community made for macOS dynamic wallpapers`（55 chars）

**Description** (260 chars max — 卡片展开时显示):
```
The first wallpaper platform that treats macOS dynamic wallpapers as first-class — preserves HEIC metadata, extracts frames, picks per-display variants automatically. Plus a clean menu-bar Mac app, weekly AI-curated themes, and no ads ever.
```
(255 chars — 在限额内)

**Topic / Categories**: Design Tools, macOS Apps, Productivity

**Pricing**: Free

---

## Maker's first comment（PH 第一条评论一定要 maker 自己发，最有 ranking 权重）

```
Hey Product Hunt 👋

I'm the maker of Wallpaper Exchange. Three years ago I got obsessed with
macOS dynamic wallpapers — the ones that change with sunrise/sunset or
across 24 hours — and went looking for a community that catered to them.

I couldn't find one. So I built it.

What I think is genuinely new here:

🌅  **HEIC metadata preservation** — most image hosts strip the
    `apple_desktop` plist on upload, breaking the dynamic behavior.
    We read it, tag it, keep it. The wallpaper you download actually
    works on your Mac.

🖥️  **Variant-aware downloads** — the Mac client sends your screen
    resolution; the server picks the smallest variant that still
    covers your display. Less bandwidth, sharper result, automatic.

🧙  **AI-curated weekly drops** — every Friday, 10 hand-picked
    wallpapers + a Claude-curated themed collection. Each wallpaper
    is featured at most once, ever. No "same 10 trending images"
    forever.

🍎  **A native macOS menu-bar app** — no Dock icon, no main window.
    Browse, favorite, apply with a click. Multi-monitor support.

🔒  **No ads, no tracking, no third-party data sharing.**
    Free, self-hosted, will never enshittify.

The whole thing is built on Go + Postgres + MinIO + Kafka, with a React
SPA front and a SwiftPM menu-bar app. Small enough that hosting costs
less than a takeout meal a month — if it grows, donations first, never
ads.

I'd especially love feedback on the dynamic-wallpaper handling — if
you're a Mac dynamic-wallpaper enthusiast, please throw your weirdest
HEIC files at it and tell me what breaks.

Try it:
🌐 https://wallpaperexchange.com
🍎 https://wallpaperexchange.com/download/mac

Cheers,
— [your handle]
```

---

## 缩略截图建议（PH 鼓励 4–6 张）

1. **Hero shot** — Weekly Drop slate on the home page（最强视觉）
2. **Dynamic wallpaper detail page** — 显示 frame timeline，证明 HEIC metadata 真的活着
3. **Mac menu-bar popover** — 证明这不是又一个网页 demo
4. **Multi-resolution variants UI** — 显示 device 列表
5. **Weekly archive page** — 体现"每周新东西"的持续运营感
6. **AI tag chips on a wallpaper** — 体现 polish

> 用 4K 屏截图，PH 要求 1270×760 以上，越锐越好。

---

## Gallery 视频（可选但强烈推荐）

如果有 30 秒以内的产品 demo 视频，PH 排序权重比图片高一档。可以：
1. 启动 Mac 客户端 → 在 menu bar 出现
2. 点开 popover → 滑动 Weekly Drop
3. 点一张壁纸 → 一键设为桌面 → 桌面真的换了
4. 关掉 popover

整段无需配音，加点轻 BGM 即可。

---

## 上线后头 24h 任务

- [ ] **00:01 PT** 发帖
- [ ] 立刻发 maker comment（影响初期 ranking）
- [ ] 朋友/小社群通知（**不要**说"please upvote"，问"thoughts welcome"）
- [ ] 每 2-3 小时回复一次评论（PH 算法看回复频率）
- [ ] 同时间在 Show HN / Twitter / Mastodon / 小红书 同步发，引导外部流量到 PH 页面（PH 看 "external traffic to PH page"）
- [ ] 截图 PH 排名做存档（用于以后说"我们曾经 #X of the day"）

---

## 备注

Product Hunt 现在的反作弊比 5 年前严了很多。**严禁**：
- 同一个 IP 多账号投票
- 朋友圈群发 "please upvote"
- VPN 切到美国投票（PH 会判 location）

正常的"我做了个东西，欢迎来看"是 OK 的。
