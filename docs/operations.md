# 运维 / 操作文档

> 这份文档只记录**需要你亲手执行的事情**。代码自动跑的不在这里。
>
> 看一眼目录就能定位，每节都给可直接复制的命令。

## 目录

1. [日常 / 周度操作](#1-日常--周度操作)
2. [AI 壁纸生成流程](#2-ai-壁纸生成流程)
3. [壁纸质量审核（qcheck）](#3-壁纸质量审核qcheck)
4. [发版（macOS 客户端）](#4-发版macos-客户端)
5. [部署（后端 / 前端）](#5-部署后端--前端)
6. [内容运营（待手动发布）](#6-内容运营待手动发布)
7. [SEO / 搜索引擎索引](#7-seo--搜索引擎索引)
8. [基础设施 / 调试](#8-基础设施--调试)
9. [密钥 / API Key 速查](#9-密钥--api-key-速查)
10. [仍在等待外部审批](#10-仍在等待外部审批)
11. [紧急情况](#11-紧急情况)

---

## 1. 日常 / 周度操作

| 频率 | 事项 | 命令 |
|---|---|---|
| 每天（建议） | 看一眼 admin dashboard 的流量 + LLM 消费 | 浏览器开 [/admin](https://wallpaperexchange.com/admin) → "流量" / "总览" |
| 每周一次 | 手动创建一期每周推荐 / 首页推荐合集 | 浏览器开 [/admin/weekly-picks](https://wallpaperexchange.com/admin/weekly-picks) 和 [/admin/collections](https://wallpaperexchange.com/admin/collections) |
| 每 1-2 周 | 给新上传壁纸跑质量审核 | 见 [§3](#3-壁纸质量审核qcheck) |
| 临时 | AI 生成一张壁纸入站 | 见 [§2](#2-ai-壁纸生成流程) |

---

## 2. AI 壁纸生成流程

完整链路：**模糊想法 → Claude 扩写 → mini 预览 ($0.01) → 你看 → 满意 → 4K 出图 ($0.17) → 推送**

### 一次完整流程

```bash
# 步骤 1：生成预览（自动调 Claude 扩写 + 出 1024² mini 图，约 20 秒）
./scripts/wallpaper-gen.sh "极简北欧雾气山脉日出，柔和粉橙渐变天空"

# 输出会给你一个 id，比如 2026-05-21-035022-217e
# Preview.app 会自动打开图给你看

# 步骤 2a：满意 → 出 4K（约 60-120 秒，$0.17）
./scripts/wallpaper-gen.sh --finalize 2026-05-21-035022-217e

# 步骤 2b：不满意 → 丢弃
./scripts/wallpaper-gen.sh --reject 2026-05-21-035022-217e

# 步骤 3：推送到线上（自动 SSH + docker exec，不需要 admin JWT）
./scripts/wallpaper-publish.sh 2026-05-21-035022-217e
# 或者把所有 approved 一次性推完：
./scripts/wallpaper-publish.sh --all
```

### 看积压

```bash
./scripts/wallpaper-gen.sh --list
```

显示 pending / approved / uploaded 三个桶里的内容。

### 文件物理位置

```
项目根/ai-wallpapers/
├── pending/              # 出了 mini 但没确认
│   └── <id>/
│       ├── meta.json
│       └── mini.png
├── approved/             # 已经出 4K，等推送
│   └── <id>/
│       ├── meta.json
│       ├── mini.png
│       └── full.png
└── uploaded/             # 已经推送到站
    └── <id>/...          # 留作存档，不删
```

整个目录在 `.gitignore` 里，所以 `git status` 看不到。

### 想看 LLM 累计花费

需要先开 SSH 隧道（见 §7），不然 dashboard 上看不到 aigen 的消费记录。

### Tips

- prompt 输入中文英文都行，Claude 会自动扩写成英文
- **不要写人物**：生成出来质量不稳定 + 法律风险；硬性约束已经写死在代码里，但你写 prompt 时也避开
- 适合 AI 的题材：抽象渐变 / 极简几何 / 插画风景 / 低多边形 / 大理石木纹
- 不适合：写实风景照（用真照片）、特定地标、人像、文字海报

---

## 3. 壁纸质量审核（qcheck）

worker 在 publish 阶段会**自动 autotag**（写 category / tags / title），但**不做质量判断** —— 模糊、噪点重、AI 残影、文字水印、构图垃圾这些都需要 `qcheck` 这步专门来识别。

跑一遍 Claude vision 会给每张壁纸标一个 `quality_flag`：

| flag | 含义 | 处理建议 |
|---|---|---|
| `ok` | 正常 | 不做任何操作。**一旦标过 ok 就是 sticky 的**，下次再跑 qcheck 不会重判 |
| `blurry` | 模糊 / 失焦 | 通常硬删除 |
| `watermark` | 有水印 / 图源 logo | 通常硬删除 |
| `ai_slop` | 明显 AI 生成残影（手指畸形 / 物理违背 / 边缘融化）| 看情况，质感好的可保留 |
| `text_overlay` | 上面带文字 / 字幕 | 通常硬删除（壁纸用不上）|
| `low_aesthetic` | 构图垃圾 / 颜色脏 / 题材无聊 | 看情况，没人喜欢的下架 |

**前提**：标记后**不会自动删除**，只是放进后台"⚑ 已标记"队列，你手动审一遍后在 admin 里"硬删除"或"标为正常"。

### 何时跑

- 每 1-2 周 / 攒了 30+ 张新上传之后
- 发现首页 Latest 出现明显垃圾时（最直观信号）
- 计划做 Weekly Drop 之前（先洗一遍候选池）

### 跑法

```bash
# 1. 干跑（不写 DB），先看一眼会标多少 + 标成什么
./scripts/qcheck-local.sh

# 2. 觉得 OK → 实际写入 DB
./scripts/qcheck-local.sh --commit

# 3. 第一次跑保守一点，限制条数（小规模 canary）
./scripts/qcheck-local.sh --commit --limit 10
```

脚本会自动开 SSH 隧道 + 拉取候选 + 调 Claude vision + 写回 DB，每张约 $0.005，速率约 4-5 张/分钟。

### 跑完之后你手动做什么

1. 浏览器开 [/admin/wallpapers?quality_flag=flagged](https://wallpaperexchange.com/admin/wallpapers)（或在 admin 壁纸列表选 "⚑ 已标记" 过滤）
2. 一张张过：
   - 确实是垃圾 → 点 **硬删除**（连 MinIO 上的 variants 也会清，详见 [§11 紧急情况](#11-紧急情况)）
   - 误判 → 点 **标为正常**（这张被 sticky 锁，下次 qcheck 不会再碰）

### 历史欠债

到目前为止你的库里 **`quality_flag IS NULL` 的壁纸 ≈ 全部新上传**（worker 不写这字段，只有 qcheck 写）。要跑一次普查，约 800 张 × $0.005 = **~$4**。

```bash
./scripts/qcheck-local.sh --commit
```

跑完后只有真正可疑的 50-80 张会出现在 "⚑ 已标记" 里，剩下的全自动打 `ok` 不会再被复跑。

### AI 类型识别（aicheck）

手动导入的壁纸不会自动带上 `is_ai_generated`。`aicheck` 专门判断明显的 AI 生成图，并把高置信度结果归入后台的 **AI** 类型：

```bash
# 干跑，不写数据库
./scripts/aicheck-local.sh --limit 10

# 只处理指定上传时间段并写入（时间必须是 RFC3339）
./scripts/aicheck-local.sh --commit \
  --created-after 2026-08-09T15:00:00Z \
  --created-before 2026-08-10T15:00:00Z
```

这个任务只查询并下载 `preview_url` 到本机内存，再把预览图字节交给 Claude；不会查询、下载或回退到原图。默认只有模型判断为 AI 且置信度达到 `0.85` 才会写 `is_ai_generated=true`。后台壁纸编辑弹窗可以手动勾选或取消“AI 生成壁纸”。

---

## 4. 发版（macOS 客户端）

每次发版你要改 3 个文本文件，跑 1 个构建脚本，并提交生成的 DMG 静态资源。

### 3.1 改 3 个文件

| 文件 | 改什么 |
|---|---|
| `macos/WallpaperExchange/Info.plist` | `CFBundleShortVersionString`（e.g. `1.3.2`）+ `CFBundleVersion`（数字 +1，e.g. `9`）|
| `macos/CHANGELOG.md` | 顶部加一个新版本块，跟之前格式一致 |
| `backend/internal/handler/mac_release.json` | `current_version` + `current_dmg_url`（相对路径 `/downloads/mac/WallpaperExchange-X.Y.Z.dmg`）+ 在 `releases` 数组顶端加新条目 |

三处版本号必须**完全一致**。

### 3.2 构建、提交、部署

```bash
# 1. 构建 .dmg，并复制到 frontend/public/downloads/mac/
./release-mac.sh

# 2. 提交版本号 + changelog + release manifest + DMG 静态资源
git add macos/WallpaperExchange/Info.plist macos/CHANGELOG.md backend/internal/handler/mac_release.json frontend/public/downloads/mac/
git commit -m "release(mac): vX.Y.Z — <一句话改动摘要>"
git push origin main

# 3. 让 prod 同时拿到静态 DMG 和 /mac/release manifest
./deploy.sh
```

### 3.3 自动升级会怎么走

- 已在 1.3.0+ 的用户：开 app 5 秒后弹出"New version available — X.Y.Z"提示框
- 在 1.2.x 的用户：自己去 [/download/mac](https://wallpaperexchange.com/download/mac) 手动下载（**最后一次手动**）

### 3.4 验证

```bash
curl -fsS "https://wallpaperexchange.com/api/v1/mac/release" | python3 -m json.tool | head -5
curl -fsSI "https://wallpaperexchange.com/downloads/mac/WallpaperExchange-X.Y.Z.dmg" | head
```

应该看到新的 `current_version`。

---

## 5. 部署（后端 / 前端）

### 常规部署

```bash
git push                     # main 分支由 Cloudflare Pages 构建并发布 Web
./deploy.sh                  # 部署 api + worker，并确保 cloudflared 运行
./deploy.sh backend          # 仅显式重建 api + worker
```

服务器不再运行 frontend 容器。后端部署脚本会自动 prune docker build
cache（防止磁盘炸），不用你手动清。

### 数据库 schema 改了之后

如果改了 `deployments/init.sql`，要手动同步到 prod：

```bash
# 看下要执行的 SQL
git diff main -- deployments/init.sql

# 直接连上 prod psql 改
ssh root@139.224.49.94 'docker compose -f /opt/app/wallpaper/docker-compose.yml exec -T postgres psql -U wallpaper -d wallpaper' < your_migration.sql

# 或者重跑整个 init.sql（IF NOT EXISTS 让它幂等）
ssh root@139.224.49.94 'cd /opt/app/wallpaper && ./wallctl.sh db-migrate'
```

### 几个常用维护脚本

| 脚本 | 干什么 | 触发条件 | 详细说明 |
|---|---|---|---|
| `./scripts/qcheck-local.sh` | 把低质量壁纸标 flag 进队列 | 1-2 周一次 | 见 [§3](#3-壁纸质量审核qcheck) |
| `./scripts/sweep-orphan-variants.sh` | 清理 MinIO 上没有 DB 引用的孤儿文件 | 几个月一次，看存储占用 | — |

> Weekly Drop 现在完全走人工运营。到后台的"每周推荐"手动选 10 张并保存；首页推荐合集到"合集"里创建 `首页推荐合集`。

---

## 6. 内容运营（待手动发布）

所有稿件在 `docs/promotion/` 下，按需复制粘贴。

| 文件 | 渠道 | 何时发 |
|---|---|---|
| `sspai-launch.md` | [sspai.com 矩阵](https://sspai.com/matrix) | 任何时候，越早越好；链接已经用 `wallpaperexchange.com`（国内可达）|
| `alternativeto-listing.md` | [alternativeto.net/submit](https://alternativeto.net/submit/) | 复制每个字段填表 |
| `show-hn-launch.md` | [news.ycombinator.com/submit](https://news.ycombinator.com/submit) | **等 Mac 1.3 发版日** UTC 08:00-14:00 |
| `product-hunt-launch.md` | [producthunt.com/posts/new](https://www.producthunt.com/posts/new) | **同上**，太平洋时间周二/三 00:01 PT |

发完任一渠道，**回这里勾选一下做记录**（替换 ☐ 为 ✓）：

- ☐ SSPai 投稿
- ☐ AlternativeTo 列表
- ☐ Show HN（留给 Mac 1.3）
- ☐ Product Hunt（留给 Mac 1.3）
- ☐ 小红书首批 5 条种子内容
- ☐ Reddit r/wallpapers 试水第一帖

---

## 7. SEO / 搜索引擎索引

### 6.1 自动跑的（不用你管）

- **IndexNow**：每张新壁纸 publish 后自动 ping Bing/Yandex
- **GSC sitemap**：已提交，Google 自己定期抓
- **RSS feed**：`/feed.xml` 已上线，聚合器自动订

### 6.2 你可以做的加速

**Google Search Console URL Inspection**（每天限额 ~10 条，5 分钟搞定一批）：

1. 进 [search.google.com/search-console](https://search.google.com/search-console)
2. 顶部输入框贴 URL → 回车
3. 等 30 秒 → 点 **Request Indexing**

优先 inspect 的页面：
- `https://wallpaperexchange.com/`
- `https://wallpaperexchange.com/discover`
- `https://wallpaperexchange.com/weekly-picks`
- `https://wallpaperexchange.com/wallpapers-for`
- 几张代表性 `https://wallpaperexchange.com/wallpaper/<slug>`

### 6.3 全站重新提交到 IndexNow（罕用）

如果重新整理过 URL 结构，或者 Bing 收录数突然掉：

```bash
ssh root@139.224.49.94 'docker compose -f /opt/app/wallpaper/docker-compose.yml exec -T api /bin/indexnow-backfill --commit'
```

---

## 8. 基础设施 / 调试

### 7.1 SSH 隧道（开 / 关）

很多本地脚本（aigen / autotag / qcheck）需要连 prod Postgres 记录 `llm_usage`。开一次隧道之后可以一直用。

```bash
# 开（后台跑）
ssh -L 15432:127.0.0.1:5432 root@139.224.49.94 -N -f

# 看在不在
pgrep -fl "ssh.*15432.*139.224.49.94"

# 关
pgrep -f "ssh.*15432.*139.224.49.94" | xargs kill
```

> 不开也能跑生成 / 推送 —— 只是 admin dashboard 的 LLM 消费看不到这一笔。

### 7.2 看 prod 日志

```bash
# 全部容器最近 30 行
ssh root@139.224.49.94 'docker compose -f /opt/app/wallpaper/docker-compose.yml logs --tail 30'

# 只看某个服务
ssh root@139.224.49.94 'docker compose -f /opt/app/wallpaper/docker-compose.yml logs api --tail 100'
ssh root@139.224.49.94 'docker compose -f /opt/app/wallpaper/docker-compose.yml logs worker --tail 100'

# 实时 follow
ssh root@139.224.49.94 'docker compose -f /opt/app/wallpaper/docker-compose.yml logs -f api'
```

### 7.3 进 prod 数据库 psql

```bash
ssh root@139.224.49.94 'docker compose -f /opt/app/wallpaper/docker-compose.yml exec -it postgres psql -U wallpaper -d wallpaper'
```

### 7.4 看磁盘占用

```bash
ssh root@139.224.49.94 'df -h / && docker system df'
```

剩余 < 5GB 就要警觉了。`./deploy.sh` 现在会自动 prune docker cache，但 MinIO 数据不会清。

### 7.5 重启某个服务

```bash
# 通过部署脚本（带 git pull + rebuild）
./deploy.sh backend

# 直接重启（不拉新代码）
ssh root@139.224.49.94 'cd /opt/app/wallpaper && ./wallctl.sh restart api'
```

---

## 9. 密钥 / API Key 速查

### 8.1 本地 `.env`（项目根目录，gitignored）

| 变量 | 用途 | 哪里拿 |
|---|---|---|
| `OPENAI_API_KEY` | aigen 调 gpt-image-2 | [platform.openai.com](https://platform.openai.com/) → API Keys |
| `ANTHROPIC_API_KEY` | aigen prompt 扩写、autotag、qcheck | 跟 prod 的一致；`ssh root@139.224.49.94 'grep ANTHROPIC /opt/app/wallpaper/.env'` |
| `INDEXNOW_KEY` | IndexNow 验证字符串 | 自动生成的，无需重置 |
| `PINTEREST_APP_ID` / `PINTEREST_APP_SECRET` | Pinterest API OAuth + 发 Pin | [developers.pinterest.com](https://developers.pinterest.com/apps/) |

### 8.2 服务器 `/opt/app/wallpaper/.env`

跟本地一份，外加 docker compose 用的 `POSTGRES_*` / `MINIO_*` / `JWT_SECRET`
和生产专用的 `CLOUDFLARE_TUNNEL_TOKEN`。Tunnel 将
`api.wallpaperexchange.com`、`storage.wallpaperexchange.com` 分别接到 API、MinIO；
客户端的普通请求仍统一访问 `wallpaperexchange.com` 主域名。Web 图片/视频上传
直接访问 `api.wallpaperexchange.com/api/v1`，绕过 Pages Function 的请求体转发；
Tunnel 在 Compose 中固定为 HTTP/2，以避免生产线路上的 QUIC 上传中断。

**复制本地某个 key 到服务器**：

```bash
KEY=OPENAI_API_KEY
VAL=$(grep "^$KEY=" .env | tail -1 | cut -d= -f2-)
ssh root@139.224.49.94 "
  if grep -q '^$KEY=' /opt/app/wallpaper/.env; then
    sed -i 's|^$KEY=.*|$KEY=$VAL|' /opt/app/wallpaper/.env
  else
    echo '$KEY=$VAL' >> /opt/app/wallpaper/.env
  fi
"
./deploy.sh backend   # 重启让 env 生效
```

### 8.3 OpenAI 余额查询

OpenAI 没账户余额公开 API。**消费**可以在我们 dashboard 看；**余额**只能去 [platform.openai.com/usage](https://platform.openai.com/usage)。

---

## 10. 仍在等待外部审批

| 事项 | 状态 | 审过来要做什么 |
|---|---|---|
| Pinterest Standard Access | 录制演示视频后提交升级 | 后台 `/admin/integrations` 可授权官方账号并测试发 Pin；回调地址是 `https://wallpaperexchange.com/api/v1/admin/integrations/pinterest/callback` |
| DeviantArt Developer App | 没注册 | 见 `docs/promotion/tumblr-deviantart-setup.md`，注册后给 client_id / secret |
| Tumblr Developer App | 没注册 | 同上，**Tumblr 不需要审批，注册当天就能跑** |
| ICP 备案 wallpaperexchange.com | 没办 | 备完案可以接 Cloudflare China Network / 阿里云 CDN，国内访问主域不再卡 |

---

## 11. 紧急情况

### 站打不开

1. 看是不是磁盘满了：`ssh root@139.224.49.94 'df -h /'`
2. 看 api 容器状态：`ssh root@139.224.49.94 'docker compose -f /opt/app/wallpaper/docker-compose.yml ps'`
3. 看 api 日志最近 100 行
4. 实在不行重启：`./deploy.sh backend`

### admin dashboard 数据全是 0

很可能是某个 SQL 字段名写错（之前踩过 `pageview` vs `page_view`）。去看 api 日志最近的 ERROR。

### 自动升级 mac 客户端坏了

走老路：[https://wallpaperexchange.com/download/mac](https://wallpaperexchange.com/download/mac) 手动下载最新 DMG 拖到 /Applications 覆盖。

### LLM 消费突然飙升

去 admin dashboard 的"LLM 消费 · 按用途"看哪个 purpose 在烧钱。最常见嫌疑：autotag 或 qcheck 在 reprocess 一大批。看 `llm_usage` 表的 `created_at` 找时间点。

```bash
ssh root@139.224.49.94 'docker compose -f /opt/app/wallpaper/docker-compose.yml exec -T postgres psql -U wallpaper -d wallpaper -c "
  SELECT purpose, COUNT(*), SUM(cost_usd)::numeric(10,4) as usd
  FROM llm_usage
  WHERE created_at >= NOW() - INTERVAL '"'"'1 day'"'"'
  GROUP BY purpose ORDER BY usd DESC;"'
```
