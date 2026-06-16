package com.wallpaperexchange.android

import org.json.JSONArray
import org.json.JSONObject

data class Page<T>(
    val items: List<T>,
    val nextCursor: Int?,
    val hasMore: Boolean,
    val total: Int? = null,
)

data class User(
    val id: Int,
    val username: String,
    val email: String?,
    val nickname: String,
    val avatarUrl: String,
    val bio: String,
    val coins: Int,
)

data class AuthPayload(
    val token: String,
    val user: User,
)

data class Category(
    val id: Int,
    val name: String,
    val slug: String,
)

data class Wallpaper(
    val id: Int,
    val slug: String,
    val userId: Int,
    val categoryId: Int?,
    val title: String,
    val description: String,
    val originalUrl: String,
    val thumbUrl: String,
    val previewUrl: String,
    val width: Int,
    val height: Int,
    val fileSize: Long,
    val fileType: String,
    val dominantColor: String?,
    val colorPalette: String?,
    val viewCount: Int,
    val likeCount: Int,
    val downloadCount: Int,
    val favoriteCount: Int,
    val isDynamic: Boolean,
    val isAiGenerated: Boolean,
    val isLiked: Boolean,
    val isFavorited: Boolean,
    val isDownloaded: Boolean,
    val status: Int,
    val createdAt: String,
) {
    val displayUrl: String
        get() = previewUrl.ifBlank { thumbUrl }

    val resolutionLabel: String
        get() {
            val px = maxOf(width, height)
            return when {
                px >= 7680 -> "8K"
                px >= 3840 -> "4K"
                px >= 2560 -> "2K"
                px >= 1920 -> "1080P"
                px >= 1280 -> "720P"
                px > 0 -> "${width}x${height}"
                else -> "HD"
            }
        }

    val isUsableOnAndroid: Boolean
        get() = !isDynamic && !fileType.startsWith("video/")
}

data class WallpaperDetail(
    val wallpaper: Wallpaper,
    val tags: List<Tag>,
    val uploader: WallpaperUploader?,
)

data class Tag(
    val id: Int,
    val name: String,
    val slug: String?,
)

data class WallpaperUploader(
    val id: Int,
    val username: String,
    val nickname: String?,
    val avatarUrl: String?,
    val bio: String?,
)

data class CollectionTile(
    val thumbUrl: String,
    val previewUrl: String,
    val dominantColor: String?,
)

data class CollectionItem(
    val id: Int,
    val slug: String,
    val title: String,
    val coverUrl: String?,
    val wallpaperCount: Int,
    val recentTiles: List<CollectionTile>,
    val kind: Int,
    val accentColor: String?,
    val description: String?,
    val likeCount: Int,
)

data class WeeklyArchiveEntry(
    val year: Int,
    val week: Int,
    val count: Int,
    val coverUrl: String,
    val accentColor: String?,
    val dominantColor: String?,
    val colorPalette: String?,
) {
    val id: String = "$year-$week"
}

data class WeeklyPicked(
    val wallpaper: Wallpaper,
    val sortOrder: Int,
    val isHero: Boolean,
)

data class CoinTransaction(
    val id: Int,
    val amount: Int,
    val balance: Int,
    val txType: String,
    val description: String,
    val createdAt: String,
)

data class AndroidRelease(
    val versionName: String,
    val versionCode: Int,
    val minimumVersionCode: Int,
    val apkUrl: String,
    val apkSha256: String?,
    val releasedAt: String,
    val notes: List<String>,
    val notesI18n: Map<String, List<String>>,
) {
    val forceUpdate: Boolean
        get() = BuildConfig.VERSION_CODE < minimumVersionCode
}

internal fun JSONObject.stringOrNull(name: String): String? =
    if (isNull(name)) null else optString(name).trim().takeIf { it.isNotEmpty() }

internal fun JSONObject.intOrNull(name: String): Int? =
    if (isNull(name) || !has(name)) null else optInt(name)

internal fun JSONArray.objects(): List<JSONObject> =
    (0 until length()).mapNotNull { optJSONObject(it) }

internal fun JSONObject.toUser(): User = User(
    id = optInt("id"),
    username = optString("username"),
    email = stringOrNull("email"),
    nickname = optString("nickname").ifBlank { optString("username") },
    avatarUrl = optString("avatar_url"),
    bio = optString("bio"),
    coins = optInt("coins"),
)

