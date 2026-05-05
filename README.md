# WallShare - Wallpaper Sharing App

A full-stack wallpaper sharing platform where users can upload, browse, search, download, and collect high-quality wallpapers.

## Tech Stack

- **Backend**: Go (chi router + GORM)
- **Frontend**: React 18 + TypeScript + TailwindCSS
- **Database**: PostgreSQL 16
- **Cache**: Redis 7
- **Object Storage**: MinIO (S3-compatible)
- **Message Queue**: Kafka (KRaft mode)
- **Deployment**: Docker Compose

## Quick Start

### Prerequisites

- Docker & Docker Compose v2

### Run

```bash
docker compose up --build
```

Services will be available at:

| Service | URL |
|---|---|
| Frontend | https://localhost (or http, auto-redirects) |
| MinIO Console | http://localhost:9001 |

**Production with real domain** (auto Let's Encrypt):

```bash
SITE_DOMAIN=wallpaper.example.com docker compose up --build -d
```

Caddy will automatically obtain and renew TLS certificates from Let's Encrypt.

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
├── docker-compose.yml          # Full stack orchestration
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
