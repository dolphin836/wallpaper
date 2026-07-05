<!-- [skill: go-team-standards · 设计文档] Wallpaper Exchange 跨端 UI 设计规范（Mac + Web） -->

# Wallpaper Exchange UI 设计规范

> 版本 v1.0 · 2026-07-05
> 适用端：macOS 客户端（`macos/`）、Web（`frontend/`）；iOS / Android / Windows 后续对齐。
> 本文取代 `docs/DESIGN.md` 中与玻璃材质冲突的旧结论（旧文档"避免装饰性玻璃"的方向已被 Liquid Glass 设计语言取代）。
> Mac 端权威实现：`macos/.../Views/Main/GlassKit.swift`；Web 端权威实现：`frontend/src/index.css` 令牌区。
> **修改规范 = 修改这两个文件 + 本文档，三者必须同步。**

---

## 0. 现状审计结论（2026-07-05，Mac 端 Main 视图层）

本规范整理自当前实现，以下是需要收敛的偏差，作为后续整改清单：

| 维度 | 现状 | 问题 |
|---|---|---|
| 圆角 | 17 种取值（3–48） | 无序。规范收敛为 6 档（§4） |
| 字号 | 25 种取值（8–86） | 无序。规范收敛为类型阶梯（§3） |
| 颜色 | 23 处 `Color(red:)` 硬编码绕过令牌 | 应全部改为语义令牌（§2）；已知点：ActionDot 的 like/favorite/download 色、chip 墨色、HoverTip 底色 |
| 两端色相 | Web paper 冷灰（oklch 色相 230）；Mac paper 暖灰 | **两端不一致**，见建议 §9.1 |
| 遗留令牌 | Web `--color-ws-purple*` 系列仍存在 | 旧版遗留，应删除（§9.2） |
| 字体 | Web 用 Newsreader/Geist/JetBrains Mono；Mac 用系统 serif/sans/mono | 可接受的降级（§3 字族策略），但需固定字重映射 |
| 组件 | Mac 已有 GlassKit；Web 仍是散落的 CSS 类 | Web 需按 §6 落一套同名组件 |

---

## 1. 设计原则

1. **内容优先**：壁纸图片是唯一主角。Chrome（导航、工具栏、按钮）负责取景和响应，不与内容争夺注意力。
2. **玻璃只用于悬浮层**：Liquid Glass 材质仅用于漂浮在内容之上的导航/操作层（顶部导航、工具栏、悬浮按钮、下拉面板）。**内容层（列表、卡片、正文）禁止使用玻璃**，禁止玻璃叠玻璃。
3. **安静的编辑部气质**：纸面 + 墨色 + 暖橙点缀 + 发丝线。克制的动效，无装饰性噪音。
4. **双色调体系**：所有悬浮组件必须同时定义 `light`（纸面页面上）与 `dark`（照片背景上）两种色调，由容器背景决定，不允许第三种。
5. **跨端可实现**：规范中的每一项都必须在 SwiftUI 与 CSS 都能实现。macOS 26 的原生 `glassEffect` 视为渐进增强，规范定义的是**两端都能达到的基线**（§5）。

---

## 2. 颜色令牌

### 2.1 基础语义色（浅色 / 深色模式）

权威定义用 OKLCH（Web 直接用；Mac 换算为 sRGB 常量）。**色相统一为暖中性（色相 ≈ 75–90），见 §9.1 决议。**

| 令牌 | 角色 | 浅色 | 深色 |
|---|---|---|---|
| `paper` | 主背景，永不纯白 | `oklch(97.5% 0.006 85)` | `oklch(16% 0.010 240)` |
| `paper-2` | 工具条、chip、次级面板、骨架屏 | `oklch(95.2% 0.008 85)` | `oklch(20% 0.010 240)` |
| `paper-3` | 更深的占位、卡片底 | `oklch(92% 0.010 85)` | `oklch(24% 0.011 240)` |
| `hair` | 1px 边框与分割线 | `oklch(86% 0.010 85)` | `oklch(28% 0.010 240)` |
| `ink` | 主文字、选中态 | `oklch(18% 0.010 85)` | `oklch(95% 0.008 240)` |
| `ink-2` | 次级文字、未选中控件 | `oklch(28% 0.010 85)` | `oklch(82% 0.010 240)` |
| `muted` | 元数据、计数、禁用 | `oklch(52% 0.010 85)` | `oklch(62% 0.010 240)` |
| `accent` | 兑换/上传/金币/主操作 | `oklch(64% 0.21 42)` | `oklch(68% 0.22 42)` |
| `accent-soft` | 进度轨道、选中软底 | `oklch(94% 0.05 60)` | `oklch(28% 0.08 42)` |
| `warn` | 警告 | `oklch(58% 0.12 80)` | `oklch(75% 0.13 85)` |

