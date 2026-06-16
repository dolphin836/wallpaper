package com.wallpaperexchange.android

import android.app.DownloadManager
import android.app.WallpaperManager
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.OpenableColumns
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.ExperimentalAnimationApi
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Paid
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PhoneIphone
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material.icons.outlined.Upload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            WallpaperExchangeTheme {
                WallpaperExchangeApp()
            }
        }
    }
}

enum class RootTab(val label: Int, val icon: ImageVector) {
    Home(R.string.home, Icons.Outlined.Home),
    Discover(R.string.discover, Icons.Outlined.GridView),
    Weekly(R.string.weekly, Icons.Outlined.CalendarMonth),
    Collections(R.string.collections, Icons.Outlined.Collections),
    Favorites(R.string.favorites, Icons.Outlined.FavoriteBorder),
}

enum class Feed { Latest, Popular, ForYou, Ai }
enum class AuthMode { Login, Register }
enum class UploadStatus { Ready, Uploading, Success, Failed }
enum class ProfileDestination(val title: Int, val icon: ImageVector) {
    Downloads(R.string.my_downloads, Icons.Outlined.Download),
    Favorites(R.string.my_favorites, Icons.Outlined.FavoriteBorder),
    Uploads(R.string.my_uploads, Icons.Outlined.Upload),
    Likes(R.string.my_likes, Icons.Outlined.ThumbUp),
    Collections(R.string.my_collections, Icons.Outlined.Collections),
    Coins(R.string.my_coins, Icons.Outlined.Paid),
}

data class AndroidUploadItem(
    val id: String = UUID.randomUUID().toString(),
    val uri: Uri,
    val name: String,
    val status: UploadStatus = UploadStatus.Ready,
)

@Stable
class LockPreviewState {
    var enabled by mutableStateOf(false)
        private set

    fun toggle() {
        enabled = !enabled
    }
}

val LocalLockPreviewState = staticCompositionLocalOf { LockPreviewState() }

@Stable
class AuthSession(context: Context) {
    private val prefs = context.getSharedPreferences("wallx_auth", Context.MODE_PRIVATE)

    var token by mutableStateOf(prefs.getString("token", null))
        private set
    var user by mutableStateOf<User?>(null)
        private set
    var authMode by mutableStateOf<AuthMode?>(null)

    val isLoggedIn: Boolean get() = !token.isNullOrBlank()

    suspend fun refreshProfile() {
        val current = token ?: return
        runCatching { ApiClient.fetchProfile(current) }
            .onSuccess { user = it }
            .onFailure { logout() }
    }

    suspend fun login(email: String, password: String) {
        val payload = ApiClient.login(email, password)
        apply(payload)
    }

    suspend fun register(username: String, email: String, password: String) {
        val payload = ApiClient.register(username, email, password)
        apply(payload)
    }

    fun present(mode: AuthMode = AuthMode.Login) {
        authMode = mode
    }

    fun dismissAuth() {
        authMode = null
    }

    fun logout() {
        prefs.edit().remove("token").apply()
        token = null
        user = null
    }

    private fun apply(payload: AuthPayload) {
        prefs.edit().putString("token", payload.token).apply()
        token = payload.token
        user = payload.user
        authMode = null
    }
}

@OptIn(ExperimentalAnimationApi::class)
@Composable
fun WallpaperExchangeApp() {
    val context = LocalContext.current
    val session = remember { AuthSession(context.applicationContext) }
    val lockPreview = remember { LockPreviewState() }
    var tab by remember { mutableStateOf(RootTab.Home) }
    var detail by remember { mutableStateOf<Wallpaper?>(null) }
    var collection by remember { mutableStateOf<CollectionItem?>(null) }
    var weekly by remember { mutableStateOf<WeeklyArchiveEntry?>(null) }
    var profileOpen by remember { mutableStateOf(false) }
    var profileDestination by remember { mutableStateOf<ProfileDestination?>(null) }
    var uploadOpen by remember { mutableStateOf(false) }

    LaunchedEffect(session.token) {
        session.refreshProfile()
    }

    CompositionLocalProvider(LocalLockPreviewState provides lockPreview) {
    Box(Modifier.fillMaxSize()) {
        PageMesh()
        Scaffold(
            containerColor = Color.Transparent,
            contentWindowInsets = WindowInsets(0),
            bottomBar = {
                FloatingTabBar(selected = tab, onSelect = { tab = it })
            },
        ) { padding ->
            Box(Modifier.padding(padding)) {
                AnimatedContent(
                    targetState = tab,
                    transitionSpec = { fadeIn() togetherWith fadeOut() },
                    label = "root-tab",
                ) { current ->
                    when (current) {
                        RootTab.Home -> HomeScreen(
                            session = session,
                            onProfile = { profileOpen = true },
                            onWallpaper = { detail = it },
                            onCollection = { collection = it },
                            onWeekly = { weekly = it },
                            onTab = { tab = it },
                        )
                        RootTab.Discover -> DiscoverScreen(session, { profileOpen = true }, { detail = it })
                        RootTab.Weekly -> WeeklyScreen(session, { profileOpen = true }, { weekly = it })
                        RootTab.Collections -> CollectionsScreen(
                            topBar = true,
                            session = session,
                            onProfile = { profileOpen = true },
                            onCollection = { collection = it },
                        )
                        RootTab.Favorites -> FavoritesScreen(session, { profileOpen = true }, { detail = it })
                    }
                }
            }
        }

        detail?.let { wallpaper ->
            OverlaySurface {
                WallpaperDetailScreen(
                    initial = wallpaper,
                    session = session,
                    onClose = { detail = null },
                )
            }
        }

        collection?.let { item ->
            OverlaySurface {
                CollectionDetailScreen(
                    collection = item,
                    onBack = { collection = null },
                    onWallpaper = { detail = it },
                )
            }
        }

        weekly?.let { item ->
            OverlaySurface {
                WeeklyDetailScreen(
                    entry = item,
                    onBack = { weekly = null },
                    onWallpaper = { detail = it },
                )
            }
        }

        AnimatedVisibility(profileOpen, enter = fadeIn(), exit = fadeOut()) {
            OverlaySurface {
                ProfileScreen(
                    session = session,
                    onClose = { profileOpen = false },
                    onUpload = {
                        uploadOpen = true
                        profileOpen = false
                    },
                    onOpen = { destination ->
                        profileDestination = destination
                        profileOpen = false
                    },
                )
            }
        }

        profileDestination?.let { destination ->
            OverlaySurface {
                AccountDestinationScreen(
                    destination = destination,
                    session = session,
                    onBack = {
                        profileDestination = null
                        profileOpen = true
                    },
                    onWallpaper = { detail = it },
                    onCollection = { collection = it },
                )
            }
        }

        AnimatedVisibility(uploadOpen, enter = fadeIn(), exit = fadeOut()) {
            OverlaySurface {
                UploadScreen(
                    session = session,
                    onClose = {
                        uploadOpen = false
                        profileOpen = true
                    },
                )
            }
        }

        session.authMode?.let {
            AuthDialog(session = session, mode = it)
        }
    }
    }
}

@Composable
fun OverlaySurface(content: @Composable () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = LocalArchiveScheme.current.paper,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
        content = content,
    )
}

