package com.wallpaperexchange.android

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.URL

@Composable
fun RemoteImage(
    url: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
    placeholder: Color? = null,
) {
    val context = LocalContext.current
    val scheme = LocalArchiveScheme.current
    val fill = placeholder ?: scheme.paper3
    var bitmap by remember(url) { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    var loading by remember(url) { mutableStateOf(!url.isNullOrBlank()) }

    LaunchedEffect(url) {
        bitmap = null
        loading = !url.isNullOrBlank()
        if (!url.isNullOrBlank()) {
            bitmap = loadBitmap(context, url)
            loading = false
        }
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
    val alpha by transition.animateFloat(
        initialValue = 0.12f,
        targetValue = 0.32f,
        animationSpec = infiniteRepeatable(tween(1200), RepeatMode.Reverse),
        label = "image-loading-alpha",
    )
    Box(modifier.alpha(alpha).background(Color.White))
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