internal fun JSONObject.toWallpaper(): Wallpaper = Wallpaper(
    id = optInt("id"),
    slug = optString("slug"),
    userId = optInt("user_id"),
    categoryId = intOrNull("category_id"),
    title = optString("title").ifBlank { "Untitled" },
    description = optString("description"),
    originalUrl = optString("original_url"),
    thumbUrl = optString("thumb_url"),
    previewUrl = optString("preview_url"),
    width = optInt("width"),
    height = optInt("height"),
    fileSize = optLong("file_size"),
    fileType = optString("file_type"),
    dominantColor = stringOrNull("dominant_color"),
    colorPalette = stringOrNull("color_palette"),
    viewCount = optInt("view_count"),
    likeCount = optInt("like_count"),
    downloadCount = optInt("download_count"),
    favoriteCount = optInt("favorite_count"),
    isDynamic = optBoolean("is_dynamic"),
    isAiGenerated = optBoolean("is_ai_generated"),
    isLiked = optBoolean("is_liked"),
    isFavorited = optBoolean("is_favorited"),
    isDownloaded = optBoolean("is_downloaded"),
    status = optInt("status", 1),
    createdAt = optString("created_at"),
)

internal fun JSONObject.toWallpaperDetail(): WallpaperDetail = WallpaperDetail(
    wallpaper = toWallpaper(),
    tags = optJSONArray("tags")?.objects()?.map {
        Tag(
            id = it.optInt("id"),
            name = it.optString("name"),
            slug = it.stringOrNull("slug"),
        )
    }.orEmpty(),
    uploader = optJSONObject("uploader")?.let {
        WallpaperUploader(
            id = it.optInt("id"),
            username = it.optString("username"),
            nickname = it.stringOrNull("nickname"),
            avatarUrl = it.stringOrNull("avatar_url"),
            bio = it.stringOrNull("bio"),
        )
    },
)

internal fun JSONObject.toCategory(): Category = Category(
    id = optInt("id"),
    name = optString("name"),
    slug = optString("slug"),
)

internal fun JSONObject.toCollectionTile(): CollectionTile = CollectionTile(
    thumbUrl = optString("thumb_url"),
    previewUrl = optString("preview_url"),
    dominantColor = stringOrNull("dominant_color"),
)

internal fun JSONObject.toCollectionItem(): CollectionItem = CollectionItem(
    id = optInt("id"),
    slug = optString("slug"),
    title = optString("title").ifBlank { "Untitled" },
    coverUrl = stringOrNull("cover_url"),
    wallpaperCount = optInt("wallpaper_count"),
    recentTiles = optJSONArray("recent_tiles")?.objects()?.map { it.toCollectionTile() }.orEmpty(),
    kind = optInt("kind"),
    accentColor = stringOrNull("accent_color"),
    description = stringOrNull("description"),
    likeCount = optInt("like_count"),
)

internal fun JSONObject.toWeeklyArchiveEntry(): WeeklyArchiveEntry = WeeklyArchiveEntry(
    year = optInt("year"),
    week = optInt("week"),
    count = optInt("count"),
    coverUrl = optString("cover_url"),
    accentColor = stringOrNull("accent_color"),
    dominantColor = stringOrNull("dominant_color"),
    colorPalette = stringOrNull("color_palette"),
)

internal fun JSONObject.toWeeklyPicked(): WeeklyPicked = WeeklyPicked(
    wallpaper = toWallpaper(),
    sortOrder = optInt("sort_order"),
    isHero = optBoolean("is_hero"),
)

internal fun JSONObject.toCoinTransaction(): CoinTransaction = CoinTransaction(
    id = optInt("id"),
    amount = optInt("amount"),
    balance = optInt("balance"),
    txType = optString("tx_type"),
    description = optString("description"),
    createdAt = optString("created_at"),
)

internal fun JSONObject.toAndroidRelease(): AndroidRelease = AndroidRelease(
    versionName = optString("current_version"),
    versionCode = optInt("current_version_code"),
    minimumVersionCode = optInt("minimum_version_code", optInt("current_version_code")),
    apkUrl = optString("current_apk_url"),
    apkSha256 = stringOrNull("apk_sha256"),
    releasedAt = optString("released_at"),
    notes = optJSONArray("notes")?.strings().orEmpty(),
    notesI18n = optJSONObject("notes_i18n")?.toStringListMap().orEmpty(),
)

private fun JSONArray.strings(): List<String> =
    (0 until length()).mapNotNull { optString(it).takeIf { value -> value.isNotBlank() } }

private fun JSONObject.toStringListMap(): Map<String, List<String>> =
    keys().asSequence().associateWith { key ->
        optJSONArray(key)?.strings().orEmpty()
    }.filterValues { it.isNotEmpty() }