@Composable
fun ArchiveTopBar(
    title: String,
    onProfile: () -> Unit,
    onClose: (() -> Unit)? = null,
    session: AuthSession? = null,
) {
    val scheme = LocalArchiveScheme.current
    Row(
        modifier = Modifier
            .statusBarsPadding()
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .fillMaxWidth()
            .height(52.dp)
            .shadow(18.dp, RoundedCornerShape(28.dp))
            .clip(RoundedCornerShape(28.dp))
            .background(scheme.paper2.copy(alpha = 0.58f))
            .padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TopAvatar(session = session, enabled = onClose == null, onClick = onProfile)
        Text(
            text = title,
            color = scheme.ink,
            fontSize = 27.sp,
            fontWeight = FontWeight.Black,
            fontFamily = FontFamily.Serif,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 8.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        if (onClose != null) {
            CircleIconButton(
                icon = Icons.Outlined.Close,
                label = stringResource(R.string.cancel),
                selected = false,
                onClick = onClose,
            )
        } else {
            LockPreviewToolbarButton()
        }
    }
}

@Composable
fun NavigationTopBar(title: String, onBack: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    Row(
        modifier = Modifier
            .statusBarsPadding()
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .fillMaxWidth()
            .height(52.dp)
            .shadow(18.dp, RoundedCornerShape(28.dp))
            .clip(RoundedCornerShape(28.dp))
            .background(scheme.paper2.copy(alpha = 0.58f))
            .padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircleIconButton(
            icon = Icons.Outlined.ArrowBack,
            label = stringResource(R.string.cancel),
            selected = false,
            onClick = onBack,
        )
        Text(
            text = title,
            color = scheme.ink,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        LockPreviewToolbarButton()
    }
}

@Composable
fun DetailTopBar(onBack: () -> Unit, previewActive: Boolean, onPreview: () -> Unit) {
    Row(
        modifier = Modifier
            .statusBarsPadding()
            .padding(12.dp)
            .fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TranslucentCircleButton(Icons.Outlined.ArrowBack, stringResource(R.string.cancel), onBack)
        TranslucentCircleButton(
            icon = Icons.Outlined.PhoneIphone,
            label = stringResource(R.string.preview),
            selected = previewActive,
            onClick = onPreview,
        )
    }
}

@Composable
fun TopAvatar(session: AuthSession?, enabled: Boolean, onClick: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    val user = session?.user
    Box(
        modifier = Modifier
            .size(40.dp)
            .clip(CircleShape)
            .background(scheme.paper3.copy(alpha = 0.78f))
            .clickable(enabled = enabled) { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        if (user != null && user.avatarUrl.isNotBlank()) {
            RemoteImage(user.avatarUrl, Modifier.fillMaxSize())
        } else if (user != null) {
            Text(
                text = (user.nickname.ifBlank { user.username }).take(1).uppercase(),
                color = scheme.ink2,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
            )
        } else {
            Icon(Icons.Outlined.Person, contentDescription = stringResource(R.string.me), tint = scheme.ink2, modifier = Modifier.size(19.dp))
        }
        Box(Modifier.matchParentSize().clip(CircleShape).background(Color.Transparent))
    }
}

@Composable
fun LockPreviewToolbarButton() {
    val lockPreview = LocalLockPreviewState.current
    CircleIconButton(
        icon = Icons.Outlined.PhoneIphone,
        label = stringResource(R.string.lock_preview),
        selected = lockPreview.enabled,
        onClick = { lockPreview.toggle() },
    )
}

@Composable
fun CircleIconButton(icon: ImageVector, label: String, selected: Boolean, onClick: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    IconButton(
        onClick = onClick,
        modifier = Modifier
            .size(40.dp)
            .clip(CircleShape)
            .background(if (selected) scheme.accent else scheme.paper3.copy(alpha = 0.78f)),
    ) {
        Icon(icon, contentDescription = label, tint = if (selected) Color.Black.copy(alpha = 0.82f) else scheme.ink2, modifier = Modifier.size(18.dp))
    }
}

@Composable
fun TranslucentCircleButton(icon: ImageVector, label: String, onClick: () -> Unit, selected: Boolean = false) {
    val scheme = LocalArchiveScheme.current
    IconButton(
        onClick = onClick,
        modifier = Modifier
            .size(40.dp)
            .clip(CircleShape)
            .background(if (selected) scheme.accent else Color.Black.copy(alpha = 0.32f)),
    ) {
        Icon(icon, contentDescription = label, tint = if (selected) Color.Black.copy(alpha = 0.82f) else scheme.lightText, modifier = Modifier.size(19.dp))
    }
}

@Composable
fun FloatingTabBar(selected: RootTab, onSelect: (RootTab) -> Unit) {
    val scheme = LocalArchiveScheme.current
    Row(
        modifier = Modifier
            .navigationBarsPadding()
            .padding(horizontal = 18.dp, vertical = 8.dp)
            .fillMaxWidth()
            .height(68.dp)
            .shadow(20.dp, RoundedCornerShape(28.dp))
            .clip(RoundedCornerShape(28.dp))
            .background(Color.Black.copy(alpha = 0.70f))
            .padding(horizontal = 8.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RootTab.entries.forEach { tab ->
            val active = selected == tab
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(20.dp))
                    .background(if (active) scheme.accent else Color.Transparent)
                    .clickable { onSelect(tab) },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(
                    imageVector = if (tab == RootTab.Favorites && active) Icons.Filled.Favorite else tab.icon,
                    contentDescription = stringResource(tab.label),
                    tint = if (active) Color.Black.copy(alpha = 0.82f) else Color.White.copy(alpha = 0.78f),
                    modifier = Modifier.size(18.dp),
                )
                Text(
                    text = stringResource(tab.label),
                    fontSize = 10.sp,
                    fontWeight = if (active) FontWeight.Bold else FontWeight.Medium,
                    color = if (active) Color.Black.copy(alpha = 0.82f) else Color.White.copy(alpha = 0.78f),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
fun SectionHeader(kicker: String, title: String, modifier: Modifier = Modifier) {
    val scheme = LocalArchiveScheme.current
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(title, color = scheme.ink, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        if (kicker.isNotBlank()) {
            Text(kicker, color = scheme.muted, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
fun SectionRow(kicker: String, title: String, action: String, onAction: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        SectionHeader(kicker, title, Modifier.weight(1f))
        TextButton(onClick = onAction) {
            Text(action, color = scheme.accentInk, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun HomeScreen(
    session: AuthSession,
    onProfile: () -> Unit,
    onWallpaper: (Wallpaper) -> Unit,
    onCollection: (CollectionItem) -> Unit,
    onWeekly: (WeeklyArchiveEntry) -> Unit,
    onTab: (RootTab) -> Unit,
) {
    var weekly by remember { mutableStateOf<List<WeeklyArchiveEntry>>(emptyList()) }
    var wallpapers by remember { mutableStateOf<List<Wallpaper>>(emptyList()) }
    var collections by remember { mutableStateOf<List<CollectionItem>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        loading = true
        error = null
        runCatching {
            weekly = ApiClient.fetchWeeklyArchive(4)
            wallpapers = ApiClient.fetchWallpapers(limit = 8).items
            collections = ApiClient.fetchCollections(limit = 4).items
        }.onFailure { error = it.message }
        loading = false
    }

    LaunchedEffect(Unit) { load() }

    Column(Modifier.fillMaxSize()) {
        ArchiveTopBar(stringResource(R.string.home), onProfile, session = session)
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            item {
                when {
                    loading && weekly.isEmpty() && wallpapers.isEmpty() && collections.isEmpty() -> HomeSkeleton()
                    error != null && weekly.isEmpty() && wallpapers.isEmpty() && collections.isEmpty() -> ErrorState(error.orEmpty()) { }
                    else -> Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        if (weekly.isNotEmpty()) {
                            WeeklyAlbumSection(weekly, onWeekly, onViewAll = { onTab(RootTab.Weekly) })
                        }
                        if (wallpapers.isNotEmpty()) {
                            SectionRow(
                                kicker = stringResource(R.string.latest),
                                title = stringResource(R.string.latest_wallpapers),
                                action = stringResource(R.string.see_more),
                                onAction = { onTab(RootTab.Discover) },
                            )
                            WallpaperGrid(wallpapers, onWallpaper)
                        }
                        if (collections.isNotEmpty()) {
                            SectionRow(
                                kicker = stringResource(R.string.collections_kicker),
                                title = stringResource(R.string.latest_collections),
                                action = stringResource(R.string.see_more),
                                onAction = { onTab(RootTab.Collections) },
                            )
                            Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                collections.take(4).forEach { CollectionCard(it, onCollection, height = 148) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun WeeklyAlbumSection(
    entries: List<WeeklyArchiveEntry>,
    onWeekly: (WeeklyArchiveEntry) -> Unit,
    onViewAll: () -> Unit,
) {
    var index by remember { mutableIntStateOf(0) }
    val visible = entries.take(4)
    LaunchedEffect(visible.size) {
        while (visible.size > 1) {
            delay(4500)
            index = (index + 1) % visible.size
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionRow(stringResource(R.string.weekly_kicker), stringResource(R.string.recent_weekly), stringResource(R.string.view_all), onViewAll)
        Box(Modifier.padding(horizontal = 12.dp)) {
            visible.getOrNull(index)?.let { entry ->
                WeeklyAlbumCard(entry, index, visible.size, onWeekly)
            }
        }
    }
}

@Composable
fun WeeklyAlbumCard(entry: WeeklyArchiveEntry, index: Int, count: Int, onWeekly: (WeeklyArchiveEntry) -> Unit) {
    val scheme = LocalArchiveScheme.current
    val accent = hexColor(entry.accentColor ?: entry.dominantColor, scheme.accent)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(336.dp)
            .then(paletteReactiveModifier(entry.colorPalette, entry.dominantColor ?: entry.accentColor))
            .clickable { onWeekly(entry) },
        contentAlignment = Alignment.BottomCenter,
    ) {
        WeeklyAlbumLayer(entry, accent, scale = 0.88f, alpha = 0.34f, x = 22.dp, y = 18.dp)
        WeeklyAlbumLayer(entry, accent, scale = 0.94f, alpha = 0.55f, x = 11.dp, y = 9.dp)
        Box(
            Modifier
                .padding(end = 22.dp, bottom = 18.dp)
                .fillMaxWidth()
                .height(316.dp)
                .clip(RoundedCornerShape(28.dp))
                .background(accent.copy(alpha = 0.72f))
        ) {
            RemoteImage(entry.coverUrl, Modifier.fillMaxSize(), placeholder = accent.copy(alpha = 0.50f))
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.74f)))))
            Column(Modifier.align(Alignment.BottomStart).padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.week, entry.week), color = scheme.lightText, fontSize = 28.sp, fontWeight = FontWeight.Black)
                Text(stringResource(R.string.picks_count, entry.count), color = scheme.lightText.copy(alpha = 0.78f), fontWeight = FontWeight.SemiBold)
            }
            Row(Modifier.align(Alignment.BottomCenter).padding(bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                repeat(count) { dot ->
                    Box(
                        Modifier
                            .size(if (dot == index) 8.dp else 5.dp)
                            .clip(CircleShape)
                            .background(if (dot == index) scheme.lightText else scheme.lightText.copy(alpha = 0.40f))
                    )
                }
            }
        }
    }
}

@Composable
fun WeeklyAlbumLayer(entry: WeeklyArchiveEntry, accent: Color, scale: Float, alpha: Float, x: androidx.compose.ui.unit.Dp, y: androidx.compose.ui.unit.Dp) {
    Box(
        Modifier
            .padding(end = x, bottom = y)
            .fillMaxWidth()
            .height(300.dp)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                transformOrigin = androidx.compose.ui.graphics.TransformOrigin(1f, 1f)
            }
            .clip(RoundedCornerShape(28.dp))
            .background(accent.copy(alpha = alpha))
    ) {
        RemoteImage(
            entry.coverUrl,
            Modifier.fillMaxSize(),
            placeholder = accent.copy(alpha = alpha),
        )
        Box(Modifier.fillMaxSize().background(accent.copy(alpha = 0.55f)))
    }
}

@Composable
fun DiscoverScreen(session: AuthSession, onProfile: () -> Unit, onWallpaper: (Wallpaper) -> Unit) {
    val scope = rememberCoroutineScope()
    var feed by remember { mutableStateOf(Feed.Latest) }
    var categories by remember { mutableStateOf<List<Category>>(emptyList()) }
    var category by remember { mutableStateOf<Category?>(null) }
    var wallpapers by remember { mutableStateOf<List<Wallpaper>>(emptyList()) }
    var cursor by remember { mutableStateOf<Int?>(null) }
    var hasMore by remember { mutableStateOf(true) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load(reset: Boolean) {
        if (loading) return
        loading = true
        if (reset) {
            wallpapers = emptyList()
            cursor = null
            hasMore = true
        }
        runCatching {
            if (feed == Feed.ForYou) {
                val token = session.token ?: throw ApiException("Sign in required", 401)
                Page(ApiClient.fetchForYou(token), null, false)
            } else {
                ApiClient.fetchWallpapers(
                    cursor = if (reset) null else cursor,
                    limit = 24,
                    aiOnly = feed == Feed.Ai,
                    categoryId = category?.id,
                    sort = if (feed == Feed.Popular) "popular" else null,
                )
            }
        }.onSuccess {
            wallpapers = if (reset) it.items else wallpapers + it.items
            cursor = it.nextCursor
            hasMore = it.hasMore
            error = null
        }.onFailure {
            error = it.message
            hasMore = false
        }
        loading = false
    }

    LaunchedEffect(Unit) {
        categories = runCatching { ApiClient.fetchCategories() }.getOrDefault(emptyList())
        load(true)
    }
    LaunchedEffect(feed, category) { load(true) }

    Column(Modifier.fillMaxSize()) {
        ArchiveTopBar(stringResource(R.string.discover), onProfile, session = session)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 28.dp)) {
            item {
                FilterSurface(
                    feed = feed,
                    feeds = if (session.isLoggedIn) Feed.entries else Feed.entries.filter { it != Feed.ForYou },
                    categories = categories,
                    selectedCategory = category,
                    onFeed = { feed = it },
                    onCategory = { category = if (category == it) null else it },
                )
            }
            item {
                when {
                    wallpapers.isEmpty() && loading -> WallpaperGridSkeleton(8)
                    wallpapers.isEmpty() && error != null -> ErrorState(error.orEmpty()) {}
                    wallpapers.isEmpty() -> EmptyState()
                    else -> Column {
                        WallpaperGrid(wallpapers, onWallpaper)
                        PagingFooter(loading, hasMore) { scope.launch { load(false) } }
                    }
                }
            }
        }
    }
}

@Composable
fun FilterSurface(
    feed: Feed,
    feeds: List<Feed>,
    categories: List<Category>,
    selectedCategory: Category?,
    onFeed: (Feed) -> Unit,
    onCategory: (Category?) -> Unit,
) {
    val scheme = LocalArchiveScheme.current
    Column(
        Modifier
            .padding(horizontal = 12.dp)
            .clip(RoundedCornerShape(24.dp))
            .background(scheme.paper2.copy(alpha = 0.72f))
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            feeds.forEach { f ->
                FilterChip(
                    selected = feed == f,
                    onClick = { onFeed(f) },
                    label = { Text(feedTitle(f)) },
                )
            }
        }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AssistChip(onClick = { onCategory(null) }, label = { Text(stringResource(R.string.all)) })
            categories.forEach {
                FilterChip(selected = selectedCategory == it, onClick = { onCategory(it) }, label = { Text(it.name) })
            }
        }
    }
}

@Composable
fun feedTitle(feed: Feed): String = when (feed) {
    Feed.Latest -> stringResource(R.string.latest)
    Feed.Popular -> stringResource(R.string.popular)
    Feed.ForYou -> stringResource(R.string.for_you)
    Feed.Ai -> stringResource(R.string.ai)
}

@Composable
fun CollectionsScreen(topBar: Boolean, session: AuthSession? = null, onProfile: () -> Unit, onCollection: (CollectionItem) -> Unit) {
    val scope = rememberCoroutineScope()
    var collections by remember { mutableStateOf<List<CollectionItem>>(emptyList()) }
    var cursor by remember { mutableStateOf<Int?>(null) }
    var hasMore by remember { mutableStateOf(true) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load(reset: Boolean = false) {
        if (loading) return
        loading = true
        if (reset) {
            collections = emptyList()
            cursor = null
            hasMore = true
        }
        runCatching { ApiClient.fetchCollections(if (reset) null else cursor) }
            .onSuccess {
                collections = if (reset) it.items else collections + it.items
                cursor = it.nextCursor
                hasMore = it.hasMore
                error = null
            }
            .onFailure {
                error = it.message
                hasMore = false
            }
        loading = false
    }

    LaunchedEffect(Unit) { load(true) }

    Column(Modifier.fillMaxSize()) {
        if (topBar) ArchiveTopBar(stringResource(R.string.collections), onProfile, session = session)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 28.dp)) {
            item {
                SectionHeader(stringResource(R.string.collections_kicker), stringResource(R.string.collections), Modifier.padding(horizontal = 12.dp, vertical = 8.dp))
            }
            when {
                collections.isEmpty() && loading -> item { CollectionListSkeleton(3) }
                collections.isEmpty() && error != null -> item { ErrorState(error.orEmpty()) {} }
                else -> {
                    items(collections, key = { it.id }) {
                        Box(Modifier.padding(horizontal = 12.dp)) {
                            CollectionCard(it, onCollection)
                        }
                    }
                    item { PagingFooter(loading, hasMore) { scope.launch { load(false) } } }
                }
            }
        }
    }
}

@Composable
fun WeeklyScreen(session: AuthSession, onProfile: () -> Unit, onWeekly: (WeeklyArchiveEntry) -> Unit) {
    var entries by remember { mutableStateOf<List<WeeklyArchiveEntry>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        loading = true
        runCatching { ApiClient.fetchWeeklyArchive(50) }
            .onSuccess { entries = it }
            .onFailure { error = it.message }
        loading = false
    }
    Column(Modifier.fillMaxSize()) {
        ArchiveTopBar(stringResource(R.string.weekly), onProfile, session = session)
        LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 28.dp)) {
            item { SectionHeader(stringResource(R.string.weekly_archive_kicker), stringResource(R.string.past_weeks), Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) }
            when {
                loading && entries.isEmpty() -> item { WeeklyArchiveSkeleton() }
                error != null && entries.isEmpty() -> item { ErrorState(error.orEmpty()) {} }
                else -> item { WeeklyArchiveGrid(entries, onWeekly) }
            }
        }
    }
}

@Composable
fun WeeklyArchiveGrid(entries: List<WeeklyArchiveEntry>, onWeekly: (WeeklyArchiveEntry) -> Unit) {
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        entries.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { entry ->
                    WeeklyArchiveCard(entry = entry, onClick = onWeekly, modifier = Modifier.weight(1f))
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun FavoritesScreen(session: AuthSession, onProfile: () -> Unit, onWallpaper: (Wallpaper) -> Unit) {
    var wallpapers by remember { mutableStateOf<List<Wallpaper>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(session.token) {
        val token = session.token ?: return@LaunchedEffect
        loading = true
        runCatching { ApiClient.fetchFavorites(token).items }
            .onSuccess { wallpapers = it }
            .onFailure { error = it.message }
        loading = false
    }
    Column(Modifier.fillMaxSize()) {
        ArchiveTopBar(stringResource(R.string.favorites), onProfile, session = session)
        if (!session.isLoggedIn) {
            SignInGate(session)
        } else {
            LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 28.dp)) {
                item {
                    when {
                        loading -> WallpaperGridSkeleton(8)
                        error != null && wallpapers.isEmpty() -> ErrorState(error.orEmpty()) {}
                        wallpapers.isEmpty() -> EmptyState()
                        else -> WallpaperGrid(wallpapers, onWallpaper)
                    }
                }
            }
        }
    }
}

@Composable
fun ProfileScreen(
    session: AuthSession,
    onClose: () -> Unit,
    onUpload: () -> Unit,
    onOpen: (ProfileDestination) -> Unit,
) {
    val context = LocalContext.current
    Column(Modifier.fillMaxSize()) {
        ArchiveTopBar(stringResource(R.string.me), onProfile = {}, onClose = onClose, session = session)
        if (session.isLoggedIn && session.user != null) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 8.dp, bottom = 28.dp),
            ) {
                item {
                    ProfileCard(
                        session = session,
                        onUpload = onUpload,
                        onEdit = { Toast.makeText(context, context.getString(R.string.coming_soon), Toast.LENGTH_SHORT).show() },
                        onPassword = { Toast.makeText(context, context.getString(R.string.coming_soon), Toast.LENGTH_SHORT).show() },
                        onSignOut = { session.logout() },
                        onCoins = { onOpen(ProfileDestination.Coins) },
                    )
                }
                item { AccountNavigationCard(session.user!!, onOpen) }
                item { PreferencesCard() }
            }
        } else {
            Column(
                Modifier.fillMaxSize().padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(Icons.Outlined.Person, contentDescription = null, tint = LocalArchiveScheme.current.muted, modifier = Modifier.size(58.dp))
                Spacer(Modifier.height(16.dp))
                Text(stringResource(R.string.sign_in_message), color = LocalArchiveScheme.current.muted, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Spacer(Modifier.height(16.dp))
                Button(onClick = { session.present(AuthMode.Login) }) { Text(stringResource(R.string.sign_in)) }
                Spacer(Modifier.height(20.dp))
                PreferencesCard()
            }
        }
    }
}

@Composable
fun ProfileCard(
    session: AuthSession,
    onUpload: () -> Unit,
    onEdit: () -> Unit,
    onPassword: () -> Unit,
    onSignOut: () -> Unit,
    onCoins: () -> Unit,
) {
    val scheme = LocalArchiveScheme.current
    val user = session.user ?: return
    Column(
        Modifier
            .padding(horizontal = 12.dp)
            .clip(RoundedCornerShape(20.dp))
            .background(scheme.paper2)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(66.dp).clip(CircleShape).background(scheme.paper3), contentAlignment = Alignment.Center) {
                if (user.avatarUrl.isNotBlank()) {
                    RemoteImage(user.avatarUrl, Modifier.fillMaxSize())
                } else {
                    Text((user.nickname.ifBlank { user.username }).take(1).uppercase(), color = scheme.ink2, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(user.nickname.ifBlank { user.username }, color = scheme.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("@${user.username}", color = scheme.muted, fontSize = 12.sp)
                if (user.bio.isNotBlank()) {
                    Text(user.bio, color = scheme.ink2, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
            Box(
                Modifier
                    .size(54.dp)
                    .clip(CircleShape)
                    .background(scheme.accentSoft)
                    .clickable { onCoins() },
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text("${user.coins}", color = scheme.accentInk, fontSize = 21.sp, fontWeight = FontWeight.Bold)
                    Text(stringResource(R.string.coins), color = scheme.muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ProfileActionButton(Icons.Outlined.Upload, stringResource(R.string.upload), accent = true, modifier = Modifier.weight(1f), onClick = onUpload)
            ProfileActionButton(Icons.Outlined.Person, stringResource(R.string.edit_profile), modifier = Modifier.weight(1f), onClick = onEdit)
            ProfileActionButton(Icons.Outlined.Info, stringResource(R.string.password), modifier = Modifier.weight(1f), onClick = onPassword)
            ProfileActionButton(Icons.Outlined.Close, stringResource(R.string.sign_out), modifier = Modifier.weight(1f), onClick = onSignOut)
        }
    }
}

@Composable
fun ProfileActionButton(icon: ImageVector, title: String, accent: Boolean = false, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    Column(
        modifier
            .height(52.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(if (accent) scheme.accent else scheme.paper3)
            .clickable { onClick() }
            .padding(horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(icon, contentDescription = null, tint = if (accent) scheme.lightText else scheme.ink2, modifier = Modifier.size(15.dp))
        Text(title, color = if (accent) scheme.lightText else scheme.ink2, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun AccountNavigationCard(user: User, onOpen: (ProfileDestination) -> Unit) {
    val scheme = LocalArchiveScheme.current
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeader("", stringResource(R.string.account_library_title))
        Column(Modifier.clip(RoundedCornerShape(18.dp)).background(scheme.paper2)) {
            AccountNavRow(ProfileDestination.Uploads.icon, stringResource(R.string.my_uploads), scheme.accentInk) { onOpen(ProfileDestination.Uploads) }
            RowDivider()
            AccountNavRow(ProfileDestination.Downloads.icon, stringResource(R.string.my_downloads), Color(0xFF3E7EBB)) { onOpen(ProfileDestination.Downloads) }
            RowDivider()
            AccountNavRow(ProfileDestination.Favorites.icon, stringResource(R.string.favorites), Color(0xFFD55A8A)) { onOpen(ProfileDestination.Favorites) }
            RowDivider()
            AccountNavRow(ProfileDestination.Likes.icon, stringResource(R.string.my_likes), Color(0xFF3E8B5B)) { onOpen(ProfileDestination.Likes) }
            RowDivider()
            AccountNavRow(ProfileDestination.Collections.icon, stringResource(R.string.my_collections), Color(0xFFD48235)) { onOpen(ProfileDestination.Collections) }
            RowDivider()
            AccountNavRow(ProfileDestination.Coins.icon, stringResource(R.string.my_coins), scheme.accent, detail = "${user.coins}") { onOpen(ProfileDestination.Coins) }
        }
    }
}

@Composable
fun AccountNavRow(icon: ImageVector, title: String, tint: Color, detail: String? = null, onClick: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    Row(
        Modifier
            .fillMaxWidth()
            .height(52.dp)
            .clickable { onClick() }
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(28.dp).clip(CircleShape).background(tint.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(16.dp))
        }
        Text(title, color = scheme.ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f), maxLines = 1)
        detail?.let { Text(it, color = scheme.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace) }
        Text("›", color = scheme.muted, fontSize = 22.sp)
    }
}

@Composable
fun PreferencesCard() {
    val scheme = LocalArchiveScheme.current
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeader("", stringResource(R.string.settings))
        Column(Modifier.clip(RoundedCornerShape(18.dp)).background(scheme.paper2)) {
            AccountNavRow(Icons.Outlined.Search, stringResource(R.string.language), scheme.accentInk) {}
            RowDivider()
            AccountNavRow(Icons.Outlined.PhoneIphone, stringResource(R.string.appearance), scheme.accentInk) {}
            RowDivider()
            AccountNavRow(Icons.Outlined.Info, stringResource(R.string.app_version), scheme.accentInk, detail = "0.1.0") {}
        }
    }
}

@Composable
fun RowDivider() {
    Box(Modifier.fillMaxWidth().padding(start = 50.dp).height(1.dp).background(LocalArchiveScheme.current.hair.copy(alpha = 0.72f)))
}

@Composable
fun UploadScreen(session: AuthSession, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var queue by remember { mutableStateOf<List<AndroidUploadItem>>(emptyList()) }
    var uploading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(20)) { uris ->
        val existing = queue.map { it.uri }.toSet()
        val additions = uris
            .filterNot { it in existing }
            .take(20 - queue.size)
            .map { uri -> AndroidUploadItem(uri = uri, name = displayName(context, uri)) }
        if (additions.isNotEmpty()) queue = queue + additions
    }

    suspend fun submit() {
        val token = session.token
        if (token == null) {
            session.present(AuthMode.Login)
            return
        }
        uploading = true
        error = null
        for (item in queue.filter { it.status == UploadStatus.Ready || it.status == UploadStatus.Failed }) {
            queue = queue.map { if (it.id == item.id) it.copy(status = UploadStatus.Uploading) else it }
            runCatching { uploadUri(context, item.uri, item.name, token) }
                .onSuccess { queue = queue.map { if (it.id == item.id) it.copy(status = UploadStatus.Success) else it } }
                .onFailure {
                    error = it.message
                    queue = queue.map { q -> if (q.id == item.id) q.copy(status = UploadStatus.Failed) else q }
                }
        }
        uploading = false
    }

    Column(Modifier.fillMaxSize()) {
        ArchiveTopBar(stringResource(R.string.upload), onProfile = {}, onClose = onClose, session = session)
        if (!session.isLoggedIn) {
            SignInGate(session)
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item {
                    OutlinedButton(
                        enabled = !uploading && queue.size < 20,
                        onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                        modifier = Modifier.fillMaxWidth().height(if (queue.isEmpty()) 132.dp else 58.dp),
                    ) {
                        Icon(Icons.Outlined.Upload, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text(if (queue.isEmpty()) stringResource(R.string.choose_photos) else stringResource(R.string.selected_photos, queue.size))
                    }
                }
                if (queue.isNotEmpty()) {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            queue.forEach { item ->
                                UploadQueueRow(
                                    item = item,
                                    onRemove = {
                                        if (!uploading) queue = queue.filterNot { it.id == item.id }
                                    },
                                )
                            }
                        }
                    }
                    item {
                        Button(
                            enabled = !uploading && queue.any { it.status == UploadStatus.Ready || it.status == UploadStatus.Failed },
                            onClick = { scope.launch { submit() } },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(if (uploading) stringResource(R.string.uploading) else stringResource(R.string.start_upload))
                        }
                    }
                }
                error?.let { message ->
                    item { Text(message, color = Color(0xFFC84C31), modifier = Modifier.padding(horizontal = 4.dp)) }
                }
                item {
                    Text(stringResource(R.string.upload_rules), color = LocalArchiveScheme.current.muted, fontSize = 13.sp)
                }
            }
        }
    }
}

@Composable
fun UploadQueueRow(item: AndroidUploadItem, onRemove: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(scheme.paper2).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp))) {
            RemoteImage(item.uri.toString(), Modifier.fillMaxSize())
        }
        Column(Modifier.weight(1f)) {
            Text(item.name, color = scheme.ink, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(uploadStatusText(item.status), color = scheme.muted, fontSize = 12.sp)
        }
        if (item.status == UploadStatus.Uploading) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
        } else if (item.status != UploadStatus.Success) {
            IconButton(onClick = onRemove) {
                Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.cancel), tint = scheme.muted)
            }
        }
    }
}

@Composable
fun uploadStatusText(status: UploadStatus): String = when (status) {
    UploadStatus.Ready -> stringResource(R.string.upload_ready)
    UploadStatus.Uploading -> stringResource(R.string.uploading)
    UploadStatus.Success -> stringResource(R.string.upload_done)
    UploadStatus.Failed -> stringResource(R.string.upload_failed_short)
}

fun displayName(context: Context, uri: Uri): String {
    val resolver = context.contentResolver
    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        if (index >= 0 && cursor.moveToFirst()) {
            return cursor.getString(index)
        }
    }
    return "wallpaper-${System.currentTimeMillis()}.jpg"
}

suspend fun uploadUri(context: Context, uri: Uri, fileName: String, token: String) = withContext(Dispatchers.IO) {
    val resolver = context.contentResolver
    val mime = resolver.getType(uri) ?: "image/jpeg"
    val safeName = fileName.replace("\"", "_")
    val boundary = "Boundary-${UUID.randomUUID()}"
    val connection = (URL(ApiClient.uploadEndpoint()).openConnection() as HttpURLConnection).apply {
        requestMethod = "POST"
        doOutput = true
        connectTimeout = 15000
        readTimeout = 60000
        setRequestProperty("Authorization", "Bearer $token")
        setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        setRequestProperty("Accept", "application/json")
    }
    connection.outputStream.use { output ->
        fun write(value: String) = output.write(value.toByteArray(Charsets.UTF_8))
        write("--$boundary\r\n")
        write("Content-Disposition: form-data; name=\"file\"; filename=\"$safeName\"\r\n")
        write("Content-Type: $mime\r\n\r\n")
        resolver.openInputStream(uri)?.use { input -> input.copyTo(output) } ?: throw ApiException("Cannot open selected photo")
        write("\r\n--$boundary--\r\n")
    }
    val status = connection.responseCode
    if (status >= 400) {
        val message = connection.errorStream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
        throw ApiException(message.ifBlank { "Upload failed" }, status)
    }
}

@Composable
fun ProfileRow(icon: ImageVector, title: String, onClick: () -> Unit = {}) {
    val scheme = LocalArchiveScheme.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(scheme.paper2)
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, tint = scheme.accentInk, modifier = Modifier.size(22.dp))
        Text(title, color = scheme.ink, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        Text("›", color = scheme.muted, fontSize = 22.sp)
    }
}

@Composable
fun AccountDestinationScreen(
    destination: ProfileDestination,
    session: AuthSession,
    onBack: () -> Unit,
    onWallpaper: (Wallpaper) -> Unit,
    onCollection: (CollectionItem) -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        NavigationTopBar(stringResource(destination.title), onBack)
        if (!session.isLoggedIn) {
            SignInGate(session)
        } else {
            when (destination) {
                ProfileDestination.Uploads -> AccountUploadsScreen(session, onWallpaper)
                ProfileDestination.Collections -> AccountCollectionsScreen(session, onCollection)
                ProfileDestination.Coins -> AccountCoinsScreen(session)
                ProfileDestination.Downloads,
                ProfileDestination.Favorites,
                ProfileDestination.Likes -> AccountWallpaperListScreen(destination, session, onWallpaper)
            }
        }
    }
}

@Composable
fun AccountWallpaperListScreen(destination: ProfileDestination, session: AuthSession, onWallpaper: (Wallpaper) -> Unit) {
    val scope = rememberCoroutineScope()
    var wallpapers by remember(destination) { mutableStateOf<List<Wallpaper>>(emptyList()) }
    var cursor by remember(destination) { mutableStateOf<Int?>(null) }
    var hasMore by remember(destination) { mutableStateOf(true) }
    var loading by remember(destination) { mutableStateOf(false) }
    var error by remember(destination) { mutableStateOf<String?>(null) }

    suspend fun load(reset: Boolean) {
        val token = session.token ?: return
        if (loading) return
        loading = true
        if (reset) {
            wallpapers = emptyList()
            cursor = null
            hasMore = true
        }
        runCatching {
            when (destination) {
                ProfileDestination.Downloads -> ApiClient.fetchDownloads(token, if (reset) null else cursor)
                ProfileDestination.Favorites -> ApiClient.fetchFavorites(token, if (reset) null else cursor)
                ProfileDestination.Likes -> ApiClient.fetchLikes(token, if (reset) null else cursor)
                else -> Page(emptyList(), null, false)
            }
        }.onSuccess {
            wallpapers = if (reset) it.items else wallpapers + it.items
            cursor = it.nextCursor
            hasMore = it.hasMore
            error = null
        }.onFailure {
            error = it.message
            hasMore = false
        }
        loading = false
    }

    LaunchedEffect(destination, session.token) { load(true) }

    LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item {
            when {
                wallpapers.isEmpty() && loading -> WallpaperGridSkeleton(8)
                wallpapers.isEmpty() && error != null -> ErrorState(error.orEmpty()) { scope.launch { load(true) } }
                wallpapers.isEmpty() -> EmptyState()
                else -> WallpaperGrid(wallpapers, onWallpaper)
            }
        }
        if (wallpapers.isNotEmpty()) {
            item { PagingFooter(loading, hasMore) { scope.launch { load(false) } } }
        }
    }
}

