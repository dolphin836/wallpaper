CREATE TABLE IF NOT EXISTS users (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username      VARCHAR(32)  NOT NULL UNIQUE,
    email         VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    nickname      VARCHAR(64)  NOT NULL DEFAULT '',
    avatar_url    VARCHAR(512) NOT NULL DEFAULT '',
    bio           VARCHAR(500) NOT NULL DEFAULT '',
    status        SMALLINT     NOT NULL DEFAULT 1,
    created_at    TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS register_client     VARCHAR(32)  NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS register_source     VARCHAR(128) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS register_referrer   VARCHAR(512) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS register_path       VARCHAR(512) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS register_ip         VARCHAR(64)  NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS register_user_agent VARCHAR(512) NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS register_country    VARCHAR(8)   NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_users_register_client ON users(register_client) WHERE register_client <> '';
CREATE INDEX IF NOT EXISTS idx_users_register_source ON users(register_source) WHERE register_source <> '';

CREATE TABLE IF NOT EXISTS categories (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       VARCHAR(64)  NOT NULL UNIQUE,
    slug       VARCHAR(64)  NOT NULL UNIQUE,
    sort_order INT          NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS wallpapers (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id        BIGINT         NOT NULL,
    category_id    BIGINT         NOT NULL,
    title          VARCHAR(128)   NOT NULL,
    description    VARCHAR(1000)  NOT NULL DEFAULT '',
    original_url   VARCHAR(512)   NOT NULL,
    thumb_url      VARCHAR(512)   NOT NULL DEFAULT '',
    preview_url    VARCHAR(512)   NOT NULL DEFAULT '',
    width          INT            NOT NULL DEFAULT 0,
    height         INT            NOT NULL DEFAULT 0,
    file_size      BIGINT         NOT NULL DEFAULT 0,
    file_type      VARCHAR(64)    NOT NULL DEFAULT '',
    dominant_color VARCHAR(7)     NOT NULL DEFAULT '',
    color_palette  VARCHAR(64)    NOT NULL DEFAULT '',
    status         SMALLINT       NOT NULL DEFAULT 0,
    view_count     BIGINT         NOT NULL DEFAULT 0,
    like_count     BIGINT         NOT NULL DEFAULT 0,
    download_count BIGINT         NOT NULL DEFAULT 0,
    favorite_count BIGINT         NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallpapers_user_id ON wallpapers(user_id);
CREATE INDEX IF NOT EXISTS idx_wallpapers_category_id ON wallpapers(category_id);
CREATE INDEX IF NOT EXISTS idx_wallpapers_status_created ON wallpapers(status, created_at DESC);

CREATE TABLE IF NOT EXISTS tags (
    id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(32) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS wallpaper_tags (
    wallpaper_id BIGINT NOT NULL,
    tag_id       BIGINT NOT NULL,
    PRIMARY KEY (wallpaper_id, tag_id)
);

CREATE INDEX IF NOT EXISTS idx_wallpaper_tags_tag_id ON wallpaper_tags(tag_id);

CREATE TABLE IF NOT EXISTS user_likes (
    user_id      BIGINT NOT NULL,
    wallpaper_id BIGINT NOT NULL,
    created_at   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, wallpaper_id)
);

CREATE TABLE IF NOT EXISTS user_favorites (
    user_id      BIGINT NOT NULL,
    wallpaper_id BIGINT NOT NULL,
    created_at   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, wallpaper_id)
);

CREATE INDEX IF NOT EXISTS idx_user_favorites_user ON user_favorites(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS device_profiles (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    platform   VARCHAR(32)  NOT NULL,
    brand      VARCHAR(64)  NOT NULL,
    name       VARCHAR(128) NOT NULL,
    width      INT          NOT NULL,
    height     INT          NOT NULL,
    ppi        INT          NOT NULL DEFAULT 0,
    sort_order INT          NOT NULL DEFAULT 0,
    is_active  BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_profiles_platform ON device_profiles(platform);
-- `name` must be unique so the seed INSERT below can use `ON CONFLICT (name) DO NOTHING`
-- to stay idempotent across repeated db-migrate runs (previously this was missing and the
-- seed silently duplicated every device every time the script was re-run).
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_profiles_name_unique ON device_profiles(name);

-- URL-safe slug derived from name, used in /wallpapers-for/:slug routes.
-- Postgres GENERATED column so we never need to maintain it manually —
-- inserts/updates to `name` automatically refresh the slug. Idempotent
-- on existing databases because IF NOT EXISTS skips the ADD COLUMN once
-- the column is in place.
ALTER TABLE device_profiles
    ADD COLUMN IF NOT EXISTS slug VARCHAR(160) GENERATED ALWAYS AS (
        lower(regexp_replace(regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g'), '(^-+|-+$)', '', 'g'))
    ) STORED;
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_profiles_slug_unique ON device_profiles(slug);

CREATE TABLE IF NOT EXISTS wallpaper_variants (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    wallpaper_id BIGINT       NOT NULL,
    device_id    BIGINT       NOT NULL,
    url          VARCHAR(512) NOT NULL,
    width        INT          NOT NULL,
    height       INT          NOT NULL,
    file_size    BIGINT       NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_variants_wallpaper ON wallpaper_variants(wallpaper_id, device_id);

ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS color_palette VARCHAR(64) NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS collections (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id         BIGINT         NOT NULL,
    title           VARCHAR(100)   NOT NULL,
    description     TEXT           NOT NULL DEFAULT '',
    cover_url       VARCHAR(512)   NOT NULL DEFAULT '',
    is_public       BOOLEAN        NOT NULL DEFAULT TRUE,
    wallpaper_count INT            NOT NULL DEFAULT 0,
    view_count      BIGINT         NOT NULL DEFAULT 0,
    like_count      BIGINT         NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_collections_user ON collections(user_id);
CREATE INDEX IF NOT EXISTS idx_collections_public ON collections(is_public, created_at DESC);

CREATE TABLE IF NOT EXISTS collection_wallpapers (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    collection_id BIGINT NOT NULL,
    wallpaper_id  BIGINT NOT NULL,
    sort_order    INT    NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    UNIQUE(collection_id, wallpaper_id)
);

CREATE INDEX IF NOT EXISTS idx_cw_collection ON collection_wallpapers(collection_id, sort_order);

CREATE TABLE IF NOT EXISTS collection_likes (
    user_id       BIGINT NOT NULL,
    collection_id BIGINT NOT NULL,
    created_at    TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, collection_id)
);

CREATE TABLE IF NOT EXISTS wallpaper_events (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    wallpaper_id BIGINT       NOT NULL,
    event_type   VARCHAR(20)  NOT NULL,
    variant_id   BIGINT,
    user_id      BIGINT       NOT NULL DEFAULT 0,
    client       VARCHAR(32)  NOT NULL DEFAULT '',
    ip           VARCHAR(64)  NOT NULL DEFAULT '',
    user_agent   VARCHAR(512) NOT NULL DEFAULT '',
    referrer     VARCHAR(512) NOT NULL DEFAULT '',
    session_id   VARCHAR(64)  NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);

ALTER TABLE wallpaper_events ADD COLUMN IF NOT EXISTS client     VARCHAR(32)  NOT NULL DEFAULT '';
ALTER TABLE wallpaper_events ADD COLUMN IF NOT EXISTS ip         VARCHAR(64)  NOT NULL DEFAULT '';
ALTER TABLE wallpaper_events ADD COLUMN IF NOT EXISTS user_agent VARCHAR(512) NOT NULL DEFAULT '';
ALTER TABLE wallpaper_events ADD COLUMN IF NOT EXISTS referrer   VARCHAR(512) NOT NULL DEFAULT '';
ALTER TABLE wallpaper_events ADD COLUMN IF NOT EXISTS session_id VARCHAR(64)  NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_we_wallpaper_type ON wallpaper_events(wallpaper_id, event_type);
CREATE INDEX IF NOT EXISTS idx_we_created ON wallpaper_events(created_at);
CREATE INDEX IF NOT EXISTS idx_we_wallpaper_created ON wallpaper_events(wallpaper_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_we_user ON wallpaper_events(user_id) WHERE user_id <> 0;
CREATE INDEX IF NOT EXISTS idx_we_client ON wallpaper_events(client) WHERE client <> '';

CREATE TABLE IF NOT EXISTS login_logs (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT       NOT NULL,
    client     VARCHAR(32)  NOT NULL DEFAULT '',
    ip         VARCHAR(64)  NOT NULL DEFAULT '',
    user_agent VARCHAR(512) NOT NULL DEFAULT '',
    country    VARCHAR(8)   NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_login_logs_created ON login_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_logs_user ON login_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_logs_client ON login_logs(client) WHERE client <> '';

ALTER TABLE wallpaper_variants ADD COLUMN IF NOT EXISTS download_count BIGINT NOT NULL DEFAULT 0;
-- Lazy variants are materialized on first download and reclaimed by cmd/variantgc
-- once cold. last_downloaded_at drives that TTL sweep (NULL = never served).
ALTER TABLE wallpaper_variants ADD COLUMN IF NOT EXISTS last_downloaded_at TIMESTAMPTZ(6);
CREATE INDEX IF NOT EXISTS idx_variants_last_downloaded ON wallpaper_variants(last_downloaded_at);

ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS slug VARCHAR(160) NOT NULL DEFAULT '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_wallpapers_slug ON wallpapers(slug) WHERE slug != '';

ALTER TABLE collections ADD COLUMN IF NOT EXISTS slug VARCHAR(160) NOT NULL DEFAULT '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_collections_slug ON collections(slug) WHERE slug != '';

-- Low-quality 480p preview clip for video wallpapers (detail-page playback);
-- original_url stays the download-quality transcode. Empty for images.
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS preview_video_url VARCHAR(512) NOT NULL DEFAULT '';
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS is_dynamic BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS dynamic_type VARCHAR(16) NOT NULL DEFAULT '';
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS frame_urls TEXT NOT NULL DEFAULT '';

ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS phash BIGINT NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_wallpapers_phash ON wallpapers(phash) WHERE phash <> 0 AND status = 1;

-- LLM-assigned quality assessment. Empty string = unassessed; "ok" = passed
-- review; anything else is a moderation hint for the admin queue.
-- Notes hold a one-line reason from the model for the flag.
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS quality_flag  VARCHAR(32) NOT NULL DEFAULT '';
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS quality_notes TEXT        NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_wallpapers_quality_flag ON wallpapers(quality_flag) WHERE quality_flag <> '' AND quality_flag <> 'ok';

-- Weekly Picks (the "Friday Drop") — 10 hand-picked wallpapers per ISO
-- week, surfaced on the new Home page. The table doubles as the archive
-- so a wallpaper that's appeared in any past pick can be excluded from
-- future ones.
CREATE TABLE IF NOT EXISTS weekly_picks (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    year         SMALLINT NOT NULL,
    week         SMALLINT NOT NULL,
    wallpaper_id BIGINT   NOT NULL,
    sort_order   INT      NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    UNIQUE (year, week, wallpaper_id)
);
CREATE INDEX IF NOT EXISTS idx_weekly_picks_yw         ON weekly_picks(year DESC, week DESC, sort_order);
CREATE INDEX IF NOT EXISTS idx_weekly_picks_wallpaper  ON weekly_picks(wallpaper_id);

-- One pick per (year, week) may be designated the "hero" — the wallpaper
-- that drives the home page's big top image. The original_url is only
-- exposed for that single hero pick; other picks return original_url=''
-- so the public surface still gates full-resolution downloads behind
-- the coin economy. Partial unique index enforces at most one hero per
-- week; when no row is flagged, the repo falls back to sort_order=0.
ALTER TABLE weekly_picks ADD COLUMN IF NOT EXISTS is_hero BOOLEAN NOT NULL DEFAULT FALSE;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_weekly_picks_hero
    ON weekly_picks(year, week) WHERE is_hero = TRUE;

-- Collections kind: 0 = user-owned (existing rows + UI default), 1 = editor
-- weekly theme collection (auto-generated by cmd/weekly-drop, displayed
-- on the new Home page). Future kinds reserve 2+ without breaking the
-- enum.
ALTER TABLE collections ADD COLUMN IF NOT EXISTS kind         SMALLINT NOT NULL DEFAULT 0;
ALTER TABLE collections ADD COLUMN IF NOT EXISTS year         SMALLINT NOT NULL DEFAULT 0;
ALTER TABLE collections ADD COLUMN IF NOT EXISTS week         SMALLINT NOT NULL DEFAULT 0;
-- Per-collection accent color (OKLCH string, e.g. "oklch(0.65 0.18 35)").
-- Themed weekly collections set this from Claude's per-theme palette
-- proposal so the front-end can tint each week's hero / archive entry
-- in a color that matches the editorial theme. User-created (kind=0)
-- collections leave it empty and render with the default ink accent.
ALTER TABLE collections ADD COLUMN IF NOT EXISTS accent_color VARCHAR(64) NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_collections_kind_created ON collections(kind, created_at DESC) WHERE kind <> 0;

CREATE TABLE IF NOT EXISTS reports (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    wallpaper_id     BIGINT       NOT NULL,
    reporter_user_id BIGINT       NOT NULL,
    reason           VARCHAR(32)  NOT NULL,
    note             TEXT         NOT NULL DEFAULT '',
    status           SMALLINT     NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    UNIQUE (wallpaper_id, reporter_user_id, reason)
);
CREATE INDEX IF NOT EXISTS idx_reports_wallpaper ON reports(wallpaper_id);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status, created_at);

-- External marketing integrations. Tokens are stored server-side and never
-- exposed through the admin API; provider is unique because each provider is
-- represented by one official account for now.
CREATE TABLE IF NOT EXISTS external_integrations (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    provider      VARCHAR(32)  NOT NULL UNIQUE,
    account_id    VARCHAR(128) NOT NULL DEFAULT '',
    account_name  VARCHAR(256) NOT NULL DEFAULT '',
    access_token  TEXT         NOT NULL DEFAULT '',
    refresh_token TEXT         NOT NULL DEFAULT '',
    scopes        TEXT         NOT NULL DEFAULT '',
    token_type    VARCHAR(32)  NOT NULL DEFAULT '',
    expires_at    TIMESTAMPTZ(6),
    metadata      TEXT         NOT NULL DEFAULT '{}',
    created_at    TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_external_integrations_provider ON external_integrations(provider);

CREATE TABLE IF NOT EXISTS pinterest_pin_posts (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    wallpaper_id BIGINT       NOT NULL,
    board_id     VARCHAR(128) NOT NULL DEFAULT '',
    board_name   VARCHAR(256) NOT NULL DEFAULT '',
    pin_id       VARCHAR(128) NOT NULL DEFAULT '',
    pin_url      VARCHAR(512) NOT NULL DEFAULT '',
    status       VARCHAR(32)  NOT NULL DEFAULT 'posted',
    message      TEXT         NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    UNIQUE (wallpaper_id)
);
CREATE INDEX IF NOT EXISTS idx_pinterest_pin_posts_created ON pinterest_pin_posts(created_at DESC);

CREATE TABLE IF NOT EXISTS reddit_weekly_posts (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    year          SMALLINT     NOT NULL,
    week          SMALLINT     NOT NULL,
    collection_id BIGINT       NOT NULL DEFAULT 0,
    subreddit     VARCHAR(128) NOT NULL DEFAULT '',
    post_id       VARCHAR(128) NOT NULL DEFAULT '',
    post_url      VARCHAR(512) NOT NULL DEFAULT '',
    title         VARCHAR(300) NOT NULL DEFAULT '',
    body          TEXT         NOT NULL DEFAULT '',
    status        VARCHAR(32)  NOT NULL DEFAULT 'posted',
    message       TEXT         NOT NULL DEFAULT '',
    created_at    TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    UNIQUE (year, week)
);
CREATE INDEX IF NOT EXISTS idx_reddit_weekly_posts_created ON reddit_weekly_posts(created_at DESC);

CREATE TABLE IF NOT EXISTS analytics_events (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id VARCHAR(64)  NOT NULL,
    user_id    BIGINT       NOT NULL DEFAULT 0,
    event_type VARCHAR(64)  NOT NULL,
    path       VARCHAR(512) NOT NULL DEFAULT '',
    referrer   VARCHAR(512) NOT NULL DEFAULT '',
    user_agent VARCHAR(512) NOT NULL DEFAULT '',
    ip         VARCHAR(64)  NOT NULL DEFAULT '',
    props      JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_analytics_events_type_created ON analytics_events(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_analytics_events_user ON analytics_events(user_id) WHERE user_id <> 0;
CREATE INDEX IF NOT EXISTS idx_analytics_events_session ON analytics_events(session_id);

-- AI-generated wallpaper marker. Set by the cmd/aigen publish path
-- (with source=ai on the upload form). Indexed partial so the future
-- "AI-generated" filter / badge lookup is cheap even as the catalog
-- grows.
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS is_ai_generated BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_wallpapers_ai ON wallpapers(is_ai_generated) WHERE is_ai_generated = true;

-- Admin review queue. New uploads land in status=5 (PendingReview) after
-- processing, and admin must approve before the wallpaper becomes
-- publicly visible. Rejection writes status=6 (Rejected) + a
-- human-readable rejection_reason that the uploader sees on their
-- "my uploads" view. Existing pre-policy rows (~900 on first
-- deployment) keep status=1 (Published); only NEW uploads after this
-- migration enter the queue.
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS rejection_reason VARCHAR(280) NOT NULL DEFAULT '';
-- Partial index keeps the review-queue list query cheap as the table
-- grows: the queue only needs rows in status=5.
CREATE INDEX IF NOT EXISTS idx_wallpapers_review_queue ON wallpapers(created_at DESC) WHERE status = 5;

-- Per-call ledger for Anthropic Claude API usage. We can't query the
-- Admin API without an Org Owner Admin key, so instead the LLM client
-- records token usage + computed USD cost after every successful call.
-- The dashboard aggregates this for the running 7d / 30d spend view.
CREATE TABLE IF NOT EXISTS llm_usage (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purpose               VARCHAR(64)   NOT NULL,     -- "autotag", "qcheck", "weekly_theme", etc.
    model                 VARCHAR(64)   NOT NULL,
    input_tokens          INTEGER       NOT NULL DEFAULT 0,
    output_tokens         INTEGER       NOT NULL DEFAULT 0,
    cache_read_tokens     INTEGER       NOT NULL DEFAULT 0,
    cache_creation_tokens INTEGER       NOT NULL DEFAULT 0,
    cost_usd              NUMERIC(12,6) NOT NULL DEFAULT 0,  -- computed at insert
    created_at            TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_llm_usage_created_at ON llm_usage(created_at DESC);

-- ISO-3166 alpha-2 derived from the CF-IPCountry header at insert time.
-- 8 chars is enough for the standard 2-letter code (defensive — CF
-- occasionally emits "XX"/"T1" for tor/unknown).
ALTER TABLE analytics_events ADD COLUMN IF NOT EXISTS country VARCHAR(8) NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_analytics_events_created_country
  ON analytics_events(created_at DESC) WHERE country <> '';

ALTER TABLE users ADD COLUMN IF NOT EXISTS coins BIGINT NOT NULL DEFAULT 0;

INSERT INTO users (id, username, email, password_hash, nickname, coins, status)
OVERRIDING SYSTEM VALUE
VALUES (0, '__system__', 'system@internal', '', 'System', 0, 0)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS coin_transactions (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      BIGINT       NOT NULL,
    amount       BIGINT       NOT NULL,
    balance      BIGINT       NOT NULL,
    tx_type      VARCHAR(32)  NOT NULL,
    ref_id       BIGINT       NOT NULL DEFAULT 0,
    description  VARCHAR(256) NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coin_tx_user ON coin_transactions(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS user_downloads (
    user_id      BIGINT NOT NULL,
    wallpaper_id BIGINT NOT NULL,
    created_at   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, wallpaper_id)
);

CREATE INDEX IF NOT EXISTS idx_user_downloads_user ON user_downloads(user_id, created_at DESC);

INSERT INTO categories (name, slug, sort_order) VALUES
    ('Nature',   'nature',   1),
    ('City',     'city',     2),
    ('Anime',    'anime',    3),
    ('Abstract', 'abstract', 4),
    ('Minimal',  'minimal',  5),
    ('Tech',     'tech',     6),
    ('Animal',   'animal',   7),
    ('Space',    'space',    8),
    ('Game',     'game',     9),
    ('Other',    'other',    10)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO device_profiles (platform, brand, name, width, height, ppi, sort_order) VALUES
    -- Desktop Monitors
    ('desktop', 'Generic',   'Full HD (1080p)',             1920,  1080,  96,   100),
    ('desktop', 'Generic',   'QHD / 2K',                   2560,  1440,  109,  101),
    ('desktop', 'Generic',   '4K UHD',                     3840,  2160,  163,  102),
    ('desktop', 'Generic',   '5K',                         5120,  2880,  218,  103),
    ('desktop', 'Generic',   'Ultrawide QHD (21:9)',       3440,  1440,  109,  110),
    ('desktop', 'Generic',   'Super Ultrawide (32:9)',     5120,  1440,  109,  111),
    ('desktop', 'Generic',   'Ultrawide FHD (21:9)',       2560,  1080,  96,   112),

    -- MacBook
    ('laptop',  'Apple',     'MacBook Air 13"',            2560,  1600,  227,  200),
    ('laptop',  'Apple',     'MacBook Air 15"',            2880,  1864,  224,  201),
    ('laptop',  'Apple',     'MacBook Pro 14"',            3024,  1964,  254,  202),
    ('laptop',  'Apple',     'MacBook Pro 16"',            3456,  2234,  254,  203),

    -- Windows Laptop
    ('laptop',  'Generic',   'Laptop FHD (1080p)',         1920,  1080,  141,  210),
    ('laptop',  'Generic',   'Laptop QHD (2K)',            2560,  1440,  189,  211),
    ('laptop',  'Microsoft', 'Surface Laptop (13.8")',     2304,  1536,  201,  212),
    ('laptop',  'Microsoft', 'Surface Laptop (15")',       2496,  1664,  201,  213),

    -- iPad
    ('tablet',  'Apple',     'iPad Pro 13" (M4)',          2752,  2064,  264,  300),
    ('tablet',  'Apple',     'iPad Pro 11" (M4)',          2420,  1668,  264,  301),
    ('tablet',  'Apple',     'iPad Air 13" (M3)',          2732,  2048,  264,  302),
    ('tablet',  'Apple',     'iPad Air 11" (M3)',          2360,  1640,  264,  303),
    ('tablet',  'Apple',     'iPad mini (A17)',            2266,  1488,  326,  304),
    ('tablet',  'Apple',     'iPad 10th Gen',              2360,  1640,  264,  305),

    -- Android Tablet
    ('tablet',  'Samsung',   'Galaxy Tab S10 Ultra',       2960,  1848,  239,  310),
    ('tablet',  'Samsung',   'Galaxy Tab S10+',            2800,  1752,  266,  311),
    ('tablet',  'Samsung',   'Galaxy Tab S10',             2560,  1600,  276,  312),

    -- iPhone
    ('phone',   'Apple',     'iPhone 16 Pro Max',          1320,  2868,  460,  400),
    ('phone',   'Apple',     'iPhone 16 Pro',              1206,  2622,  460,  401),
    ('phone',   'Apple',     'iPhone 16 / 16e',            1179,  2556,  460,  402),
    ('phone',   'Apple',     'iPhone 15 / 14 Pro',         1179,  2556,  460,  403),
    ('phone',   'Apple',     'iPhone SE 4',                1179,  2556,  460,  404),
    ('phone',   'Apple',     'iPhone 14 / 13',             1170,  2532,  460,  405),

    -- Android Phone (flagship)
    ('phone',   'Samsung',   'Galaxy S25 Ultra',           1440,  3120,  505,  410),
    ('phone',   'Samsung',   'Galaxy S25 / S25+',          1080,  2340,  416,  411),
    ('phone',   'Samsung',   'Galaxy Z Fold 6 (outer)',    968,   2376,  374,  412),
    ('phone',   'Samsung',   'Galaxy Z Fold 6 (inner)',    1812,  2176,  373,  413),
    ('phone',   'Samsung',   'Galaxy Z Flip 6',            1080,  2640,  426,  414),
    ('phone',   'Google',    'Pixel 9 Pro XL',             1344,  2992,  486,  420),
    ('phone',   'Google',    'Pixel 9 Pro',                1280,  2856,  495,  421),
    ('phone',   'Google',    'Pixel 9',                    1080,  2424,  422,  422),
    ('phone',   'OnePlus',   'OnePlus 13',                 1440,  3168,  525,  430),
    ('phone',   'Xiaomi',    'Xiaomi 15 Pro',              1440,  3200,  521,  440),
    ('phone',   'Xiaomi',    'Xiaomi 15',                  1200,  2670,  460,  441),
    ('phone',   'Huawei',    'Mate 70 Pro',                1260,  2844,  458,  450)
ON CONFLICT (name) DO NOTHING;

-- ──────────────────────────────────────────────────────────────────────────
-- Admin console support
-- ──────────────────────────────────────────────────────────────────────────

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_users_is_admin ON users(is_admin) WHERE is_admin = TRUE;

-- Per-list privacy flags for the profile page. All default FALSE so existing
-- accounts start with private lists; the owner opts each one in via the
-- Profile-page toggle.
ALTER TABLE users ADD COLUMN IF NOT EXISTS likes_public     BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS favorites_public BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS downloads_public BOOLEAN NOT NULL DEFAULT FALSE;

-- Per-job lifecycle records for the Kafka workers. Workers insert a row when
-- they start processing a message and update it on completion. The admin
-- console reads from this table to show "what is the worker doing right now",
-- "what failed last", and per-job duration.
CREATE TABLE IF NOT EXISTS worker_jobs (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    worker        VARCHAR(32)  NOT NULL,          -- image | stats | phash
    topic         VARCHAR(64)  NOT NULL DEFAULT '',
    ref_id        BIGINT       NOT NULL DEFAULT 0, -- wallpaper_id (or whatever the job key is)
    status        VARCHAR(16)  NOT NULL DEFAULT 'running', -- running | done | failed | skipped
    message       TEXT         NOT NULL DEFAULT '',
    started_at    TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
    finished_at   TIMESTAMPTZ(6),
    duration_ms   INT          NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_worker_jobs_worker_started ON worker_jobs(worker, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_worker_jobs_status_started ON worker_jobs(status, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_worker_jobs_ref ON worker_jobs(ref_id) WHERE ref_id <> 0;

-- [skill: go-team-standards · 数据库设计] popular-sort partial index
-- The public "popular" list sort (repo/wallpaper.go List, sort=popular)
-- orders by like_count DESC, id DESC over status=1 rows only. A partial
-- index keeps that sort cheap as the catalog grows past the point where
-- a full scan + sort of all published rows stops being free.
CREATE INDEX IF NOT EXISTS idx_wallpapers_popular
    ON wallpapers(like_count DESC, id DESC) WHERE status = 1;

-- ── Content i18n ─────────────────────────────────────────────────────
-- Per-language overrides for user-visible text, keyed by UI language tag
-- ("en" / "zh-CN" / "zh-TW" / "ja"). The base column keeps the original
-- text; API handlers substitute the override matching Accept-Language and
-- fall back to the original. Categories are hand-translated below (fixed
-- seed data); tags and collections are backfilled offline by cmd/i18nfill.
ALTER TABLE categories  ADD COLUMN IF NOT EXISTS name_i18n        JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE tags        ADD COLUMN IF NOT EXISTS name_i18n        JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE collections ADD COLUMN IF NOT EXISTS title_i18n       JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE collections ADD COLUMN IF NOT EXISTS description_i18n JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Seed translations for the 10 fixed categories. Idempotent overwrite —
-- categories have no mutation endpoint, this block is their source of truth.
UPDATE categories c SET name_i18n = v.i18n::jsonb
FROM (VALUES
    ('nature',   '{"en":"Nature","zh-CN":"自然","zh-TW":"自然","ja":"自然"}'),
    ('city',     '{"en":"City","zh-CN":"城市","zh-TW":"城市","ja":"都市"}'),
    ('anime',    '{"en":"Anime","zh-CN":"动漫","zh-TW":"動漫","ja":"アニメ"}'),
    ('abstract', '{"en":"Abstract","zh-CN":"抽象","zh-TW":"抽象","ja":"抽象"}'),
    ('minimal',  '{"en":"Minimal","zh-CN":"极简","zh-TW":"極簡","ja":"ミニマル"}'),
    ('tech',     '{"en":"Tech","zh-CN":"科技","zh-TW":"科技","ja":"テック"}'),
    ('animal',   '{"en":"Animal","zh-CN":"动物","zh-TW":"動物","ja":"動物"}'),
    ('space',    '{"en":"Space","zh-CN":"太空","zh-TW":"太空","ja":"宇宙"}'),
    ('game',     '{"en":"Game","zh-CN":"游戏","zh-TW":"遊戲","ja":"ゲーム"}'),
    ('other',    '{"en":"Other","zh-CN":"其他","zh-TW":"其他","ja":"その他"}')
) AS v(slug, i18n)
WHERE c.slug = v.slug;
