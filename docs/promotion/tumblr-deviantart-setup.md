# Tumblr + DeviantArt 自动发布：注册指引

> 跟 Pinterest 是同一个模式：你先在两个平台各开一个 developer app，给我 client_id + client_secret，我建集成。两个平台都 **不需要付费、不需要 trial 审批**（这是它们的相对优势）。

---

## Tumblr

### 1. 注册 / 升级账号

- 如果还没 Tumblr 账号，去 [tumblr.com](https://www.tumblr.com/register) 注册。**用邮箱注册即可，不需要企业认证**。
- 选好你的 blog name（这就是 wallpaperexchange.tumblr.com 的子域，**注册后不能改**，挑个好的）。建议直接用 `wallpaperexchange` 或 `wxch`。

### 2. 创建 Application

去 [tumblr.com/oauth/apps](https://www.tumblr.com/oauth/apps) 点 **+ Register application**。

填表：

| 字段 | 填什么 |
|---|---|
| Application Name | `WallpaperExchange` |
| Application Website | `https://wallpaperexchange.com` |
| Application Description | `Auto-publishes hand-picked wallpapers from wallpaperexchange.com to our Tumblr blog.` |
| Administrative contact email | 你的邮箱 |
| **Default callback URL** | `https://api.wallpaperexchange.com/api/v1/admin/integrations/tumblr/callback` |
| OAuth2 redirect URLs | 同上 |

提交后立即拿到：
- **OAuth Consumer Key**（= `client_id`）
- **OAuth Consumer Secret**（= `client_secret`）

把这两个连同你的 blog name 发我，我接着干。

### 3. 关键事实

- Tumblr 用 **OAuth 1.0a** + 现代 OAuth2 都支持。我会用 OAuth2（更简单）。
- 速率限制：**5000 calls / day per consumer key**，5 posts per hour per blog。我们每天最多 25 张帖（每小时 1 张），完全在限额内。
- 不需要 verification、不需要审批、注册当天就能跑。

---

## DeviantArt

### 1. 注册 / 升级账号

- 注册 [deviantart.com](https://www.deviantart.com/users/login)（免费）。
- 升级 Core 不强求 —— 自动发布的 deviation 在免费账号也能用。

### 2. 创建 Application

进 [deviantart.com/developers/apps](https://www.deviantart.com/developers/apps) → **Register Your Application**。

填表：

| 字段 | 填什么 |
|---|---|
| Application Name | `WallpaperExchange Sync` |
| Application Description | `Sync curated wallpapers from wallpaperexchange.com to our DeviantArt gallery.` |
| Website | `https://wallpaperexchange.com` |
| **OAuth2 Redirect URI Whitelist** | `https://api.wallpaperexchange.com/api/v1/admin/integrations/deviantart/callback` |
| Grant types | 勾选 `Authorization Code` 即可，其它默认 |

提交后等审批：**DeviantArt 的 dev app 默认是 trial 状态**，需要他们手动审。一般 1-3 个工作日。

审过之前你能拿到：
- **Client ID**
- **Client Secret**

发我这两个 + 一句"审过了"，我开工。

### 3. 关键事实

- DeviantArt 也支持 OAuth2 → 集成同 Tumblr 一样的代码框架，可以复用一半逻辑。
- 速率限制：**10 calls/sec, 100k calls/day** —— 这是我见过最大方的额度，每天发 100 张都不会接近。
- 上传图片的接口叫 `/stash/submit` 然后 `/stash/publish`，分两步（**stash 是 sandbox**，publish 才进画廊）。

---

## 我会怎么实现

跟 Pinterest 同结构，复用 `backend/internal/pkg/{tumblr,deviantart}/client.go` + `cmd/{tumblr,deviantart}-post`。一次 OAuth 授权后存 refresh token，之后自动续期。

**触发节奏**：

| 时机 | 行为 |
|---|---|
| Weekly Drop 当天 | 把当周 10 张全部发到 Tumblr + DeviantArt |
| 每天 18:00 (UTC+8) | 从过去 48h 上传中挑 1 张热度最高的发 Tumblr |

Pinterest 一旦审过来也接入这套，统一节流。

---

## 我推荐的顺序

1. **现在** 去注册 Tumblr，能立刻给我 key。Tumblr 不需要审批，是这俩里最快上线的。
2. **顺便** 注册 DeviantArt 提交 app，等审批中。
3. **审批期间** 我把 Tumblr 跑起来 + 把 DeviantArt 的代码框架先写好，审过来直接接上。

两个一起跑通后，加上将来 Pinterest，我们就有 **3 个海外免费图片站自动同步**，每张壁纸 SEO 反向链接 ×3，长期复利效果挺好。