@Composable
fun AccountUploadsScreen(session: AuthSession, onWallpaper: (Wallpaper) -> Unit) {
    val scope = rememberCoroutineScope()
    var pending by remember { mutableStateOf<List<Wallpaper>>(emptyList()) }
    var published by remember { mutableStateOf<List<Wallpaper>>(emptyList()) }
    var cursor by remember { mutableStateOf<Int?>(null) }
    var hasMore by remember { mutableStateOf(true) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val username = session.user?.username.orEmpty()

    suspend fun loadPublished(reset: Boolean) {
        val token = session.token ?: return
        if (username.isBlank() || loading) return
        loading = true
        if (reset) {
            published = emptyList()
            cursor = null
            hasMore = true
        }
        runCatching { ApiClient.fetchUserUploads(username, token, if (reset) null else cursor, status = "1,2,4,6") }
            .onSuccess {
                published = if (reset) it.items else published + it.items
                cursor = it.nextCursor
                hasMore = it.hasMore
                error = null
            }
            .onFailure {
                error = it.message
                hasMore = false
            }
        loading = false
    }

    LaunchedEffect(username, session.token) {
        val token = session.token ?: return@LaunchedEffect
        if (username.isBlank()) return@LaunchedEffect
        pending = runCatching { ApiClient.fetchUserUploads(username, token, limit = 12, status = "0,5").items }.getOrDefault(emptyList())
        loadPublished(true)
    }

    LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        if (pending.isNotEmpty()) {
            item {
                SectionHeader(stringResource(R.string.processing_review_kicker), stringResource(R.string.pending_uploads), Modifier.padding(horizontal = 12.dp))
                Spacer(Modifier.height(10.dp))
                WallpaperGrid(pending, onWallpaper)
            }
        }
        item {
            SectionHeader(stringResource(R.string.uploads_kicker), stringResource(R.string.published_uploads), Modifier.padding(horizontal = 12.dp))
        }
        item {
            when {
                published.isEmpty() && loading -> WallpaperGridSkeleton(8)
                published.isEmpty() && error != null -> ErrorState(error.orEmpty()) { scope.launch { loadPublished(true) } }
                published.isEmpty() -> EmptyState()
                else -> WallpaperGrid(published, onWallpaper)
            }
        }
        if (published.isNotEmpty()) {
            item { PagingFooter(loading, hasMore) { scope.launch { loadPublished(false) } } }
        }
    }
}

