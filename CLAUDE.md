# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Communication

- All conversation with the user (explanations, replies, status updates) must be in **中文**. Code, comments, and commit messages stay in English. See `.cursor/rules/01-language.mdc`.
- `.cursor/rules/auto-commit-push.mdc` applies to Claude Code too: after every completed change, `git add <specific files>` → `git commit` (Conventional Commits, with the Co-Authored-By trailer from the system prompt) → `git push`. Split unrelated changes into separate commits. Do not pause to ask. Still follow the system prompt's git safety rules — no `--no-verify`, no force-pushing `main`, no amending pushed commits.

## Deploys & Releases

There is **no CI-driven deploy**. `git push` only builds — it does not ship. Claude Code is expected to drive both flows from the local checkout via SSH (key auth is set up to `root@139.224.49.94`).

- **Whenever the user asks to deploy / 更新服务 / 重启服务 / "push to prod"**, run `./deploy.sh` from the repo root. It SSHes to the prod host and runs `./wallctl.sh deploy` (git pull + rebuild + restart api/worker/frontend). Pass a service name (`./deploy.sh frontend`, `./deploy.sh backend`) to scope it down — that maps to `wallctl.sh restart <service>` on the host and is much faster than a full rebuild.
- **Whenever the user asks to release the Mac client / 发布 mac 版本**, run `./release-mac.sh` from the repo root. It builds `.app` + `.dmg` and copies the DMG into `frontend/public/downloads/mac/` as a static frontend asset. Before running it, make sure `macos/WallpaperExchange/Info.plist` (CFBundleShortVersionString + CFBundleVersion), `macos/CHANGELOG.md`, and `backend/internal/handler/mac_release.json` are all bumped to the new version — the script reads the version from Info.plist, and `current_dmg_url` should be a relative URL like `/downloads/mac/WallpaperExchange-X.Y.Z.dmg`. Each new entry in `mac_release.json` needs both the English `notes` array (old Mac clients hard-decode that shape — never change it to an object) and a `notes_i18n` map with `zh-CN` / `zh-TW` / `ja` arrays of the same length (the web download page picks by UI language). After the script copies the DMG, commit the version files plus the generated DMG, push, then run `./deploy.sh` so both the frontend static asset and backend release manifest are served.

- **Whenever the prod host runs low on disk / 清理磁盘 / 磁盘满了**, run `./clean-disk.sh` from the repo root. It SSHes in, prints `df` + `docker system df` + journal usage, asks for confirmation, then reclaims the *safe* stuff only: `docker builder prune -af`, `docker image prune -af`, and `journalctl --vacuum-size=80M`. Use `./clean-disk.sh --check` to inspect without changing anything, or `-y` to skip the prompt. It **never** prunes docker volumes — the host's "dangling" volume list includes other apps' named data volumes (`word-game_mysql_data`, `dolphin_*`, `wallpaper_caddy_*`) and MinIO's wallpaper storage, so a blind `docker volume prune` would delete real data. Tune the journal cap via `JOURNAL_KEEP=200M`. (Context: 2026-05-27 the 40G host hit 100% mid-deploy and crashed Kafka with `No space left on device`; build cache + unused images were the bulk.)

Both scripts assume `SSH_HOST=root@139.224.49.94` and `SSH_DEPLOY_PATH=/opt/app/wallpaper`; override via env if either changes (`clean-disk.sh` honors `SSH_HOST` too).

## Repository Layout

This is a 3-surface monorepo for the WallShare / Wallpaper Exchange product:

- `backend/` — Go API server + Kafka workers + slug-regen CLI (Go 1.22+, single `go.mod`).
- `frontend/` — React 19 + TypeScript + Vite + TailwindCSS v4 SPA.
- `macos/WallpaperExchange/` — SwiftPM menu-bar app for macOS 14+ (status-bar `NSPopover`, no main window; `LSUIElement=true`).
- `ios/WallpaperExchange/` — SwiftUI iOS app (iOS 17+, XcodeGen project). Models/Keychain/endpoint extension are verbatim copies of the macOS sources; `APIClient.swift` is the UIKit-adapted variant. **Requires full Xcode to build** (CommandLineTools can only `swiftc -parse`); see `ios/README.md`. Keep both clients in sync when an endpoint changes.
- `deployments/` — `init.sql` (canonical DB schema), `Caddyfile`, `nginx.conf` for the frontend container.
- `docs/` — Product spec (`product.md`) and technical architecture (`architecture.md`) in Chinese.
- `wallctl.sh` — Operational CLI wrapping `docker compose` (project name `wallpaper`).

