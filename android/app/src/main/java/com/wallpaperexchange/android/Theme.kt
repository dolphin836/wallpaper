package com.wallpaperexchange.android

import android.view.MotionEvent
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.unit.dp

enum class AppThemeMode(val key: String) {
    System("system"),
    Light("light"),
    Dark("dark");

    companion object {
        fun fromKey(key: String?): AppThemeMode =
            entries.firstOrNull { it.key == key } ?: System
    }
}

@Stable
data class ArchiveScheme(
    val paper: Color,
    val paper2: Color,
    val paper3: Color,
    val hair: Color,
    val ink: Color,
    val ink2: Color,
    val muted: Color,
    val accent: Color,
    val accentSoft: Color,
    val accentInk: Color,
    val lightText: Color = Color(0xFFF8F6F1),
)

val LocalArchiveScheme = staticCompositionLocalOf {
    ArchiveScheme(
        paper = Color(0xFFF8F6F1),
        paper2 = Color(0xFFF2F0EB),
        paper3 = Color(0xFFEBE8E3),
        hair = Color(0xFFDEDCD8),
        ink = Color(0xFF2D2B2A),
        ink2 = Color(0xFF494745),
        muted = Color(0xFF868480),
        accent = Color(0xFFE27D48),
        accentSoft = Color(0xFFF4E8DD),
        accentInk = Color(0xFF8D4B26),
    )
}

class MeshState {
    var c1 by mutableStateOf(Color(0xFFEFC78C))
        private set
    var c2 by mutableStateOf(Color(0xFFF2BD9E))
        private set
    var c3 by mutableStateOf(Color(0xFFF5D6A8))
        private set

    fun apply(palette: String?, dominant: String?) {
        val resolved = resolvePalette(palette, dominant) ?: return
        c1 = resolved[0]
        c2 = resolved[1]
        c3 = resolved[2]
    }

    fun reset(isDark: Boolean = false) {
        c1 = if (isDark) Color(0xFF2B130D) else Color(0xFFEFC78C)
        c2 = if (isDark) Color(0xFF04151E) else Color(0xFFF2BD9E)
        c3 = if (isDark) Color(0xFF32180B) else Color(0xFFF5D6A8)
    }
}

val LocalMeshState = staticCompositionLocalOf { MeshState() }

@Composable
fun WallpaperExchangeTheme(themeMode: AppThemeMode = AppThemeMode.System, content: @Composable () -> Unit) {
    val systemDark = isSystemInDarkTheme()
    val isDark = when (themeMode) {
        AppThemeMode.System -> systemDark
        AppThemeMode.Light -> false
        AppThemeMode.Dark -> true
    }
    val scheme = if (isDark) {
        ArchiveScheme(
            paper = Color(0xFF050608),
            paper2 = Color(0xFF0C0F10),
            paper3 = Color(0xFF131618),
            hair = Color(0xFF32373A),
            ink = Color(0xFFEDF0F2),
            ink2 = Color(0xFFBAC0C3),
            muted = Color(0xFF899196),
            accent = Color(0xFFFF6F28),
            accentSoft = Color(0xFF471702),
            accentInk = Color(0xFFFFBF8D),
        )
    } else {
        LocalArchiveScheme.current
    }
    val mesh = remember { MeshState() }
    val material = if (isDark) {
        darkColorScheme(primary = scheme.accent, background = scheme.paper, surface = scheme.paper2)
    } else {
        lightColorScheme(primary = scheme.accent, background = scheme.paper, surface = scheme.paper2)
    }
    CompositionLocalProvider(LocalArchiveScheme provides scheme, LocalMeshState provides mesh) {
        MaterialTheme(colorScheme = material, content = content)
    }
}

@Composable
fun PageMesh(modifier: Modifier = Modifier) {
    val scheme = LocalArchiveScheme.current
    val mesh = LocalMeshState.current
    val c1 by animateColorAsState(mesh.c1, label = "mesh-c1")
    val c2 by animateColorAsState(mesh.c2, label = "mesh-c2")
    val c3 by animateColorAsState(mesh.c3, label = "mesh-c3")

    Box(
        modifier
            .fillMaxSize()
            .background(scheme.paper)
            .background(
                Brush.linearGradient(
                    listOf(
                        c1.copy(alpha = 0.24f),
                        c2.copy(alpha = 0.18f),
                        c3.copy(alpha = 0.22f),
                        scheme.paper.copy(alpha = 0.72f),
                    ),
                    start = Offset.Zero,
                    end = Offset(1200f, 1800f),
                )
            )
            .blur(0.3.dp)
    )
}

@Composable
fun paletteReactiveModifier(palette: String?, dominant: String?): Modifier {
    val mesh = LocalMeshState.current
    val isDark = isSystemInDarkTheme()
    return Modifier.pointerInteropFilter { event ->
        when (event.actionMasked) {
            MotionEvent.ACTION_HOVER_ENTER, MotionEvent.ACTION_HOVER_MOVE -> mesh.apply(palette, dominant)
            MotionEvent.ACTION_HOVER_EXIT -> mesh.reset(isDark)
        }
        false
    }
}

fun hexColor(raw: String?, fallback: Color): Color {
    val text = raw?.trim()?.removePrefix("#") ?: return fallback
    if (text.length != 6) return fallback
    return runCatching {
        Color(
            red = text.substring(0, 2).toInt(16),
            green = text.substring(2, 4).toInt(16),
            blue = text.substring(4, 6).toInt(16),
        )
    }.getOrDefault(fallback)
}

fun resolvePalette(palette: String?, dominant: String?): List<Color>? {
    val parts = palette
        ?.split(",")
        ?.map { it.trim() }
        ?.filter { it.isNotEmpty() }
        .orEmpty()
    if (parts.size >= 3) {
        return listOf(
            hexColor(parts.first(), Color.Unspecified),
            hexColor(parts[parts.size / 2], Color.Unspecified),
            hexColor(parts.last(), Color.Unspecified),
        ).takeIf { colors -> colors.none { it == Color.Unspecified } }
    }
    dominant?.let {
        val color = hexColor(it, Color.Unspecified)
        if (color != Color.Unspecified) return listOf(color, color, color)
    }
    return null
}

fun Color.readableOn(): Color =
    if (luminance() > 0.55f) Color.Black.copy(alpha = 0.82f) else Color.White.copy(alpha = 0.92f)