@Composable
fun AccountCollectionsScreen(session: AuthSession, onCollection: (CollectionItem) -> Unit) {
    val scope = rememberCoroutineScope()
    val username = session.user?.username.orEmpty()
    var collections by remember { mutableStateOf<List<CollectionItem>>(emptyList()) }
    var cursor by remember { mutableStateOf<Int?>(null) }
    var hasMore by remember { mutableStateOf(true) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load(reset: Boolean) {
        val token = session.token ?: return
        if (username.isBlank() || loading) return
        loading = true
        if (reset) {
            collections = emptyList()
            cursor = null
            hasMore = true
        }
        runCatching { ApiClient.fetchUserCollections(username, token, if (reset) null else cursor) }
            .onSuccess {
                collections = if (reset) it.items else collections + it.items
                cursor = it.nextCursor
                hasMore = it.hasMore
                error = null
            }
            .onFailure {
                error = it.message
                hasMore = false
            }
        loading = false
    }

    LaunchedEffect(username, session.token) { load(true) }

    LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        when {
            collections.isEmpty() && loading -> item { CollectionListSkeleton(3) }
            collections.isEmpty() && error != null -> item { ErrorState(error.orEmpty()) { scope.launch { load(true) } } }
            collections.isEmpty() -> item { EmptyState() }
            else -> {
                items(collections, key = { it.id }) {
                    Box(Modifier.padding(horizontal = 12.dp)) { CollectionCard(it, onCollection) }
                }
                item { PagingFooter(loading, hasMore) { scope.launch { load(false) } } }
            }
        }
    }
}

