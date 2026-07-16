# WallShare - Wallpaper Sharing App

A full-stack wallpaper sharing platform where users can upload, browse, search, download, and collect high-quality wallpapers.

## Tech Stack

- **Backend**: Go (chi router + GORM)
- **Frontend**: React 19 + TypeScript + TailwindCSS
- **Database**: PostgreSQL 16
- **Cache**: Redis 7
- **Object Storage**: MinIO (S3-compatible)
- **Message Queue**: Kafka (KRaft mode)
- **Deployment**: Cloudflare Pages (Web) + Docker Compose (backend services)

## Quick Start

### Prerequisites

- Docker & Docker Compose v2

### Configuration

```bash
cp .env.example .env
vi .env    # Modify as needed
```

Available `.env` variables:

| Variable | Default | Description |
|---|---|---|
| `HTTP_PORT` | `80` | HTTP port on host |
| `HTTPS_PORT` | `443` | HTTPS port on host |
| `POSTGRES_USER` | `wallpaper` | PostgreSQL username |
| `POSTGRES_PASSWORD` | `wallpaper` | PostgreSQL password |
| `POSTGRES_DB` | `wallpaper` | PostgreSQL database name |
| `REDIS_PASSWORD` | (empty) | Redis password (optional) |
| `MINIO_ROOT_USER` | `minioadmin` | MinIO access key |
| `MINIO_ROOT_PASSWORD` | `minioadmin` | MinIO secret key |
| `MINIO_BUCKET` | `wallpapers` | MinIO bucket name |
| `MINIO_PUBLIC_URL` | `https://wallpaperexchange.com/storage` | Public media URL proxied by Cloudflare Pages |
| `CLOUDFLARE_TUNNEL_TOKEN` | (empty) | Production token for the outbound API/MinIO origin tunnel |
| `JWT_SECRET` | `change-me...` | JWT signing secret |
| `JWT_EXPIRE_HOUR` | `24` | JWT token expiry (hours) |

### Run

```bash
./wallctl.sh start
```

`wallctl.sh start` starts backend infrastructure only. The Web build is published
from `main` by Cloudflare Pages. API and MinIO remain private Docker services;
`cloudflared` exposes them as `api.wallpaperexchange.com` and
`storage.wallpaperexchange.com` only for the Pages Function, while all public
clients continue to use `https://wallpaperexchange.com/api/...` and
`https://wallpaperexchange.com/storage/...`.

### Development

**Backend** (requires Go 1.22+):

```bash
cd backend
cp .env.example .env  # configure if needed
go run ./cmd/api
```

**Worker**:

```bash
cd backend
go run ./cmd/worker
```

**Frontend** (requires Node 20+):

```bash
cd frontend
npm install
npm run dev
```

The dev server proxies `/api` requests to `localhost:8080`.

## Project Structure

```
wallpaper/
├── docker-compose.yml          # Backend service orchestration
├── backend/
│   ├── cmd/api/                # API server entry point
│   ├── cmd/worker/             # Kafka workers entry point
│   ├── internal/
│   │   ├── cache/              # Redis cache wrapper
│   │   ├── config/             # Config from env vars
│   │   ├── handler/            # HTTP handlers + router
│   │   ├── middleware/         # Auth, logging, rate limiting
│   │   ├── model/              # GORM models
│   │   ├── repo/               # Database operations
│   │   ├── service/            # Business logic
│   │   ├── worker/             # Kafka consumers
│   │   └── pkg/                # Internal utilities
│   └── Dockerfile
├── frontend/
│   ├── src/
│   │   ├── api/                # API client
│   │   ├── components/         # Reusable UI components
│   │   ├── pages/              # Route pages
│   │   ├── store/              # Zustand state
│   │   └── types/              # TypeScript types
│   └── Dockerfile
├── deployments/
│   └── init.sql                # DB schema + seed data
└── docs/
    ├── product.md              # Product specification
    └── architecture.md         # Technical architecture
```

## API Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | /api/v1/auth/register | No | Register |
| POST | /api/v1/auth/login | No | Login |
| GET | /api/v1/wallpapers | No | List wallpapers |
| GET | /api/v1/wallpapers/:id | No | Wallpaper detail |
| POST | /api/v1/wallpapers | Yes | Upload wallpaper |
| DELETE | /api/v1/wallpapers/:id | Yes | Delete wallpaper |
| POST | /api/v1/wallpapers/:id/like | Yes | Like |
| DELETE | /api/v1/wallpapers/:id/like | Yes | Unlike |
| POST | /api/v1/wallpapers/:id/favorite | Yes | Favorite |
| DELETE | /api/v1/wallpapers/:id/favorite | Yes | Unfavorite |
| GET | /api/v1/wallpapers/:id/download | No | Download |
| GET | /api/v1/categories | No | List categories |
| GET | /api/v1/tags | No | Popular tags |
| GET | /api/v1/users/:id | No | User profile |
| GET | /api/v1/users/:id/wallpapers | No | User's wallpapers |
| GET | /api/v1/users/me/favorites | Yes | My favorites |

## Architecture

See [docs/architecture.md](docs/architecture.md) for detailed technical architecture.

See [docs/product.md](docs/product.md) for product specification.
