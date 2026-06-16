package com.wallpaperexchange.android

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale

class ApiException(message: String, val status: Int = 0) : Exception(message)

object ApiClient {
    private const val BASE_URL = "https://wallpaperexchange.com/api/v1"

    suspend fun fetchWallpapers(
        cursor: Int? = null,
        limit: Int = 24,
        aiOnly: Boolean = false,
        categoryId: Int? = null,
        sort: String? = null,
    ): Page<Wallpaper> {
        val params = mutableMapOf(
            "limit" to limit.toString(),
            "exclude_video" to "true",
            "exclude_dynamic" to "true",
        )
        cursor?.let { params["cursor"] = it.toString() }
        if (aiOnly) params["ai_only"] = "true"
        categoryId?.let { params["category_id"] = it.toString() }
        sort?.let { params["sort"] = it }
        return page("/wallpapers", params) { it.toWallpaper() }
    }

    suspend fun fetchCategories(): List<Category> =
        arrayData("/categories").objects().map { it.toCategory() }

    suspend fun fetchWallpaperDetail(slug: String): WallpaperDetail =
        objectData("/wallpapers/$slug").toWallpaperDetail()

    suspend fun fetchSimilarWallpapers(id: Int, limit: Int = 12): List<Wallpaper> =
        arrayData(
            "/wallpapers/$id/similar",
            mapOf("limit" to limit.toString(), "exclude_video" to "true", "exclude_dynamic" to "true"),
        ).objects().map { it.toWallpaper() }.filter { it.isUsableOnAndroid }

    suspend fun fetchForYou(token: String, limit: Int = 30): List<Wallpaper> =
        arrayData(
            "/wallpapers/for-you",
            mapOf("limit" to limit.toString(), "exclude_video" to "true", "exclude_dynamic" to "true"),
            token,
        ).objects().map { it.toWallpaper() }.filter { it.isUsableOnAndroid }

    suspend fun fetchCollections(cursor: Int? = null, limit: Int = 24): Page<CollectionItem> {
        val params = mutableMapOf("limit" to limit.toString())
        cursor?.let { params["cursor"] = it.toString() }
        return page("/collections", params) { it.toCollectionItem() }
    }

    suspend fun fetchCollection(slug: String): CollectionItem =
        objectData("/collections/$slug").toCollectionItem()

    suspend fun fetchCollectionWallpapers(id: Int, cursor: Int? = null, limit: Int = 24): Page<Wallpaper> {
        val params = mutableMapOf(
            "limit" to limit.toString(),
            "exclude_video" to "true",
            "exclude_dynamic" to "true",
        )
        cursor?.let { params["cursor"] = it.toString() }
        return page("/collections/$id/wallpapers", params) { it.toWallpaper() }
    }

    suspend fun fetchWeeklyArchive(limit: Int = 50): List<WeeklyArchiveEntry> =
        arrayData("/weekly-picks/archive", mapOf("limit" to limit.toString()))
            .objects()
            .map { it.toWeeklyArchiveEntry() }

    suspend fun fetchWeeklyByWeek(year: Int, week: Int): List<WeeklyPicked> =
        objectData("/weekly-picks/$year/$week")
            .optJSONArray("picks")
            ?.objects()
            ?.map { it.toWeeklyPicked() }
            ?.filter { it.wallpaper.isUsableOnAndroid }
            .orEmpty()

    suspend fun fetchFavorites(token: String, cursor: Int? = null, limit: Int = 24): Page<Wallpaper> {
        val params = wallpaperPageParams(limit)
        cursor?.let { params["cursor"] = it.toString() }
        return page("/users/me/favorites", params, token) { it.toWallpaper() }
    }

    suspend fun fetchLikes(token: String, cursor: Int? = null, limit: Int = 24): Page<Wallpaper> {
        val params = wallpaperPageParams(limit)
        cursor?.let { params["cursor"] = it.toString() }
        return page("/users/me/likes", params, token) { it.toWallpaper() }
    }

    suspend fun fetchDownloads(token: String, cursor: Int? = null, limit: Int = 24): Page<Wallpaper> {
        val params = wallpaperPageParams(limit)
        cursor?.let { params["cursor"] = it.toString() }
        return page("/users/me/downloads", params, token) { it.toWallpaper() }
    }

    suspend fun fetchUserUploads(
        username: String,
        token: String,
        cursor: Int? = null,
        limit: Int = 24,
        status: String = "1,2,4,6",
    ): Page<Wallpaper> {
        val params = wallpaperPageParams(limit)
        params["status"] = status
        cursor?.let { params["cursor"] = it.toString() }
        return page("/users/${encodePath(username)}/wallpapers", params, token) { it.toWallpaper() }
    }

    suspend fun fetchUserCollections(username: String, token: String, cursor: Int? = null, limit: Int = 20): Page<CollectionItem> {
        val params = mutableMapOf("limit" to limit.toString())
        cursor?.let { params["cursor"] = it.toString() }
        return page("/users/${encodePath(username)}/collections", params, token) { it.toCollectionItem() }
    }