@Composable
fun AccountCoinsScreen(session: AuthSession) {
    val scope = rememberCoroutineScope()
    var balance by remember { mutableIntStateOf(0) }
    var transactions by remember { mutableStateOf<List<CoinTransaction>>(emptyList()) }
    var cursor by remember { mutableStateOf<Int?>(null) }
    var hasMore by remember { mutableStateOf(true) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load(reset: Boolean) {
        val token = session.token ?: return
        if (loading) return
        loading = true
        if (reset) {
            transactions = emptyList()
            cursor = null
            hasMore = true
            balance = runCatching { ApiClient.fetchCoins(token) }.getOrDefault(session.user?.coins ?: 0)
        }
        runCatching { ApiClient.fetchCoinTransactions(token, if (reset) null else cursor) }
            .onSuccess {
                transactions = if (reset) it.items else transactions + it.items
                cursor = it.nextCursor
                hasMore = it.hasMore
                error = null
            }
            .onFailure {
                error = it.message
                hasMore = false
            }
        loading = false
    }

    LaunchedEffect(session.token) { load(true) }

    LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            ElevatedCard(colors = CardDefaults.elevatedCardColors(containerColor = LocalArchiveScheme.current.paper2)) {
                Row(Modifier.fillMaxWidth().padding(18.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Outlined.Paid, contentDescription = null, tint = LocalArchiveScheme.current.accentInk, modifier = Modifier.size(34.dp))
                    Text(stringResource(R.string.coin_balance, balance), color = LocalArchiveScheme.current.ink, fontSize = 26.sp, fontWeight = FontWeight.Black)
                }
            }
        }
        item { SectionHeader(stringResource(R.string.ledger_kicker), stringResource(R.string.coin_transactions)) }
        when {
            transactions.isEmpty() && loading -> item { CollectionListSkeleton(3, 72) }
            transactions.isEmpty() && error != null -> item { ErrorState(error.orEmpty()) { scope.launch { load(true) } } }
            transactions.isEmpty() -> item { EmptyState() }
            else -> {
                items(transactions, key = { it.id }) { CoinTransactionRow(it) }
                item { PagingFooter(loading, hasMore) { scope.launch { load(false) } } }
            }
        }
    }
}