## Common Commands

Top-level operations go through `./wallctl.sh` (Docker Compose orchestration):

```bash
./wallctl.sh start                  # build + start full stack
./wallctl.sh restart backend        # rebuild api+worker only (also: frontend, app, <service>)
./wallctl.sh logs api 200           # tail last 200 lines of one service
./wallctl.sh deploy                 # git pull + rebuild + restart api/worker/frontend
./wallctl.sh db-shell               # psql into postgres container
./wallctl.sh db-migrate             # re-apply deployments/init.sql
./wallctl.sh sluggen [--force]      # regenerate URL slugs (runs /bin/sluggen in api container)
./wallctl.sh reset-data             # wipe all data except users (resets MinIO, Redis, Kafka offsets)
```

Local development (each surface runs independently):

```bash
# backend api
cd backend && go run ./cmd/api
# kafka workers
cd backend && go run ./cmd/worker
# slug regenerator CLI
cd backend && go run ./cmd/sluggen [--force]

# frontend (Vite dev server on :5173, proxies /api → :8080)
cd frontend && npm install && npm run dev
cd frontend && npm run lint           # eslint
cd frontend && npm run build          # tsc -b && vite build

# macOS app
cd macos/WallpaperExchange && swift build
# (Info.plist is linked into the binary via Package.swift's -sectcreate flag)

# iOS app (needs full Xcode + xcodegen; not buildable with CLT alone)
cd ios && xcodegen generate && open WallpaperExchange.xcodeproj
```

There is no test suite in this repo. `backend/migrations/` exists but is **empty** — the authoritative schema is `deployments/init.sql`, applied via `./wallctl.sh db-migrate`.

## Backend Architecture

Entry points: `backend/cmd/{api,worker,sluggen}/main.go`. All three share `internal/config` (env-var loader via `caarlos0/env`).

Layered structure inside `backend/internal/`:

```
handler/   chi routes + HTTP I/O           (wires URL → service)
service/   business logic + Kafka producer (auth, wallpaper, collection)
repo/      GORM queries + transactions
model/     GORM struct definitions
middleware Auth (JWT), OptionalAuth, Logger, Recovery, RateLimiter (in-memory token bucket)
worker/    Kafka consumers: image + stats
cache/     Redis client wrapper (currently underused — initialized but not heavily wired)
pkg/
  errcode/ Centralized business error codes (Code int + Message)
  response Unified JSON envelope {code, message, data}
  jwt/     HS256 signing / parsing
  storage/ MinIO client wrapper (EnsureBucket, presigned URLs, object IO)
  slug/    URL-safe slug generation with short random suffix
```

Wiring is manual constructor injection in `cmd/api/main.go` — there is no DI framework. New repo/service/handler types should be added there and to `handler.Deps`.

### Routes & Auth Modes (`internal/handler/router.go`)

Three auth tiers under `/api/v1`:
- **Public**: register, login, categories, tags, devices, users list.
- **OptionalAuth**: list/get wallpapers, collections, user wallpaper lists. Injects userID if JWT present so `is_liked` / `is_favorited` fields populate, otherwise anonymous.
- **Auth (required)**: uploads, deletes, likes, favorites, downloads, profile mutation, coin endpoints, collection mutation.

CORS allow-list is **hard-coded** in `router.go`: `wallpaperexchange.com`, `www.wallpaperexchange.com`, plus any `http://localhost:*`. Update there when adding domains.

### Kafka Event Flow

Producer: API server (single `kafka.Writer` in `cmd/api/main.go`, `AllowAutoTopicCreation=true`).
Consumers: `cmd/worker` runs both workers concurrently via `errgroup`.