### 2.2 状态色（两端一致，不随模式变化）

| 令牌 | 值 | 用途 |
|---|---|---|
| `like` | `#E0463A` | 点赞激活态（仅此用途） |
| `favorite` | `#D8A23A` | 收藏激活态 |
| `downloaded` | `#4A8A5A` | 已下载/成功态 |

### 2.3 玻璃色调（GlassTone，§5 材质配套）

| 令牌 | light 色调 | dark 色调 |
|---|---|---|
| `glass-tint` | `paper @ 28%` | `black @ 40–50%` |
| `glass-fg` | `ink` / `ink-2` / `muted` | `white` / `white 85%` / `white 55%` |
| `glass-hover` | `ink @ 8%` | `white @ 12%` |
| `glass-active` | `accent @ 13%` | `white @ 18%` |
| `glass-divider` | `ink @ 16%` | `white @ 22%` |

### 2.4 禁止

- 禁止在业务代码中出现裸 RGB/HEX（Mac 的 `Color(red:)`、Web 的 `#xxx`），一律走令牌。
- 禁止紫色/靛蓝/纯灰度出现在产品界面（Web 管理后台的运营灰除外）。
- `accent` 只用于表达"主操作/交易语义"，禁止当装饰色铺开（防"芭比机"效应）。

---

## 3. 字体

### 3.1 字族（跨端策略：Web 加载字体，Mac 用系统同类降级）

| 角色 | Web | Mac | 用途边界 |
|---|---|---|---|
| Display（衬线） | Newsreader | `system(design: .serif)` | 仅页面大标题、板块标题 |
| UI（无衬线） | Geist | `system` (SF Pro) | 按钮、标签、正文、表单、导航——一切控件 |
| Meta（等宽） | JetBrains Mono | `system(design: .monospaced)` | 分辨率、尺寸、状态、kicker 等技术元数据，通常大写+字距 |

**禁止**：Display 字体出现在控件/导航/表单里；等宽字体用于正文。

### 3.2 类型阶梯（收敛后的唯一合法字号表）

| 级别 | 字号 | 字重 | 角色 |
|---|---|---|---|
| `display-xl` | 34 | semibold serif | 页面主标题（如"本周精选"） |
| `display-lg` | 32 | regular serif | 板块标题 |
| `display-md` | 24 | semibold serif | 弹层标题 |
| `title` | 16 | semibold sans | 卡片/工具栏标题 |
| `body` | 13.5 | regular sans | 正文、导航项 |
| `label` | 12.5 | medium sans | 按钮、chip、表单标签 |
| `caption` | 11.5 | medium sans | 辅助说明、紧凑控件 |
| `meta` | 10–11 | medium mono +tracking | kicker、徽标、技术元数据 |

超出此表的字号视为违规；确有需要先改表再用。

---

## 4. 间距、圆角、尺寸、边框

### 4.1 间距（4pt 网格）

`4 / 8 / 12 / 16 / 24 / 32 / 40 / 56 / 72`

- **页面侧边距固定 40**，内容全宽自适应（禁止居中限宽的"版心"布局，全屏时内容随窗口生长）。
- 卡片网格间距：紧凑网格 16，大卡网格 28。
- 板块之间垂直间距：56–72。

### 4.2 圆角（6 档）

