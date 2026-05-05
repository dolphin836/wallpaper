# 壁纸分享应用 -- 技术架构

## 1. 系统架构总览

```
┌─────────────┐     HTTP/JSON     ┌──────────────┐
│  React SPA  │ ◄───────────────► │  Go API      │
│  (Nginx)    │                   │  (chi router) │
└─────────────┘                   └──────┬───────┘
                                         │
                    ┌────────────────┬────┴────────────┬──────────────┐
                    │                │                 │              │
               ┌────▼────┐    ┌─────▼─────┐    ┌─────▼─────┐  ┌────▼────┐
               │PostgreSQL│    │   MinIO   │    │   Redis   │  │  Kafka  │
               │  (数据)  │    │ (对象存储) │    │  (缓存)   │  │ (消息)  │
               └─────────┘    └───────────┘    └───────────┘  └────┬────┘
                                                                    │
                                                              ┌─────▼─────┐
                                                              │  Workers  │
                                                              │ (消费者)  │
                                                              └───────────┘
```

## 2. 技术选型

| 层 | 技术 | 版本 | 说明 |
|---|---|---|---|
| Frontend | React + TypeScript | React 18 | SPA，Vite 构建 |
| CSS | TailwindCSS | 3.x | 原子化 CSS |
| Backend API | Go + chi | Go 1.22+ | RESTful JSON API |
| ORM | GORM | v2 | PostgreSQL driver |
| Database | PostgreSQL | 16 | 主存储，TIMESTAMPTZ UTC |
| Cache | Redis | 7 | 列表缓存、频率限制 |
| Object Storage | MinIO | latest | S3 兼容，存储壁纸文件 |
| Message Queue | Kafka | 3.7 (KRaft) | 异步图片处理、统计聚合 |
| Migration | goose | v3 | SQL 迁移管理 |
| Auth | golang-jwt | v5 | JWT 认证 |
| Deployment | Docker Compose | v2 | 一键部署 |

## 3. 项目目录结构

```
wallpaper/
├── docker-compose.yml
├── backend/
│   ├── cmd/
│   │   ├── api/main.go           # API 服务入口
│   │   └── worker/main.go        # Kafka Worker 入口
│   ├── internal/
│   │   ├── config/               # 配置加载（env → struct）
│   │   ├── handler/              # HTTP handler（路由绑定）
│   │   ├── middleware/           # JWT、日志、CORS、Recovery
│   │   ├── model/                # GORM model 定义
│   │   ├── repo/                 # 数据库操作层
│   │   ├── service/              # 业务逻辑层
│   │   ├── worker/               # Kafka consumer 逻辑
│   │   └── pkg/
│   │       ├── errcode/          # 业务错误码
│   │       ├── response/         # 统一 JSON 响应
│   │       ├── jwt/              # JWT 签发与验证
│   │       └── storage/          # MinIO 客户端封装
│   ├── migrations/               # goose SQL 迁移文件
│   ├── Dockerfile
│   ├── go.mod
│   └── go.sum
├── frontend/
│   ├── src/
│   │   ├── api/                  # Axios 封装 + API 函数
│   │   ├── components/           # 通用 UI 组件
│   │   ├── pages/                # 页面组件
│   │   ├── hooks/                # 自定义 React Hooks
│   │   ├── store/                # Zustand 状态管理
│   │   └── types/                # TypeScript 类型定义
│   ├── Dockerfile
│   ├── package.json
│   └── vite.config.ts
├── deployments/
│   ├── nginx.conf                # 前端 Nginx 配置
│   └── init.sql                  # 数据库初始化（分类种子数据）
└── docs/
    ├── product.md
    └── architecture.md
```

## 4. 数据模型

### 4.1 ER 关系

```
users 1──N wallpapers
categories 1──N wallpapers
wallpapers N──M tags (via wallpaper_tags)
users N──M wallpapers (via user_likes)
users N──M wallpapers (via user_favorites)
```

### 4.2 表结构

#### users
| 字段 | 类型 | 说明 |
|---|---|---|
| id | BIGINT (identity) | 主键 |
| username | VARCHAR(32) | 用户名，唯一 |
| email | VARCHAR(255) | 邮箱，唯一 |
| password_hash | VARCHAR(255) | bcrypt 哈希 |
| nickname | VARCHAR(64) | 昵称 |
| avatar_url | VARCHAR(512) | 头像 URL |
| bio | VARCHAR(500) | 个性签名 |
| status | SMALLINT | 1=正常 0=禁用 |
| created_at | TIMESTAMPTZ(6) | 创建时间 UTC |
| updated_at | TIMESTAMPTZ(6) | 更新时间 UTC |