    suspend fun fetchCoins(token: String): Int =
        objectData("/users/me/coins", token = token).optInt("coins")

    suspend fun fetchCoinTransactions(token: String, cursor: Int? = null, limit: Int = 30): Page<CoinTransaction> {
        val params = mutableMapOf("limit" to limit.toString())
        cursor?.let { params["cursor"] = it.toString() }
        return page("/users/me/coin-transactions", params, token) { it.toCoinTransaction() }
    }

    suspend fun fetchProfile(token: String): User =
        objectData("/users/me", token = token).toUser()

    suspend fun updateProfile(nickname: String, bio: String, token: String): User =
        objectData(
            "/users/me/profile",
            token = token,
            method = "PUT",
            body = JSONObject().put("nickname", nickname).put("bio", bio),
        ).toUser()

    suspend fun changePassword(oldPassword: String, newPassword: String, token: String) {
        request(
            "/users/me/password",
            token = token,
            method = "PUT",
            body = JSONObject().put("old_password", oldPassword).put("new_password", newPassword),
        )
    }

    suspend fun login(email: String, password: String): AuthPayload =
        auth("/auth/login", JSONObject().put("email", email).put("password", password))

    suspend fun register(username: String, email: String, password: String): AuthPayload =
        auth("/auth/register", JSONObject().put("username", username).put("email", email).put("password", password))

    suspend fun like(id: Int, token: String) {
        request("/wallpapers/$id/like", method = "POST", token = token)
    }

    suspend fun unlike(id: Int, token: String) {
        request("/wallpapers/$id/like", method = "DELETE", token = token)
    }

    suspend fun favorite(id: Int, token: String) {
        request("/wallpapers/$id/favorite", method = "POST", token = token)
    }

    suspend fun unfavorite(id: Int, token: String) {
        request("/wallpapers/$id/favorite", method = "DELETE", token = token)
    }

    fun downloadEndpoint(id: Int): String = "$BASE_URL/wallpapers/$id/download"

    fun uploadEndpoint(): String = "$BASE_URL/wallpapers"

    private suspend fun auth(path: String, body: JSONObject): AuthPayload {
        val data = objectData(path, method = "POST", body = body)
        return AuthPayload(
            token = data.optString("token"),
            user = data.getJSONObject("user").toUser(),
        )
    }

    private suspend fun objectData(
        path: String,
        params: Map<String, String> = emptyMap(),
        token: String? = null,
        method: String = "GET",
        body: JSONObject? = null,
    ): JSONObject = request(path, params, token, method, body).getJSONObject("data")

    private suspend fun arrayData(
        path: String,
        params: Map<String, String> = emptyMap(),
        token: String? = null,
    ) = request(path, params, token).getJSONArray("data")

    private suspend fun <T> page(
        path: String,
        params: Map<String, String>,
        token: String? = null,
        parse: (JSONObject) -> T,
    ): Page<T> {
        val data = objectData(path, params, token)
        return Page(
            items = data.optJSONArray("items")?.objects()?.map(parse).orEmpty(),
            nextCursor = data.intOrNull("next_cursor"),
            hasMore = data.optBoolean("has_more"),
            total = data.intOrNull("total"),
        )
    }

    private suspend fun request(
        path: String,
        params: Map<String, String> = emptyMap(),
        token: String? = null,
        method: String = "GET",
        body: JSONObject? = null,
    ): JSONObject = withContext(Dispatchers.IO) {
        val url = URL(BASE_URL + path + query(params))
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15000
            readTimeout = 30000
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Accept-Language", Locale.getDefault().toLanguageTag())
            token?.let { setRequestProperty("Authorization", "Bearer $it") }
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        if (body != null) {
            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { it.write(body.toString()) }
        }
        val status = connection.responseCode
        val stream = if (status >= 400) connection.errorStream else connection.inputStream
        val text = stream?.use { input ->
            BufferedReader(InputStreamReader(input, Charsets.UTF_8)).readText()
        }.orEmpty()
        val json = if (text.isBlank()) JSONObject().put("data", JSONObject()) else JSONObject(text)
        if (status >= 400) {
            throw ApiException(json.optString("message").ifBlank { "Request failed" }, status)
        }
        json
    }

    private fun query(params: Map<String, String>): String {
        if (params.isEmpty()) return ""
        return params.entries.joinToString(prefix = "?", separator = "&") { (key, value) ->
            "${encode(key)}=${encode(value)}"
        }
    }

    private fun encode(value: String): String =
        URLEncoder.encode(value, Charsets.UTF_8.name())

    private fun encodePath(value: String): String =
        encode(value).replace("+", "%20")

    private fun wallpaperPageParams(limit: Int): MutableMap<String, String> =
        mutableMapOf(
            "limit" to limit.toString(),
            "exclude_video" to "true",
            "exclude_dynamic" to "true",
        )
}