| 档 | 值 | 用途 |
|---|---|---|
| `r-xs` | 6 | 小徽标、输入框内元素 |
| `r-sm` | 10 | 紧凑媒体卡、菜单 |
| `r-md` | 14 | 常规媒体卡、表单控件 |
| `r-lg` | 18 | 大卡（首页周精选卡）、下拉/信息面板 |
| `r-xl` | 24 | 弹层外壳、大型面板 |
| `r-full` | 胶囊/圆 | 按钮、chip、分段控件、导航条 |

### 4.3 控件尺寸（高度）

| 尺寸 | 高度 | 用途 |
|---|---|---|
| `ctl-xs` | 26 | 紧凑分段项、行内 chip |
| `ctl-sm` | 30–32 | 次级按钮、菜单触发器 |
| `ctl-md` | 34 | 导航分段项、标准按钮 |
| `ctl-lg` | 38 | 悬浮圆钮（返回/信息）、主操作按钮 |

图标尺寸随控件：`ctl` 高度 × 0.38–0.43，全部使用 semibold 字重的线性图标。

### 4.4 边框与分割线

- 一律 1px（发丝线），颜色用 `hair`（内容层）或 `glass-divider`（玻璃内部）。
- 玻璃描边用**渐变发丝线**（顶部亮 → 底部淡），见 §5 光影层。
- 禁止 2px 及以上装饰性边框。

---

## 5. 玻璃材质（跨端定义）

材质分三层，两端各自实现，视觉结果一致：

| 层 | 定义 | Mac 实现 | Web 实现 |
|---|---|---|---|
| ① 材质底 | 背景模糊 + 色调 | macOS 26：`glassEffect(.regular)`（自带折射）；26 以下：`ultraThinMaterial` + 色调 | `backdrop-filter: blur(24px) saturate(1.4)` + 色调背景；进阶折射可用 SVG 位移贴图（参考 Aave 方案），作为渐进增强 |
| ② 光影层 | 45° 高光 + 顶部亮边 + 底部暗反边 + 冷暖色散细线 | `GlassLightingOverlay` | 两层 `box-shadow: inset` + 伪元素渐变描边 |
| ③ 投影 | 双层：接触影（radius 3, y2, 18%）+ 环境影（radius 18, y8, 20%） | `GlassShadow.floating` | 两段 `box-shadow` |

规则：

- 水珠选中态（分段控件的滑动透镜）：位置动画用 spring（响应 0.42 / 阻尼 0.68，带过冲）；Web 用 `transition` + 自定义 spring 曲线近似。
- 悬停：控件弹性放大 1.05–1.12；按压：压缩到 0.90 后弹回。
- 可达性：必须响应系统"降低透明度/增强对比度/减弱动态效果"（Mac 自动；Web 用 `prefers-reduced-motion` / `prefers-contrast`）。
- **禁止**：玻璃用于滚动内容、整页背景、卡片本体；玻璃叠玻璃（选中水珠是唯一例外，且必须在同一容器内）。

---

## 6. 基础组件（两端同名对齐）

Mac 权威实现在 `GlassKit.swift`；Web 需按同一 API 语义落地（React 组件或 CSS 类）。

| 组件 | 规格摘要 |
|---|---|
| `GlassPill` | 胶囊容器，内边距 5，内部元素间距 2；材质三层全套 |
| `GlassSegmented` | 分段控件，常规（34）/紧凑（26）两号；水珠选中态；可选 `fullWidth`（各段均分整行）；段支持 icon + label + badge |
| `GlassChip` | 筛选标签：静止=轻玻璃，激活=实心 ink 胶囊；行内出现，不带悬浮投影 |
| `GlassIconButton` | 玻璃容器内的图标钮（28），扁平色块高亮，hover 弹出下方 HoverTip |
| `GlassCircleButton` | 独立悬浮圆钮（38），自带玻璃；`prominent` 变体=纸白底+accent 描边，用于照片上的主操作 |
| `GlassCapsuleButton` | 文字胶囊按钮，三风格：`glass`（次级）/ `paper`（照片上主操作）/ `accent`（品牌 CTA）；每屏 accent 不超过 1 个 |
| `glassPanel` | 圆角 18–24 玻璃面板：下拉、信息卡、选择器 |
| `glassMenuLabel` | 下拉菜单触发器外观（高 32 胶囊） |
| `HoverTip` | 深色小胶囊提示，出现在控件下方 8pt，立即显示 |
| `GlassPillDivider` | 玻璃容器内 1×20 分隔线 |