#### wallpapers
| 字段 | 类型 | 说明 |
|---|---|---|
| id | BIGINT (identity) | 主键 |
| user_id | BIGINT | 上传者 |
| category_id | BIGINT | 分类 |
| title | VARCHAR(128) | 标题 |
| description | VARCHAR(1000) | 描述 |
| original_url | VARCHAR(512) | 原图 MinIO 路径 |
| thumb_url | VARCHAR(512) | 缩略图路径 |
| preview_url | VARCHAR(512) | 预览图路径 |
| width | INT | 宽度 px |
| height | INT | 高度 px |
| file_size | BIGINT | 文件大小 bytes |
| file_type | VARCHAR(16) | MIME 类型 |
| dominant_color | VARCHAR(7) | 主色调 #RRGGBB |
| status | SMALLINT | 0=处理中 1=已发布 2=失败 3=下架 |
| view_count | BIGINT | 浏览次数 |
| like_count | BIGINT | 点赞数 |
| download_count | BIGINT | 下载数 |
| favorite_count | BIGINT | 收藏数 |
| created_at | TIMESTAMPTZ(6) | 创建时间 UTC |
| updated_at | TIMESTAMPTZ(6) | 更新时间 UTC |

#### categories / tags / wallpaper_tags / user_likes / user_favorites

见 migrations/ 目录下的 SQL 迁移文件。

## 5. API 设计

### 5.1 认证

| Method | Path | Auth | 说明 |
|---|---|---|---|
| POST | /api/v1/auth/register | No | 注册 |
| POST | /api/v1/auth/login | No | 登录 |

### 5.2 壁纸

| Method | Path | Auth | 说明 |
|---|---|---|---|
| POST | /api/v1/wallpapers | Yes | 上传壁纸 |
| GET | /api/v1/wallpapers | No | 壁纸列表（分页/筛选） |
| GET | /api/v1/wallpapers/:id | No | 壁纸详情 |
| DELETE | /api/v1/wallpapers/:id | Yes | 删除（仅作者） |

### 5.3 互动

| Method | Path | Auth | 说明 |
|---|---|---|---|
| POST | /api/v1/wallpapers/:id/like | Yes | 点赞 |
| DELETE | /api/v1/wallpapers/:id/like | Yes | 取消点赞 |
| POST | /api/v1/wallpapers/:id/favorite | Yes | 收藏 |
| DELETE | /api/v1/wallpapers/:id/favorite | Yes | 取消收藏 |
| GET | /api/v1/wallpapers/:id/download | No | 下载 |

### 5.4 分类与标签

| Method | Path | Auth | 说明 |
|---|---|---|---|
| GET | /api/v1/categories | No | 分类列表 |
| GET | /api/v1/tags | No | 热门标签 |

### 5.5 用户

| Method | Path | Auth | 说明 |
|---|---|---|---|
| GET | /api/v1/users/:id | No | 用户主页 |
| GET | /api/v1/users/:id/wallpapers | No | 用户壁纸 |
| GET | /api/v1/users/me/favorites | Yes | 我的收藏 |

### 5.6 统一响应格式

```json
{
  "code": 0,
  "message": "ok",
  "data": { ... }
}
```

错误响应：

```json
{
  "code": 40001,
  "message": "invalid email format",
  "data": null
}
```

### 5.7 分页参数（游标分页）

请求：`?cursor=xxx&limit=20`

响应：

```json
{
  "code": 0,
  "message": "ok",
  "data": {
    "items": [...],
    "next_cursor": "eyJpZCI6MTAwfQ",
    "has_more": true
  }
}
```

## 6. Kafka 事件流

### 6.1 Topics

| Topic | Producer | Consumer | 说明 |
|---|---|---|---|
| wallpaper.uploaded | API Server | Image Worker | 触发缩略图生成 |
| wallpaper.stats | API Server | Stats Worker | 浏览/下载统计聚合 |

### 6.2 Image Worker 流程

1. 消费 `wallpaper.uploaded` 消息
2. 从 MinIO 下载原图
3. 生成缩略图（300x200 WebP）和预览图（800px 宽 WebP）
4. 上传缩略图和预览图到 MinIO
5. 更新 wallpapers 表：thumb_url、preview_url、status=1
6. 失败时设置 status=2 并记录日志

### 6.3 Stats Worker 流程

1. 消费 `wallpaper.stats` 消息
2. 内存中按 wallpaper_id + event_type 聚合
3. 每 10 秒或累积 1000 条时，批量 UPDATE wallpapers 表的计数字段
4. 使用 `UPDATE wallpapers SET view_count = view_count + $delta WHERE id = $id`

## 7. Docker Compose 服务

| 服务 | 镜像 | 端口 | 依赖 |
|---|---|---|---|
| postgres | postgres:16-alpine | 5432 | - |
| redis | redis:7-alpine | 6379 | - |
| minio | minio/minio:latest | 9000/9001 | - |
| kafka | apache/kafka:3.7.0 | 9092 | - |
| api | 自构建 | 8080 | postgres, redis, minio, kafka |
| worker | 自构建 | - | postgres, minio, kafka |
| frontend | 自构建 (nginx) | 80 | api |

## 8. 安全考虑

- 密码使用 bcrypt 哈希存储（cost=10）
- JWT 有效期 24 小时，密钥从环境变量读取
- 文件上传校验 MIME 类型和文件大小
- SQL 参数化查询（GORM 默认）
- CORS 白名单配置
- Rate Limiting（Redis 令牌桶）
