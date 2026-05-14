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
    created_at   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_we_wallpaper_type ON wallpaper_events(wallpaper_id, event_type);
CREATE INDEX IF NOT EXISTS idx_we_created ON wallpaper_events(created_at);

ALTER TABLE wallpaper_variants ADD COLUMN IF NOT EXISTS download_count BIGINT NOT NULL DEFAULT 0;

ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS slug VARCHAR(160) NOT NULL DEFAULT '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_wallpapers_slug ON wallpapers(slug) WHERE slug != '';

ALTER TABLE collections ADD COLUMN IF NOT EXISTS slug VARCHAR(160) NOT NULL DEFAULT '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_collections_slug ON collections(slug) WHERE slug != '';

ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS is_dynamic BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS dynamic_type VARCHAR(16) NOT NULL DEFAULT '';
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS frame_urls TEXT NOT NULL DEFAULT '';

ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS phash BIGINT NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_wallpapers_phash ON wallpapers(phash) WHERE phash <> 0 AND status = 1;

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
    ('自然风光', 'nature', 1),
    ('城市建筑', 'city', 2),
    ('动漫插画', 'anime', 3),
    ('抽象艺术', 'abstract', 4),
    ('极简主义', 'minimal', 5),
    ('科技数码', 'tech', 6),
    ('动物萌宠', 'animal', 7),
    ('太空宇宙', 'space', 8),
    ('游戏', 'game', 9),
    ('其他', 'other', 10)
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