@Composable
fun CoinTransactionRow(tx: CoinTransaction) {
    val scheme = LocalArchiveScheme.current
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(scheme.paper2).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(if (tx.amount >= 0) "+${tx.amount}" else "${tx.amount}", color = if (tx.amount >= 0) Color(0xFF2E8B57) else Color(0xFFC84C31), fontSize = 18.sp, fontWeight = FontWeight.Black)
        Column(Modifier.weight(1f)) {
            Text(tx.description.ifBlank { tx.txType }, color = scheme.ink, fontWeight = FontWeight.SemiBold)
            Text(tx.createdAt.take(10), color = scheme.muted, fontSize = 12.sp)
        }
        Text("${tx.balance}", color = scheme.muted, fontFamily = FontFamily.Monospace)
    }
}

@Composable
fun WallpaperGrid(wallpapers: List<Wallpaper>, onWallpaper: (Wallpaper) -> Unit) {
    Column(Modifier.padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        wallpapers.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.fillMaxWidth()) {
                row.forEach { wallpaper ->
                    WallpaperCard(wallpaper, onWallpaper, Modifier.weight(1f))
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun WallpaperCard(wallpaper: Wallpaper, onWallpaper: (Wallpaper) -> Unit, modifier: Modifier = Modifier) {
    val scheme = LocalArchiveScheme.current
    val lockPreview = LocalLockPreviewState.current
    val tint = hexColor(wallpaper.dominantColor, scheme.paper3)
    Box(
        modifier
            .aspectRatio(9f / 19.5f)
            .then(paletteReactiveModifier(wallpaper.colorPalette, wallpaper.dominantColor))
            .clip(RoundedCornerShape(15.dp))
            .background(tint.copy(alpha = 0.65f))
            .clickable { onWallpaper(wallpaper) },
    ) {
        RemoteImage(wallpaper.displayUrl, Modifier.fillMaxSize(), placeholder = tint.copy(alpha = 0.55f))
        if (lockPreview.enabled) {
            LockScreenOverlay(compact = true, modifier = Modifier.fillMaxSize())
        } else {
            Row(Modifier.padding(7.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                MediaChip(wallpaper.resolutionLabel)
                if (wallpaper.isAiGenerated) MediaChip("AI", scheme.accent.copy(alpha = 0.78f))
            }
        }
    }
}

@Composable
fun LockScreenOverlay(compact: Boolean, modifier: Modifier = Modifier) {
    val now = remember { Date() }
    val time = remember(now) { SimpleDateFormat("HH:mm", Locale.getDefault()).format(now) }
    val date = remember(now) { SimpleDateFormat("EEEE, MMMM d", Locale.getDefault()).format(now) }
    Column(
        modifier
            .background(Color.Black.copy(alpha = if (compact) 0.04f else 0.08f))
            .padding(horizontal = if (compact) 10.dp else 36.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            Modifier.padding(top = if (compact) 12.dp else 58.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (compact) 0.dp else 2.dp),
        ) {
            Text(date, color = Color.White, fontSize = if (compact) 7.sp else 15.sp, fontWeight = FontWeight.Medium, maxLines = 1)
            Text(time, color = Color.White, fontSize = if (compact) 21.sp else 64.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.weight(1f))
        Row(
            Modifier
                .fillMaxWidth()
                .padding(bottom = if (compact) 10.dp else 28.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            LockScreenPill(compact)
            LockScreenPill(compact)
        }
    }
}

@Composable
fun LockScreenPill(compact: Boolean) {
    Box(
        Modifier
            .size(if (compact) 18.dp else 46.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.35f)),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .size(if (compact) 5.dp else 12.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.82f))
        )
    }
}

@Composable
fun MediaChip(text: String, tint: Color = Color.Black.copy(alpha = 0.28f)) {
    Text(
        text = text.uppercase(),
        color = Color(0xFFF8F6F1),
        fontSize = 10.sp,
        fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.Monospace,
        modifier = Modifier.clip(RoundedCornerShape(12.dp)).background(tint).padding(horizontal = 6.dp, vertical = 3.dp),
    )
}

@Composable
fun CollectionCard(collection: CollectionItem, onCollection: (CollectionItem) -> Unit, modifier: Modifier = Modifier, height: Int = 190) {
    val scheme = LocalArchiveScheme.current
    val accent = hexColor(collection.accentColor ?: collection.recentTiles.firstOrNull()?.dominantColor, scheme.paper3)
    Row(
        modifier
            .height(height.dp)
            .fillMaxWidth()
            .then(paletteReactiveModifier(null, collection.recentTiles.firstOrNull()?.dominantColor ?: collection.accentColor))
            .clip(RoundedCornerShape(18.dp))
            .background(scheme.paper2)
            .clickable { onCollection(collection) }
            .padding(11.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        CollectionMosaic(collection, accent, Modifier.width((height * 0.72f).dp).fillMaxHeight())
        Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(if (collection.kind == 1) stringResource(R.string.theme) else stringResource(R.string.shelf), color = scheme.muted, fontSize = 10.sp, letterSpacing = 2.sp)
            Text(collection.title, color = scheme.ink, fontSize = if (height > 170) 22.sp else 18.sp, fontWeight = FontWeight.Black, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(stringResource(R.string.wallpapers_count, collection.wallpaperCount), color = scheme.muted, fontSize = 13.sp)
            Spacer(Modifier.weight(1f))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.Collections, contentDescription = null, tint = scheme.accentInk, modifier = Modifier.size(16.dp))
                Text("${collection.wallpaperCount}", color = scheme.accentInk, fontWeight = FontWeight.Bold)
                if (collection.likeCount > 0) {
                    Icon(Icons.Outlined.FavoriteBorder, contentDescription = null, tint = scheme.accentInk, modifier = Modifier.size(16.dp))
                    Text("${collection.likeCount}", color = scheme.accentInk, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

@Composable
fun CollectionMosaic(collection: CollectionItem, accent: Color, modifier: Modifier = Modifier) {
    val tiles = collection.recentTiles
    Row(modifier.clip(RoundedCornerShape(14.dp)).background(accent.copy(alpha = 0.18f)).padding(5.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        RemoteImage(
            tiles.getOrNull(0)?.previewUrl ?: collection.coverUrl,
            Modifier.weight(0.62f).fillMaxHeight().clip(RoundedCornerShape(10.dp)),
            placeholder = accent.copy(alpha = 0.35f),
        )
        Column(Modifier.weight(0.38f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            RemoteImage(tiles.getOrNull(1)?.previewUrl, Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(9.dp)), placeholder = accent.copy(alpha = 0.24f))
            RemoteImage(tiles.getOrNull(2)?.previewUrl, Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(9.dp)), placeholder = accent.copy(alpha = 0.30f))
        }
    }
}

@Composable
fun WeeklyArchiveCard(entry: WeeklyArchiveEntry, onClick: (WeeklyArchiveEntry) -> Unit, modifier: Modifier = Modifier) {
    val scheme = LocalArchiveScheme.current
    val accent = hexColor(entry.accentColor ?: entry.dominantColor, scheme.accent)
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(0.78f)
            .then(paletteReactiveModifier(entry.colorPalette, entry.dominantColor ?: entry.accentColor))
            .clickable { onClick(entry) },
    ) {
        Box(
            Modifier
                .matchParentSize()
                .padding(start = 7.dp, bottom = 7.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(accent.copy(alpha = 0.18f))
        )
        Box(
            Modifier
                .matchParentSize()
                .padding(end = 7.dp, top = 7.dp)
                .clip(RoundedCornerShape(18.dp))
        ) {
            RemoteImage(entry.coverUrl, Modifier.fillMaxSize(), placeholder = accent.copy(alpha = 0.72f))
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.08f), Color.Black.copy(alpha = 0.72f)))))
            Column(Modifier.align(Alignment.BottomStart).padding(12.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(stringResource(R.string.week, entry.week), color = scheme.lightText, fontSize = 20.sp, fontWeight = FontWeight.Black, maxLines = 1)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    MediaChip(stringResource(R.string.year, entry.year), Color.Black.copy(alpha = 0.20f))
                    MediaChip(stringResource(R.string.picks_count, entry.count), Color.Black.copy(alpha = 0.20f))
                }
            }
        }
    }
}

@Composable
fun CollectionDetailScreen(collection: CollectionItem, onBack: () -> Unit, onWallpaper: (Wallpaper) -> Unit) {
    var wallpapers by remember { mutableStateOf<List<Wallpaper>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(collection.id) {
        loading = true
        runCatching { ApiClient.fetchCollectionWallpapers(collection.id).items }
            .onSuccess { wallpapers = it }
            .onFailure { error = it.message }
        loading = false
    }
    Column(Modifier.fillMaxSize()) {
        NavigationTopBar(collection.title, onBack)
        LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 28.dp)) {
            item {
                when {
                    loading -> WallpaperGridSkeleton(8)
                    error != null && wallpapers.isEmpty() -> ErrorState(error.orEmpty()) {}
                    wallpapers.isEmpty() -> EmptyState()
                    else -> WallpaperGrid(wallpapers, onWallpaper)
                }
            }
        }
    }
}

@Composable
fun WeeklyDetailScreen(entry: WeeklyArchiveEntry, onBack: () -> Unit, onWallpaper: (Wallpaper) -> Unit) {
    var wallpapers by remember { mutableStateOf<List<Wallpaper>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(entry.id) {
        loading = true
        runCatching { ApiClient.fetchWeeklyByWeek(entry.year, entry.week).map { it.wallpaper } }
            .onSuccess { wallpapers = it }
            .onFailure { error = it.message }
        loading = false
    }
    Column(Modifier.fillMaxSize()) {
        NavigationTopBar("${stringResource(R.string.week, entry.week)} · ${stringResource(R.string.year, entry.year)}", onBack)
        LazyColumn(contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 28.dp)) {
            item {
                when {
                    loading -> WallpaperGridSkeleton(8)
                    error != null && wallpapers.isEmpty() -> ErrorState(error.orEmpty()) {}
                    wallpapers.isEmpty() -> EmptyState()
                    else -> WallpaperGrid(wallpapers, onWallpaper)
                }
            }
        }
    }
}

@Composable
fun WallpaperDetailScreen(initial: Wallpaper, session: AuthSession, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val scheme = LocalArchiveScheme.current
    var detail by remember { mutableStateOf<WallpaperDetail?>(null) }
    var showInfo by remember { mutableStateOf(false) }
    var showDevicePreview by remember { mutableStateOf(false) }
    val wallpaper = detail?.wallpaper ?: initial
    LaunchedEffect(initial.slug) {
        runCatching { ApiClient.fetchWallpaperDetail(initial.slug) }.onSuccess { detail = it }
    }
    Box(Modifier.fillMaxSize().background(hexColor(wallpaper.dominantColor, scheme.paper3))) {
        RemoteImage(wallpaper.displayUrl, Modifier.fillMaxSize(), placeholder = hexColor(wallpaper.dominantColor, scheme.paper3))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.35f), Color.Transparent, Color.Black.copy(alpha = 0.62f)))))
        if (showDevicePreview) {
            LockScreenOverlay(compact = false, modifier = Modifier.fillMaxSize())
        }
        DetailTopBar(
            onBack = onClose,
            previewActive = showDevicePreview,
            onPreview = { showDevicePreview = !showDevicePreview },
        )
        DetailToolbar(
            modifier = Modifier.align(Alignment.BottomCenter).padding(18.dp).navigationBarsPadding(),
            onDownload = {
                val token = session.token
                if (token == null) {
                    session.present(AuthMode.Login)
                } else {
                    startDownload(context, wallpaper, token)
                }
            },
            onLike = {
                val token = session.token
                if (token == null) {
                    session.present(AuthMode.Login)
                } else {
                    scope.launch { runCatching { ApiClient.like(wallpaper.id, token) } }
                }
            },
            onFavorite = {
                val token = session.token
                if (token == null) {
                    session.present(AuthMode.Login)
                } else {
                    scope.launch { runCatching { ApiClient.favorite(wallpaper.id, token) } }
                }
            },
            onInfo = { showInfo = true },
            onSetWallpaper = {
                val token = session.token
                if (token == null) {
                    session.present(AuthMode.Login)
                } else {
                    scope.launch { setAsWallpaper(context, wallpaper, token) }
                }
            },
        )
        if (showInfo) WallpaperInfoSheet(wallpaper) { showInfo = false }
    }
}