| Topic | Group | Worker | Purpose |
|---|---|---|---|
| `wallpaper.uploaded` | `image-worker` | `worker.ImageWorker` | Decode original (incl. HEIC via `gen2brain/heic`), generate thumb/preview, detect dominant color and `apple_desktop` dynamic-wallpaper tags (`solar`/`h24`/`apr`), upload variants, update `wallpapers.status` → published/failed. |
| `wallpaper.stats` | `stats-worker` | `worker.StatsWorker` | Aggregate view/download events in memory, batch-update counters every 10s or 1k events. |

When resetting consumer offsets, **stop the worker first** (`wallctl.sh reset-data` already does this — Kafka rejects offset resets on active groups).

### Storage & URLs

- MinIO bucket name from `MINIO_BUCKET` (default `wallpapers`). `EnsureBucket` runs at API startup.
- Public URLs use `MINIO_PUBLIC_URL` (in prod: `https://${SITE_DOMAIN}/storage`, proxied via Caddy). Object keys are stored in `original_url` / `thumb_url` / `preview_url` columns.
- Wallpapers expose a `slug` (unique index) used in routes; `cmd/sluggen` backfills empty slugs (or all slugs with `--force`).
- Dynamic wallpapers (Apple solar/h24) are decomposed into individual frame PNGs; `frame_urls` is a TEXT-serialized list.

### DB Schema

PostgreSQL 16, all timestamps `TIMESTAMPTZ(6)` in UTC. Identity columns (`BIGINT GENERATED ALWAYS AS IDENTITY`) for primary keys. Schema and seed categories are in `deployments/init.sql`. GORM is configured **without** `AutoMigrate` — schema changes must be added to `init.sql` and applied via `./wallctl.sh db-migrate` (or re-running `init.sql` against the DB).

## Frontend Architecture

React 19 + React Router 7 SPA. Key conventions:

- **API base URL resolution** (`src/api/client.ts:resolveBaseURL`): uses `VITE_API_BASE_URL` if set, else maps `wallpaperexchange.com` → `https://api.wallpaperexchange.com/api/v1`, else falls back to relative `/api/v1` (dev proxy in `vite.config.ts` routes to `:8080`). Any new XHR endpoint that bypasses axios (e.g. raw `fetch` for downloads/uploads) must call `resolveBaseURL()` directly — see recent commits `2715eef`, `47d43d5`.
- **Auth token**: stored in `localStorage` as `token`; axios interceptor attaches `Authorization: Bearer`. 401 responses force redirect to `/login`.
- **State**: Zustand store in `src/store/auth.ts`. No other global stores.
- **Routing**: uses the `location.state.background` pattern in `App.tsx` to show `WallpaperDetailModal` overlaid on the previous page (Unsplash-style modal) while keeping `/wallpaper/:slug` as a sharable deep link.
- **Styling**: TailwindCSS v4 via `@tailwindcss/vite` plugin (no `tailwind.config.js`).

## macOS App Architecture

Menu-bar–only app (no Dock icon — `LSUIElement` is true). Structure under `macos/WallpaperExchange/Sources/`:

- `App/` — `AppDelegate` sets up the `NSStatusItem`, transient `NSPopover` with `PopoverContentView`, global mouse-event monitor to dismiss, and the `wallxch://` URL scheme handler for OAuth callback (`wallxch://auth?token=...`).
- `Services/` — `APIClient` (actor, `baseURL` is **hard-coded** to `https://api.wallpaperexchange.com/api/v1`), `AuthService` (singleton, token persistence + URL callback), `WallpaperManager` (downloads to `~/Library/Application Support/WallpaperExchange/Downloads`, applies wallpapers).
- `Models/`, `Views/` — SwiftUI views inside the popover.

Info.plist is **injected into the binary at link time** via `unsafeFlags` in `Package.swift` (`-sectcreate __TEXT,__info_plist`). Don't add it to `resources` — `swift build` won't pick it up. The bundle ID is `com.wallpaperexchange.mac`.

## Environment

Backend reads everything from env (see `backend/internal/config/config.go`). Defaults assume `localhost` services; Docker Compose injects production hostnames (`postgres`, `redis`, `minio:9000`, `kafka:9092`). The root `.env` (copied from `.env.example`) only configures Compose; the API container receives a separate explicit env block in `docker-compose.yml`.
