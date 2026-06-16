package com.wallpaperexchange.android

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.LruCache
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URL

private object ImageMemoryCache {
    private val cache = object : LruCache<String, ImageBitmap>(72) {}

    fun get(url: String?): ImageBitmap? =
        url?.takeIf { it.isNotBlank() }?.let { cache.get(it) }

    fun put(url: String?, bitmap: ImageBitmap) {
        url?.takeIf { it.isNotBlank() }?.let { cache.put(it, bitmap) }
    }
}

@Composable
fun RemoteImage(
    url: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    placeholder: Color? = null,
    fallbackUrl: String? = null,
    cacheTarget: Boolean = true,
) {
    val context = LocalContext.current
    val scheme = LocalArchiveScheme.current
    val fill = placeholder ?: scheme.paper3
    var bitmap by remember(url, fallbackUrl, cacheTarget) {
        mutableStateOf((if (cacheTarget) ImageMemoryCache.get(url) else null) ?: ImageMemoryCache.get(fallbackUrl))
    }
    var loading by remember(url, fallbackUrl, cacheTarget) {
        mutableStateOf(!url.isNullOrBlank() && (if (cacheTarget) ImageMemoryCache.get(url) else null) == null)
    }

    LaunchedEffect(url, fallbackUrl, cacheTarget) {
        val cachedTarget = if (cacheTarget) ImageMemoryCache.get(url) else null
        val cachedFallback = ImageMemoryCache.get(fallbackUrl)
        bitmap = cachedTarget ?: cachedFallback
        loading = !url.isNullOrBlank() && cachedTarget == null

        if (url.isNullOrBlank() || cachedTarget != null) {
            loading = false
            return@LaunchedEffect
        }

        if (
            bitmap == null &&
            !fallbackUrl.isNullOrBlank() &&
            fallbackUrl != url
        ) {
            loadAndCache(context, fallbackUrl)?.let { bitmap = it }
        }

        val targetBitmap = if (cacheTarget) loadAndCache(context, url) else loadBitmap(context, url)
        targetBitmap?.let { bitmap = it }
        loading = false
    }

    Box(modifier.background(fill)) {
        bitmap?.let {
            Image(
                bitmap = it,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = contentScale,
            )
        }
        AnimatedVisibility(loading && bitmap == null) {
            LoadingVeil(Modifier.fillMaxSize())
        }
    }
}

@Composable
fun LoadingVeil(modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "image-loading")
    val sweep by transition.animateFloat(
        initialValue = -0.8f,
        targetValue = 1.8f,
        animationSpec = infiniteRepeatable(tween(1200), RepeatMode.Restart),
        label = "image-loading-sweep",
    )
    Box(
        modifier
            .alpha(0.55f)
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        Color.White.copy(alpha = 0.02f),
                        Color.White.copy(alpha = 0.30f),
                        Color.White.copy(alpha = 0.04f),
                    ),
                    start = Offset(sweep * 420f, 0f),
                    end = Offset(sweep * 420f + 260f, 520f),
                ),
            ),
    )
}

private suspend fun loadAndCache(context: Context, url: String): ImageBitmap? {
    ImageMemoryCache.get(url)?.let { return it }
    return loadBitmap(context, url)?.also { ImageMemoryCache.put(url, it) }
}

private suspend fun loadBitmap(context: Context, url: String) = withContext(Dispatchers.IO) {
    runCatching {
        val stream = if (url.startsWith("content://")) {
            context.contentResolver.openInputStream(Uri.parse(url))
        } else {
            URL(url).openStream()
        }
        stream?.use { BitmapFactory.decodeStream(it)?.asImageBitmap() }
    }.getOrNull()
}