@Composable
fun DetailToolbar(
    modifier: Modifier,
    onDownload: () -> Unit,
    onLike: () -> Unit,
    onFavorite: () -> Unit,
    onInfo: () -> Unit,
    onSetWallpaper: () -> Unit,
) {
    val scheme = LocalArchiveScheme.current
    Row(
        modifier
            .clip(RoundedCornerShape(28.dp))
            .background(Color.Black.copy(alpha = 0.32f))
            .padding(10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ToolbarButton(Icons.Outlined.ThumbUp, stringResource(R.string.like), onLike, scheme)
        ToolbarButton(Icons.Outlined.FavoriteBorder, stringResource(R.string.favorite), onFavorite, scheme)
        ToolbarButton(Icons.Outlined.Info, stringResource(R.string.info), onInfo, scheme)
        ToolbarButton(Icons.Outlined.Download, stringResource(R.string.download), onDownload, scheme, selected = true)
        ToolbarButton(Icons.Outlined.PhoneIphone, stringResource(R.string.set_wallpaper), onSetWallpaper, scheme, selected = true)
    }
}

@Composable
fun ToolbarButton(icon: ImageVector, label: String, action: () -> Unit, scheme: ArchiveScheme, selected: Boolean = false) {
    Box(
        Modifier
            .size(46.dp)
            .clip(CircleShape)
            .background(if (selected) scheme.accent else Color.White.copy(alpha = 0.12f))
            .clickable { action() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = if (selected) Color.Black.copy(alpha = 0.82f) else scheme.lightText, modifier = Modifier.size(20.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WallpaperInfoSheet(wallpaper: Wallpaper, onDismiss: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = scheme.paper,
        contentColor = scheme.ink,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.wallpaper_info), color = scheme.ink, fontSize = 22.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) }
            }
            InfoGroup {
                InfoLine(stringResource(R.string.resolution), "${wallpaper.width} x ${wallpaper.height}")
                InfoLine(stringResource(R.string.file_size), formatBytes(wallpaper.fileSize))
                InfoLine(stringResource(R.string.file_type), wallpaper.fileType.ifBlank { "-" }.uppercase())
                InfoLine(stringResource(R.string.dominant_color), wallpaper.dominantColor ?: "-")
            }
            InfoGroup {
                InfoLine(stringResource(R.string.like), "${wallpaper.likeCount}")
                InfoLine(stringResource(R.string.favorite), "${wallpaper.favoriteCount}")
                InfoLine(stringResource(R.string.download), "${wallpaper.downloadCount}")
                InfoLine(stringResource(R.string.engagement), "${wallpaper.viewCount}")
            }
        }
    }
}