组件外的临时拼样式（ad-hoc `background(Capsule()...)`）视为违规；组件能力不够时先扩组件。

---

## 7. 动效

| 场景 | 参数 | Web 等价 |
|---|---|---|
| hover 进入/离开 | spring(0.32, 0.6) | `transition: 240ms cubic-bezier(0.34, 1.56, 0.64, 1)` |
| 按压反馈 | spring(0.26, 0.55)，scale 0.90 | 同上，180ms |
| 选中水珠滑动 | spring(0.42, 0.68) | 320ms 同曲线 |
| 面板出现/消失 | easeOut 0.16 + opacity/move | `160ms var(--ease-out-quart)` |
| 页面背景色过渡 | easeOut 0.42 | `420ms` |

原则：动效表达物理反馈（挤压、回弹、滑动），不做纯装饰动画；玻璃在静止状态下必须"歇着"（省电与性能）。

---

## 8. 图标与图片

- Mac 用 SF Symbols；**Web 禁止依赖 SF Symbols**（授权限制），用 Lucide 作为等价字形库，两端按语义对照（如 `chevron.left` ↔ `chevron-left`、`tray.and.arrow.up` ↔ `upload`）。新增图标必须两端都能找到等价字形才可采用。
- 图片加载顺序统一为：**默认底（mesh/paper）→ 主色块 → 缩略图（模糊）→ 原图**，配加载扫光。
- 卡片图片一律 `cover` 裁剪 + 固定纵横比（媒体卡 3:2 / 4:5 / 16:10，首页周精选卡黄金比 1.618:1）。

---

## 9. 对项目的规范建议（决议项）

### 9.1 两端色相统一（高优先级）

现状：Web 纸面是**冷灰**（OKLCH 色相 230），Mac 纸面是**暖灰**。两端"同一产品"的观感被破坏。
建议：**统一到暖中性**（本文 §2.1 的值）。理由：产品气质是"编辑部纸面"，暖纸 + 暖橙 accent 是既有品牌资产；Mac 端大面积玻璃在暖色壁纸上表现也更和谐。改动落点：`frontend/src/index.css` 的 `--color-paper*` / `--color-hair*` / `--color-ink*` 系列换色相即可，布局零改动。

### 9.2 清理 Web 遗留令牌（高优先级）

`--color-ws-purple*`、`--color-ws-dark-*` 系列是旧版遗留，与 §2.4 冲突，删除并替换残余引用。

### 9.3 玻璃语言引入 Web（中优先级）

按 §5 的三层定义在 Web 落地基线版（backdrop-filter + 光影 + 双影），首批应用于顶部导航与壁纸详情工具栏，与 Mac 端呼应。SVG 位移折射作为二期增强，且只在 Chromium 上启用（Safari 用基线版兜底）。

### 9.4 Mac 端整改清单（随迭代逐步做）

1. 23 处 `Color(red:)` 硬编码 → 补充 `like`/`favorite`/`downloaded`/`chipInk`/`tipSurface` 令牌后替换；
2. 圆角/字号按 §3/§4 收敛（重点：DetailPage、UploadView 内的散值）；
3. `SettingsView.swift` 死代码删除；
4. Popover（菜单栏弹窗）视觉仍是 v1 语言，按 GlassKit 重制或保持独立但对齐令牌。

### 9.5 风格上的两条边界（防跑偏）

- 玻璃密度上限：一屏同时可见的玻璃表面 ≤ 3 块（导航条、返回钮、一块面板）。超过说明信息架构有问题，不是样式问题。
- 照片上的文字必须有保底可读性手段（刮渣层/局部渐变/白字+投影三选一），禁止裸文字压图。

---

## 10. 落地与维护

- 新页面/新组件先查本文档；规范没覆盖的样式，先提案改文档，再写代码。
- 变更流程：改 `GlassKit.swift`（Mac）+ `index.css` 令牌（Web）+ 本文档，一次提交同步。
- 发版前跑 `macos/uitest/run-uitest.sh` 冒烟 + 人工翻一遍截图产物确认视觉。