@Composable
fun InfoGroup(content: @Composable () -> Unit) {
    val scheme = LocalArchiveScheme.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(scheme.paper2)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = { content() },
    )
}

@Composable
fun InfoLine(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, color = LocalArchiveScheme.current.muted)
        Text(value, color = LocalArchiveScheme.current.ink, fontWeight = FontWeight.SemiBold)
    }
}

fun formatBytes(size: Long): String {
    if (size <= 0) return "-"
    val mb = size / 1024.0 / 1024.0
    return "%.1f MB".format(mb)
}

fun startDownload(context: Context, wallpaper: Wallpaper, token: String) {
    runCatching {
        val request = DownloadManager.Request(Uri.parse(ApiClient.downloadEndpoint(wallpaper.id)))
            .addRequestHeader("Authorization", "Bearer $token")
            .setTitle(wallpaper.title)
            .setDescription("Wallpaper Exchange")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalPublicDir(Environment.DIRECTORY_PICTURES, "WallpaperExchange/${wallpaper.slug}.jpg")
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        manager.enqueue(request)
        Toast.makeText(context, context.getString(R.string.download_started), Toast.LENGTH_SHORT).show()
    }.onFailure {
        Toast.makeText(context, context.getString(R.string.download_failed), Toast.LENGTH_SHORT).show()
    }
}

suspend fun setAsWallpaper(context: Context, wallpaper: Wallpaper, token: String) = withContext(Dispatchers.IO) {
    runCatching {
        val connection = (URL(ApiClient.downloadEndpoint(wallpaper.id)).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15000
            readTimeout = 60000
            instanceFollowRedirects = true
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "image/*,*/*")
        }
        if (connection.responseCode >= 400) {
            throw ApiException("Wallpaper download failed", connection.responseCode)
        }
        connection.inputStream.use { input ->
            val manager = WallpaperManager.getInstance(context.applicationContext)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                manager.setStream(input, null, true, WallpaperManager.FLAG_SYSTEM)
            } else {
                manager.setStream(input)
            }
        }
    }.onSuccess {
        withContext(Dispatchers.Main) {
            Toast.makeText(context, context.getString(R.string.wallpaper_set), Toast.LENGTH_SHORT).show()
        }
    }.onFailure {
        withContext(Dispatchers.Main) {
            Toast.makeText(context, context.getString(R.string.wallpaper_set_failed), Toast.LENGTH_SHORT).show()
        }
    }
}

@Composable
fun AuthDialog(session: AuthSession, mode: AuthMode) {
    val scope = rememberCoroutineScope()
    var email by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = { if (!busy) session.dismissAuth() },
        confirmButton = {
            Button(
                enabled = !busy,
                onClick = {
                    scope.launch {
                        busy = true
                        error = null
                        runCatching {
                            if (mode == AuthMode.Login) session.login(email, password)
                            else session.register(username, email, password)
                        }.onFailure { error = it.message }
                        busy = false
                    }
                },
            ) {
                Text(if (mode == AuthMode.Login) stringResource(R.string.sign_in) else stringResource(R.string.register))
            }
        },
        dismissButton = { TextButton(onClick = { session.dismissAuth() }) { Text(stringResource(R.string.cancel)) } },
        title = { Text(if (mode == AuthMode.Login) stringResource(R.string.sign_in) else stringResource(R.string.register)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (mode == AuthMode.Register) {
                    OutlinedTextField(username, { username = it }, label = { Text(stringResource(R.string.username)) }, singleLine = true)
                }
                OutlinedTextField(email, { email = it }, label = { Text(stringResource(R.string.email)) }, singleLine = true)
                OutlinedTextField(password, { password = it }, label = { Text(stringResource(R.string.password)) }, singleLine = true)
                error?.let { Text(it, color = Color.Red) }
                TextButton(onClick = { session.present(if (mode == AuthMode.Login) AuthMode.Register else AuthMode.Login) }) {
                    Text(if (mode == AuthMode.Login) stringResource(R.string.register) else stringResource(R.string.sign_in))
                }
            }
        },
    )
}

@Composable
fun SignInGate(session: AuthSession) {
    val scheme = LocalArchiveScheme.current
    Column(
        Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Outlined.FavoriteBorder, contentDescription = null, tint = scheme.accentInk, modifier = Modifier.size(48.dp))
        Spacer(Modifier.height(12.dp))
        Text(stringResource(R.string.sign_in_required), color = scheme.ink, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.sign_in_message), color = scheme.muted, modifier = Modifier.padding(vertical = 8.dp))
        Button(onClick = { session.present(AuthMode.Login) }) { Text(stringResource(R.string.sign_in)) }
    }
}

@Composable
fun PagingFooter(isLoading: Boolean, hasMore: Boolean, onLoadMore: () -> Unit) {
    Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
        when {
            isLoading -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Text(stringResource(R.string.loading_more), color = LocalArchiveScheme.current.muted)
            }
            hasMore -> OutlinedButton(onClick = onLoadMore) { Text(stringResource(R.string.load_more)) }
            else -> Text(stringResource(R.string.all_loaded), color = LocalArchiveScheme.current.muted, fontSize = 12.sp)
        }
    }
}

@Composable
fun EmptyState() {
    Column(Modifier.fillMaxWidth().padding(36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(stringResource(R.string.no_matches), color = LocalArchiveScheme.current.ink, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.no_matches_message), color = LocalArchiveScheme.current.muted)
    }
}

@Composable
fun ErrorState(message: String, onRetry: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(message, color = LocalArchiveScheme.current.ink)
        TextButton(onClick = onRetry) { Text(stringResource(R.string.retry)) }
    }
}

@Composable
fun HomeSkeleton() {
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        SkeletonBlock(Modifier.height(316.dp).fillMaxWidth(), 28)
        WallpaperGridSkeleton(8)
        CollectionListSkeleton(4, 148)
    }
}

@Composable
fun WallpaperGridSkeleton(count: Int) {
    Column(Modifier.padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        repeat((count + 1) / 2) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.fillMaxWidth()) {
                SkeletonBlock(Modifier.weight(1f).aspectRatio(9f / 19.5f), 15)
                SkeletonBlock(Modifier.weight(1f).aspectRatio(9f / 19.5f), 15)
            }
        }
    }
}

@Composable
fun CollectionListSkeleton(count: Int, height: Int = 190) {
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        repeat(count) {
            SkeletonBlock(Modifier.height(height.dp).fillMaxWidth(), 18)
        }
    }
}

@Composable
fun WeeklyArchiveSkeleton() {
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        repeat(3) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SkeletonBlock(Modifier.weight(1f).aspectRatio(0.78f), 18)
                SkeletonBlock(Modifier.weight(1f).aspectRatio(0.78f), 18)
            }
        }
    }
}

@Composable
fun SkeletonBlock(modifier: Modifier, radius: Int) {
    val scheme = LocalArchiveScheme.current
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(radius.dp),
        color = scheme.paper3.copy(alpha = 0.72f),
        border = BorderStroke(1.dp, scheme.hair.copy(alpha = 0.60f)),
    ) {
        LoadingVeil(Modifier.fillMaxSize())
    }
}
