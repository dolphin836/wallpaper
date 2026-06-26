package com.wallpaperexchange.android

import android.app.DownloadManager
import android.app.WallpaperManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.LocaleList
import android.provider.OpenableColumns
import android.provider.Settings
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
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.AddCircle
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.Contrast
import androidx.compose.material.icons.outlined.Copyright
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Gavel
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Paid
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.PhoneIphone
import androidx.compose.material.icons.outlined.PrivacyTip
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material.icons.outlined.Upload
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.Wallpaper
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
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CoroutineScope(Dispatchers.IO).launch {
            ApiClient.trackEvent("app_launch", "/android")
        }
        setContent {
            val preferences = remember { AppPreferencesState(this) }
            AppLanguageProvider(preferences.language) {
                CompositionLocalProvider(LocalAppPreferences provides preferences) {
                    WallpaperExchangeTheme(themeMode = preferences.themeMode) {
                        WallpaperExchangeApp()
                    }
                }
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

enum class AppLanguage(val key: String, val tag: String?) {
    System("system", null),
    English("en", "en"),
    SimplifiedChinese("zh-Hans", "zh-CN"),
    TraditionalChinese("zh-Hant", "zh-TW"),
    Japanese("ja", "ja");

    companion object {
        fun fromKey(key: String?): AppLanguage =
            entries.firstOrNull { it.key == key } ?: System
    }
}

@Stable
class AppPreferencesState(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("wallx_preferences", Context.MODE_PRIVATE)

    var language by mutableStateOf(AppLanguage.fromKey(prefs.getString("language", AppLanguage.System.key)))
        private set
    var themeMode by mutableStateOf(AppThemeMode.fromKey(prefs.getString("theme_mode", AppThemeMode.System.key)))
        private set

    fun updateLanguage(value: AppLanguage) {
        prefs.edit().putString("language", value.key).apply()
        language = value
    }

    fun updateThemeMode(value: AppThemeMode) {
        prefs.edit().putString("theme_mode", value.key).apply()
        themeMode = value
    }
}

val LocalAppPreferences = staticCompositionLocalOf<AppPreferencesState> {
    error("AppPreferencesState is not provided")
}

@Composable
fun AppLanguageProvider(language: AppLanguage, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val baseConfiguration = LocalConfiguration.current
    val tag = language.tag
    if (tag == null) {
        content()
    } else {
        val localizedConfiguration = remember(baseConfiguration, tag) {
            Configuration(baseConfiguration).apply {
                setLocales(LocaleList.forLanguageTags(tag))
            }
        }
        val localizedContext = remember(context, localizedConfiguration) {
            context.createConfigurationContext(localizedConfiguration)
        }
        CompositionLocalProvider(
            LocalContext provides localizedContext,
            LocalConfiguration provides localizedConfiguration,
            content = content,
        )
    }
}

enum class ProfileDestination(val title: Int, val icon: ImageVector) {
    Downloads(R.string.my_downloads, Icons.Outlined.Download),
    Favorites(R.string.my_favorites, Icons.Outlined.FavoriteBorder),
    Uploads(R.string.my_uploads, Icons.Outlined.Upload),
    Likes(R.string.my_likes, Icons.Outlined.ThumbUp),
    Collections(R.string.my_collections, Icons.Outlined.Collections),
    Coins(R.string.my_coins, Icons.Outlined.Paid),
}

enum class LegalDocumentKind(val title: Int, val icon: ImageVector, val updated: Int) {
    Terms(R.string.terms_title, Icons.Outlined.Gavel, R.string.legal_updated_terms),
    Privacy(R.string.privacy_title, Icons.Outlined.PrivacyTip, R.string.legal_updated_terms),
    Dmca(R.string.dmca_title, Icons.Outlined.Copyright, R.string.legal_updated_dmca),
}

data class AndroidUploadItem(
    val id: String = UUID.randomUUID().toString(),
    val uri: Uri,
    val name: String,
    val fileSize: Long,
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

data class PendingApkDownload(
    val id: Long,
    val fileName: String,
    val release: AndroidRelease,
)

@Stable
class AndroidUpdateState(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("wallx_update", Context.MODE_PRIVATE)

    var release by mutableStateOf<AndroidRelease?>(null)
        private set
    var promptRelease by mutableStateOf<AndroidRelease?>(null)
        private set
    var pendingDownload by mutableStateOf<PendingApkDownload?>(null)
        private set
    var checking by mutableStateOf(false)
        private set
    var downloading by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    suspend fun check(manual: Boolean): AndroidRelease? {
        if (checking) return null
        checking = true
        error = null
        val result = runCatching { ApiClient.fetchAndroidRelease() }
        checking = false
        result.onSuccess { remote ->
            release = remote
            val hasUpdate = remote.versionCode > BuildConfig.VERSION_CODE
            val skipped = prefs.getInt("skipped_version_code", 0)
            if (hasUpdate && (manual || remote.forceUpdate || skipped < remote.versionCode)) {
                promptRelease = remote
                return remote
            }
        }.onFailure {
            error = it.message
        }
        return null
    }

    fun remindLater() {
        promptRelease = null
    }

    fun skipCurrentVersion() {
        promptRelease?.let { release ->
            prefs.edit().putInt("skipped_version_code", release.versionCode).apply()
        }
        promptRelease = null
    }

    fun beginDownload(context: Context, target: AndroidRelease) {
        val fileName = "WallpaperExchange-${target.versionName}.apk"
        downloading = true
        pendingDownload = startApkDownload(context, target, fileName)
        if (pendingDownload == null) downloading = false
    }

    fun finishDownload() {
        downloading = false
        promptRelease = null
        pendingDownload = null
    }
}

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

    suspend fun updateProfile(nickname: String, bio: String) {
        val current = token ?: throw ApiException("Sign in required", 401)
        user = ApiClient.updateProfile(nickname, bio, current)
    }

    suspend fun updateAvatar(context: Context, uri: Uri) {
        val current = token ?: throw ApiException("Sign in required", 401)
        val avatarUrl = uploadAvatar(context, uri, current)
        user = user?.copy(avatarUrl = avatarUrl)
    }

    suspend fun changePassword(oldPassword: String, newPassword: String) {
        val current = token ?: throw ApiException("Sign in required", 401)
        ApiClient.changePassword(oldPassword, newPassword, current)
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
    val updateState = remember { AndroidUpdateState(context.applicationContext) }
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
    LaunchedEffect(Unit) {
        updateState.check(manual = false)
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
                    updateState = updateState,
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

        detail?.let { wallpaper ->
            OverlaySurface {
                WallpaperDetailScreen(
                    initial = wallpaper,
                    session = session,
                    onClose = { detail = null },
                )
            }
        }

        AndroidUpdateDownloadWatcher(updateState)
        AndroidUpdateDialog(updateState)

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
fun AndroidUpdateDialog(updateState: AndroidUpdateState) {
    val context = LocalContext.current
    val release = updateState.promptRelease ?: return
    val notes = localizedReleaseNotes(release)
    AlertDialog(
        onDismissRequest = {
            if (!release.forceUpdate && !updateState.downloading) updateState.remindLater()
        },
        title = { Text(stringResource(R.string.update_available_title, release.versionName)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    stringResource(R.string.update_available_message, BuildConfig.VERSION_NAME, release.versionName),
                    color = LocalArchiveScheme.current.ink2,
                    fontSize = 14.sp,
                    lineHeight = 20.sp,
                )
                if (notes.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        notes.take(4).forEach { note ->
                            Text("• $note", color = LocalArchiveScheme.current.muted, fontSize = 13.sp, lineHeight = 18.sp)
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                enabled = !updateState.downloading,
                onClick = { updateState.beginDownload(context, release) },
            ) {
                if (updateState.downloading) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                } else {
                    Text(stringResource(R.string.download_update))
                }
            }
        },
        dismissButton = {
            if (!release.forceUpdate) {
                TextButton(onClick = { updateState.skipCurrentVersion() }, enabled = !updateState.downloading) {
                    Text(stringResource(R.string.skip_this_version))
                }
            }
        },
    )
}

@Composable
fun AndroidUpdateDownloadWatcher(updateState: AndroidUpdateState) {
    val context = LocalContext.current
    val pending = updateState.pendingDownload
    val installFailed = stringResource(R.string.install_open_failed)
    val allowInstall = stringResource(R.string.allow_unknown_apps)
    DisposableEffect(pending?.id) {
        if (pending == null) {
            onDispose {}
        } else {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
                    if (id != pending.id) return
                    updateState.finishDownload()
                    if (isDownloadSuccessful(context, pending.id)) {
                        installDownloadedApk(context, pending.fileName, allowInstall, installFailed)
                    } else {
                        Toast.makeText(context, context.getString(R.string.download_failed), Toast.LENGTH_SHORT).show()
                    }
                }
            }
            val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(receiver, filter)
            }
            onDispose { runCatching { context.unregisterReceiver(receiver) } }
        }
    }
}

@Composable
fun localizedReleaseNotes(release: AndroidRelease): List<String> {
    val configuration = LocalConfiguration.current
    val tag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        configuration.locales[0]?.toLanguageTag().orEmpty()
    } else {
        @Suppress("DEPRECATION")
        configuration.locale.toLanguageTag()
    }
    return release.notesI18n[tag]
        ?: release.notesI18n[tag.substringBefore("-")]
        ?: release.notes
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
            icon = Icons.AutoMirrored.Outlined.ArrowBack,
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
fun DetailTopBar(onBack: () -> Unit, onInfo: () -> Unit) {
    Row(
        modifier = Modifier
            .statusBarsPadding()
            .padding(12.dp)
            .fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TranslucentCircleButton(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.cancel), onBack)
        TranslucentCircleButton(Icons.Outlined.Info, stringResource(R.string.wallpaper_info), onInfo)
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
                                kicker = "",
                                title = stringResource(R.string.latest_wallpapers),
                                action = stringResource(R.string.see_more),
                                onAction = { onTab(RootTab.Discover) },
                            )
                            WallpaperGrid(wallpapers, onWallpaper)
                        }
                        if (collections.isNotEmpty()) {
                            SectionRow(
                                kicker = "",
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
        SectionRow("", stringResource(R.string.weekly), stringResource(R.string.see_more), onViewAll)
        Box(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
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
            .aspectRatio(1.12f)
            .then(paletteReactiveModifier(entry.colorPalette, entry.dominantColor ?: entry.accentColor))
            .clickable { onWeekly(entry) },
        contentAlignment = Alignment.BottomCenter,
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .clip(RoundedCornerShape(28.dp))
                .background(accent.copy(alpha = 0.72f))
        ) {
            RemoteImage(entry.coverUrl, Modifier.fillMaxSize(), placeholder = accent.copy(alpha = 0.50f))
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.08f), Color.Black.copy(alpha = 0.74f)))))
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
    updateState: AndroidUpdateState,
) {
    var showEditProfile by remember { mutableStateOf(false) }
    var showChangePassword by remember { mutableStateOf(false) }
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
                        onEdit = { showEditProfile = true },
                        onPassword = { showChangePassword = true },
                        onSignOut = { session.logout() },
                        onCoins = { onOpen(ProfileDestination.Coins) },
                    )
                }
                item { AccountNavigationCard(session.user!!, onOpen) }
                item { PreferencesCard(updateState) }
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
                PreferencesCard(updateState)
            }
        }
    }
    if (showEditProfile) {
        EditProfileDialog(session = session, onDismiss = { showEditProfile = false })
    }
    if (showChangePassword) {
        ChangePasswordDialog(session = session, onDismiss = { showChangePassword = false })
    }
}

@Composable
fun EditProfileDialog(session: AuthSession, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val user = session.user ?: return
    var nickname by remember(user.id) { mutableStateOf(user.nickname) }
    var bio by remember(user.id) { mutableStateOf(user.bio) }
    var avatarUri by remember(user.id) { mutableStateOf<Uri?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val avatarPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) avatarUri = uri
    }

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text(stringResource(R.string.edit_profile)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(Modifier.size(68.dp).clip(CircleShape).background(LocalArchiveScheme.current.paper3), contentAlignment = Alignment.Center) {
                        val preview = avatarUri?.toString() ?: user.avatarUrl
                        if (preview.isNotBlank()) {
                            RemoteImage(preview, Modifier.fillMaxSize())
                        } else {
                            Text((user.nickname.ifBlank { user.username }).take(1).uppercase(), color = LocalArchiveScheme.current.ink2, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    OutlinedButton(
                        enabled = !busy,
                        onClick = { avatarPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                    ) {
                        Icon(Icons.Outlined.PhotoCamera, contentDescription = null, modifier = Modifier.size(17.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.change_avatar))
                    }
                }
                OutlinedTextField(
                    value = nickname,
                    onValueChange = { nickname = it },
                    label = { Text(stringResource(R.string.nickname)) },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = bio,
                    onValueChange = { bio = it },
                    label = { Text(stringResource(R.string.bio)) },
                    minLines = 3,
                    maxLines = 5,
                )
                error?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
            }
        },
        confirmButton = {
            Button(
                enabled = !busy && nickname.length <= 64 && bio.length <= 500,
                onClick = {
                    scope.launch {
                        busy = true
                        error = null
                        runCatching {
                            session.updateProfile(nickname.trim(), bio.trim())
                            avatarUri?.let { session.updateAvatar(context, it) }
                        }.onSuccess {
                            onDismiss()
                        }.onFailure {
                            error = it.message
                        }
                        busy = false
                    }
                },
            ) {
                if (busy) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(stringResource(R.string.save))
            }
        },
        dismissButton = {
            TextButton(onClick = { if (!busy) onDismiss() }) { Text(stringResource(R.string.cancel)) }
        },
    )
}

@Composable
fun ChangePasswordDialog(session: AuthSession, onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    val mismatchText = stringResource(R.string.password_mismatch)
    val tooShortText = stringResource(R.string.password_too_short)
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        title = { Text(stringResource(R.string.change_password)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                PasswordTextField(
                    value = currentPassword,
                    onValueChange = { currentPassword = it },
                    label = stringResource(R.string.current_password),
                )
                PasswordTextField(
                    value = newPassword,
                    onValueChange = { newPassword = it },
                    label = stringResource(R.string.new_password),
                )
                PasswordTextField(
                    value = confirmPassword,
                    onValueChange = { confirmPassword = it },
                    label = stringResource(R.string.confirm_new_password),
                )
                error?.let { Text(it, color = Color.Red, fontSize = 12.sp) }
            }
        },
        confirmButton = {
            Button(
                enabled = !busy && currentPassword.isNotBlank() && newPassword.isNotBlank() && confirmPassword.isNotBlank(),
                onClick = {
                    when {
                        newPassword.length < 8 -> error = tooShortText
                        newPassword != confirmPassword -> error = mismatchText
                        else -> scope.launch {
                            busy = true
                            error = null
                            runCatching {
                                session.changePassword(currentPassword, newPassword)
                            }.onSuccess {
                                onDismiss()
                            }.onFailure {
                                error = it.message
                            }
                            busy = false
                        }
                    }
                },
            ) {
                if (busy) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp) else Text(stringResource(R.string.save))
            }
        },
        dismissButton = {
            TextButton(onClick = { if (!busy) onDismiss() }) { Text(stringResource(R.string.cancel)) }
        },
    )
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
            ProfileCoinBadge(coins = user.coins, onClick = onCoins)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ProfileActionButton(Icons.Outlined.Upload, stringResource(R.string.upload), accent = true, modifier = Modifier.weight(1f), onClick = onUpload)
            ProfileActionButton(Icons.Outlined.Person, stringResource(R.string.edit_profile), modifier = Modifier.weight(1f), onClick = onEdit)
            ProfileActionButton(Icons.Outlined.Key, stringResource(R.string.password), modifier = Modifier.weight(1f), onClick = onPassword)
            ProfileActionButton(Icons.Outlined.Close, stringResource(R.string.sign_out), modifier = Modifier.weight(1f), onClick = onSignOut)
        }
    }
}

@Composable
fun ProfileCoinBadge(coins: Int, onClick: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    val digits = coins.toString().length
    val numberSize = when {
        digits >= 5 -> 15.sp
        digits >= 4 -> 17.sp
        else -> 20.sp
    }
    Column(
        Modifier
            .height(54.dp)
            .widthIn(min = 62.dp, max = 88.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(scheme.accentSoft)
            .clickable { onClick() }
            .padding(horizontal = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            "$coins",
            color = scheme.accentInk,
            fontSize = numberSize,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(stringResource(R.string.coins), color = scheme.muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace, maxLines = 1)
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
fun PreferencesCard(updateState: AndroidUpdateState) {
    val scheme = LocalArchiveScheme.current
    val preferences = LocalAppPreferences.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val alreadyLatest = stringResource(R.string.already_latest)
    val checkFailed = stringResource(R.string.update_check_failed)
    var showLanguagePicker by remember { mutableStateOf(false) }
    var showThemePicker by remember { mutableStateOf(false) }
    var legalDocument by remember { mutableStateOf<LegalDocumentKind?>(null) }
    Column(Modifier.padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeader("", stringResource(R.string.settings))
        Column(Modifier.clip(RoundedCornerShape(18.dp)).background(scheme.paper2)) {
            AccountNavRow(
                Icons.Outlined.Language,
                stringResource(R.string.language),
                scheme.accentInk,
                detail = languageLabel(preferences.language),
            ) { showLanguagePicker = true }
            RowDivider()
            AccountNavRow(
                Icons.Outlined.Contrast,
                stringResource(R.string.appearance),
                scheme.accentInk,
                detail = themeModeLabel(preferences.themeMode),
            ) { showThemePicker = true }
            RowDivider()
            AccountNavRow(Icons.Outlined.Gavel, stringResource(R.string.terms_title), scheme.accentInk) { legalDocument = LegalDocumentKind.Terms }
            RowDivider()
            AccountNavRow(Icons.Outlined.PrivacyTip, stringResource(R.string.privacy_title), scheme.accentInk) { legalDocument = LegalDocumentKind.Privacy }
            RowDivider()
            AccountNavRow(Icons.Outlined.Copyright, stringResource(R.string.dmca_title), scheme.accentInk) { legalDocument = LegalDocumentKind.Dmca }
            RowDivider()
            AccountNavRow(
                Icons.Outlined.Download,
                stringResource(R.string.check_for_updates),
                scheme.accentInk,
                detail = if (updateState.checking) stringResource(R.string.checking_updates) else "v${BuildConfig.VERSION_NAME}",
            ) {
                scope.launch {
                    val found = updateState.check(manual = true)
                    if (found == null) {
                        Toast.makeText(
                            context,
                            if (updateState.error == null) alreadyLatest else checkFailed,
                            Toast.LENGTH_SHORT,
                        ).show()
                    }
                }
            }
        }
    }
    if (showLanguagePicker) {
        LanguagePickerDialog(
            selected = preferences.language,
            onSelect = {
                preferences.updateLanguage(it)
                showLanguagePicker = false
            },
            onDismiss = { showLanguagePicker = false },
        )
    }
    if (showThemePicker) {
        ThemePickerDialog(
            selected = preferences.themeMode,
            onSelect = {
                preferences.updateThemeMode(it)
                showThemePicker = false
            },
            onDismiss = { showThemePicker = false },
        )
    }
    legalDocument?.let { kind ->
        LegalDocumentDialog(kind = kind, onDismiss = { legalDocument = null })
    }
}

@Composable
fun LanguagePickerDialog(selected: AppLanguage, onSelect: (AppLanguage) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.select_language)) },
        text = {
            Column {
                AppLanguage.entries.forEach { language ->
                    PreferenceOption(
                        title = languageLabel(language),
                        selected = selected == language,
                        onClick = { onSelect(language) },
                    )
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
fun ThemePickerDialog(selected: AppThemeMode, onSelect: (AppThemeMode) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.select_theme)) },
        text = {
            Column {
                AppThemeMode.entries.forEach { mode ->
                    PreferenceOption(
                        title = themeModeLabel(mode),
                        selected = selected == mode,
                        onClick = { onSelect(mode) },
                    )
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
fun PreferenceOption(title: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .clickable { onClick() }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        RadioButton(selected = selected, onClick = onClick)
        Text(title, color = LocalArchiveScheme.current.ink, fontSize = 15.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
fun languageLabel(language: AppLanguage): String = when (language) {
    AppLanguage.System -> stringResource(R.string.language_system)
    AppLanguage.English -> stringResource(R.string.language_english)
    AppLanguage.SimplifiedChinese -> stringResource(R.string.language_simplified_chinese)
    AppLanguage.TraditionalChinese -> stringResource(R.string.language_traditional_chinese)
    AppLanguage.Japanese -> stringResource(R.string.language_japanese)
}

@Composable
fun themeModeLabel(mode: AppThemeMode): String = when (mode) {
    AppThemeMode.System -> stringResource(R.string.theme_system)
    AppThemeMode.Light -> stringResource(R.string.theme_light)
    AppThemeMode.Dark -> stringResource(R.string.theme_dark)
}

data class LegalSectionText(val title: String, val body: String)

@Composable
fun LegalDocumentDialog(kind: LegalDocumentKind, onDismiss: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    val title = stringResource(kind.title)
    val sections = legalSections(kind)
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            modifier = Modifier
                .fillMaxSize()
                .padding(12.dp)
                .statusBarsPadding()
                .navigationBarsPadding(),
            shape = RoundedCornerShape(24.dp),
            color = scheme.paper,
            border = BorderStroke(1.dp, scheme.hair.copy(alpha = 0.72f)),
        ) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    CircleIconButton(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.cancel), false, onDismiss)
                    Text(title, color = scheme.ink, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 18.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(stringResource(R.string.legal), color = scheme.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
                            Text(title, color = scheme.ink, fontSize = 28.sp, fontWeight = FontWeight.Black)
                            Text("${stringResource(R.string.legal_version)} v1.0 · ${stringResource(kind.updated)}", color = scheme.muted, fontSize = 13.sp)
                            Text(stringResource(R.string.legal_body_note), color = scheme.ink2, fontSize = 13.sp, lineHeight = 19.sp)
                        }
                    }
                    items(sections) { section ->
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(section.title, color = scheme.ink, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                            Text(section.body, color = scheme.ink2, fontSize = 14.sp, lineHeight = 21.sp)
                        }
                    }
                    item { Spacer(Modifier.height(10.dp)) }
                }
            }
        }
    }
}

@Composable
fun legalSections(kind: LegalDocumentKind): List<LegalSectionText> = when (kind) {
    LegalDocumentKind.Terms -> listOf(
        LegalSectionText(stringResource(R.string.terms_section_acceptance_title), stringResource(R.string.terms_section_acceptance_body)),
        LegalSectionText(stringResource(R.string.terms_section_account_title), stringResource(R.string.terms_section_account_body)),
        LegalSectionText(stringResource(R.string.terms_section_content_title), stringResource(R.string.terms_section_content_body)),
        LegalSectionText(stringResource(R.string.terms_section_coins_title), stringResource(R.string.terms_section_coins_body)),
        LegalSectionText(stringResource(R.string.terms_section_contact_title), stringResource(R.string.terms_section_contact_body)),
    )
    LegalDocumentKind.Privacy -> listOf(
        LegalSectionText(stringResource(R.string.privacy_section_collect_title), stringResource(R.string.privacy_section_collect_body)),
        LegalSectionText(stringResource(R.string.privacy_section_use_title), stringResource(R.string.privacy_section_use_body)),
        LegalSectionText(stringResource(R.string.privacy_section_share_title), stringResource(R.string.privacy_section_share_body)),
        LegalSectionText(stringResource(R.string.privacy_section_rights_title), stringResource(R.string.privacy_section_rights_body)),
        LegalSectionText(stringResource(R.string.privacy_section_contact_title), stringResource(R.string.privacy_section_contact_body)),
    )
    LegalDocumentKind.Dmca -> listOf(
        LegalSectionText(stringResource(R.string.dmca_section_notice_title), stringResource(R.string.dmca_section_notice_body)),
        LegalSectionText(stringResource(R.string.dmca_section_counter_title), stringResource(R.string.dmca_section_counter_body)),
        LegalSectionText(stringResource(R.string.dmca_section_repeat_title), stringResource(R.string.dmca_section_repeat_body)),
        LegalSectionText(stringResource(R.string.dmca_section_contact_title), stringResource(R.string.dmca_section_contact_body)),
    )
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
    val maxFiles = 20
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(20)) { uris ->
        val existing = queue.map { it.uri }.toSet()
        val additions = uris
            .filterNot { it in existing }
            .take(maxFiles - queue.size)
            .map { uri -> uploadItem(context, uri) }
        if (additions.isNotEmpty()) queue = queue + additions
    }

    fun needsUpload(item: AndroidUploadItem): Boolean =
        item.status == UploadStatus.Ready || item.status == UploadStatus.Failed

    suspend fun submit() {
        val token = session.token
        if (token == null) {
            session.present(AuthMode.Login)
            return
        }
        uploading = true
        error = null
        for (item in queue.filter(::needsUpload)) {
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

    val doneCount = queue.count { it.status == UploadStatus.Success }
    val failedCount = queue.count { it.status == UploadStatus.Failed }
    val readyCount = queue.count(::needsUpload)
    val allDone = queue.isNotEmpty() && doneCount == queue.size
    val slots = maxOf(0, maxFiles - queue.size)

    Column(Modifier.fillMaxSize()) {
        ArchiveTopBar(stringResource(R.string.upload), onProfile = {}, onClose = onClose, session = session)
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 12.dp, top = 8.dp, end = 12.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                SectionHeader(
                    kicker = stringResource(R.string.upload_kicker),
                    title = stringResource(R.string.upload),
                    modifier = Modifier.padding(top = 6.dp),
                )
            }
            if (!session.isLoggedIn) {
                item { UploadSignedOutPrompt(session) }
            } else {
                item {
                    UploadPickerCard(
                        queueCount = queue.size,
                        maxFiles = maxFiles,
                        enabled = !uploading && slots > 0,
                        onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                    )
                }
                if (queue.isNotEmpty()) {
                    item {
                        UploadQueueSection(
                            queue = queue,
                            uploading = uploading,
                            onRemove = { item ->
                                if (!uploading) queue = queue.filterNot { it.id == item.id }
                            },
                        )
                    }
                    item {
                        UploadControlCard(
                            queueSize = queue.size,
                            readyCount = readyCount,
                            doneCount = doneCount,
                            failedCount = failedCount,
                            uploading = uploading,
                            allDone = allDone,
                            error = error,
                            onSubmit = { scope.launch { submit() } },
                            onClear = {
                                queue = emptyList()
                                error = null
                            },
                        )
                    }
                }
                item { UploadRulesCard() }
            }
        }
    }
}

@Composable
fun UploadSignedOutPrompt(session: AuthSession) {
    val scheme = LocalArchiveScheme.current
    Column(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Outlined.Upload, contentDescription = null, tint = scheme.muted, modifier = Modifier.size(44.dp))
        Text(
            stringResource(R.string.upload_signed_out_message),
            color = scheme.muted,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            lineHeight = 20.sp,
        )
        Button(onClick = { session.present(AuthMode.Login) }) {
            Text(stringResource(R.string.sign_in))
        }
    }
}

@Composable
fun UploadPickerCard(queueCount: Int, maxFiles: Int, enabled: Boolean, onClick: () -> Unit) {
    val scheme = LocalArchiveScheme.current
    val empty = queueCount == 0
    val tint = if (enabled) scheme.accentInk else scheme.muted
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .clickable(enabled = enabled) { onClick() },
        shape = RoundedCornerShape(16.dp),
        color = Color.Transparent,
        border = BorderStroke(1.5.dp, if (enabled) scheme.accentInk.copy(alpha = 0.42f) else scheme.hair),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = if (empty) 40.dp else 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (empty) 9.dp else 7.dp),
        ) {
            Icon(
                imageVector = if (empty) Icons.Outlined.Upload else Icons.Outlined.AddCircle,
                contentDescription = null,
                tint = tint,
                modifier = Modifier.size(if (empty) 34.dp else 22.dp),
            )
            Text(
                if (empty) stringResource(R.string.choose_photos) else stringResource(R.string.upload_add_more_photos, queueCount, maxFiles),
                color = tint,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
            )
            Text(
                stringResource(R.string.upload_batch_hint, maxFiles),
                color = scheme.muted,
                fontSize = 12.sp,
                lineHeight = 17.sp,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                maxLines = 2,
            )
        }
    }
}

@Composable
fun UploadQueueSection(
    queue: List<AndroidUploadItem>,
    uploading: Boolean,
    onRemove: (AndroidUploadItem) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeader(
            kicker = stringResource(R.string.selected_photos, queue.size),
            title = stringResource(R.string.upload_queue_title),
        )
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            queue.chunked(2).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { item ->
                        UploadQueueTile(
                            item = item,
                            uploading = uploading,
                            onRemove = { onRemove(item) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
fun UploadQueueTile(
    item: AndroidUploadItem,
    uploading: Boolean,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scheme = LocalArchiveScheme.current
    val border = when (item.status) {
        UploadStatus.Ready -> scheme.hair
        UploadStatus.Uploading -> scheme.accentInk.copy(alpha = 0.78f)
        UploadStatus.Success -> Color(0xFF2E8B57).copy(alpha = 0.68f)
        UploadStatus.Failed -> Color(0xFFC84C31).copy(alpha = 0.72f)
    }
    Column(
        modifier,
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(9f / 16.8f)
                .clip(RoundedCornerShape(14.dp))
                .background(scheme.paper3),
        ) {
            RemoteImage(item.uri.toString(), Modifier.fillMaxSize())
            when (item.status) {
                UploadStatus.Ready -> Unit
                UploadStatus.Uploading -> UploadStatusVeil()
                UploadStatus.Success -> UploadStatusBadge(Icons.Outlined.CheckCircle, Color(0xFF2E8B57))
                UploadStatus.Failed -> UploadStatusBadge(Icons.Outlined.ErrorOutline, Color(0xFFC84C31))
            }
            if (!uploading && item.status != UploadStatus.Success) {
                IconButton(
                    onClick = onRemove,
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.55f)),
                ) {
                    Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.cancel), tint = scheme.lightText, modifier = Modifier.size(14.dp))
                }
            }
        }
        Text(
            uploadTileMeta(item),
            color = scheme.muted,
            fontSize = 10.sp,
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (item.status == UploadStatus.Failed) {
            Text(uploadStatusText(item.status), color = Color(0xFFC84C31), fontSize = 11.sp, maxLines = 2)
        }
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp),
            color = border,
            content = {},
        )
    }
}

@Composable
fun UploadStatusVeil() {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.34f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CircularProgressIndicator(Modifier.size(26.dp), strokeWidth = 2.dp, color = LocalArchiveScheme.current.lightText)
            Text(stringResource(R.string.uploading), color = LocalArchiveScheme.current.lightText, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
fun UploadStatusBadge(icon: ImageVector, tint: Color) {
    Box(
        Modifier
            .padding(7.dp)
            .size(36.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.34f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(23.dp))
    }
}

@Composable
fun UploadControlCard(
    queueSize: Int,
    readyCount: Int,
    doneCount: Int,
    failedCount: Int,
    uploading: Boolean,
    allDone: Boolean,
    error: String?,
    onSubmit: () -> Unit,
    onClear: () -> Unit,
) {
    val scheme = LocalArchiveScheme.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(scheme.paper2)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            when {
                uploading -> {
                    CircularProgressIndicator(Modifier.size(17.dp), strokeWidth = 2.dp, color = scheme.accentInk)
                    Spacer(Modifier.width(8.dp))
                    Text(
                        "${doneCount}/${queueSize}",
                        color = scheme.muted,
                        fontSize = 12.sp,
                        fontFamily = FontFamily.Monospace,
                        modifier = Modifier.weight(1f),
                    )
                }
                allDone -> {
                    Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = Color(0xFF2E8B57), modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.upload_all_done), color = Color(0xFF2E8B57), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                }
                else -> {
                    Text(stringResource(R.string.upload_ready_count, readyCount), color = scheme.ink, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    if (doneCount > 0) {
                        Text(" · ${stringResource(R.string.upload_done_count, doneCount)}", color = Color(0xFF2E8B57), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                    if (failedCount > 0) {
                        Text(" · ${stringResource(R.string.upload_failed_count, failedCount)}", color = Color(0xFFC84C31), fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                    Spacer(Modifier.weight(1f))
                }
            }
        }
        error?.let {
            Text(it, color = Color(0xFFC84C31), fontSize = 12.sp, lineHeight = 17.sp)
        }
        if (allDone) {
            OutlinedButton(onClick = onClear, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Outlined.AddCircle, contentDescription = null, modifier = Modifier.size(17.dp))
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.upload_another))
            }
        } else {
            Button(
                enabled = !uploading && readyCount > 0,
                onClick = onSubmit,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Outlined.Upload, contentDescription = null, modifier = Modifier.size(17.dp))
                Spacer(Modifier.width(8.dp))
                Text(uploadButtonTitle(readyCount, failedCount))
            }
        }
    }
}

@Composable
fun UploadRulesCard() {
    val scheme = LocalArchiveScheme.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(scheme.paper2)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Text(stringResource(R.string.upload_rules_title), color = scheme.muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
        Text("- ${stringResource(R.string.upload_rule_licensed)}", color = scheme.ink2, fontSize = 12.sp)
        Text("- ${stringResource(R.string.upload_rule_no_watermarks)}", color = scheme.ink2, fontSize = 12.sp)
        Text("- ${stringResource(R.string.upload_rule_resolution)}", color = scheme.ink2, fontSize = 12.sp)
        Text("- ${stringResource(R.string.upload_rule_review)}", color = scheme.ink2, fontSize = 12.sp)
    }
}

@Composable
fun uploadButtonTitle(readyCount: Int, failedCount: Int): String = when {
    failedCount > 0 && readyCount == failedCount -> stringResource(R.string.upload_retry_failed)
    readyCount <= 1 -> stringResource(R.string.upload)
    else -> stringResource(R.string.upload_upload_many, readyCount)
}

@Composable
fun uploadStatusText(status: UploadStatus): String = when (status) {
    UploadStatus.Ready -> stringResource(R.string.upload_ready)
    UploadStatus.Uploading -> stringResource(R.string.uploading)
    UploadStatus.Success -> stringResource(R.string.upload_done)
    UploadStatus.Failed -> stringResource(R.string.upload_failed_short)
}

fun uploadTileMeta(item: AndroidUploadItem): String =
    "${item.name} · ${formatBytes(item.fileSize)}"

fun uploadItem(context: Context, uri: Uri): AndroidUploadItem =
    AndroidUploadItem(uri = uri, name = displayName(context, uri), fileSize = fileSize(context, uri))

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

fun fileSize(context: Context, uri: Uri): Long {
    val resolver = context.contentResolver
    resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
        val index = cursor.getColumnIndex(OpenableColumns.SIZE)
        if (index >= 0 && cursor.moveToFirst()) {
            return cursor.getLong(index)
        }
    }
    return 0
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

suspend fun uploadAvatar(context: Context, uri: Uri, token: String): String = withContext(Dispatchers.IO) {
    val resolver = context.contentResolver
    val mime = resolver.getType(uri) ?: "image/jpeg"
    val boundary = "Boundary-${UUID.randomUUID()}"
    val connection = (URL("$API_BASE_URL/users/me/avatar").openConnection() as HttpURLConnection).apply {
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
        write("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n")
        write("Content-Type: $mime\r\n\r\n")
        resolver.openInputStream(uri)?.use { input -> input.copyTo(output) } ?: throw ApiException("Cannot open selected photo")
        write("\r\n--$boundary--\r\n")
    }
    val status = connection.responseCode
    val stream = if (status >= 400) connection.errorStream else connection.inputStream
    val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
    val json = if (text.isBlank()) JSONObject() else JSONObject(text)
    if (status >= 400) {
        throw ApiException(json.optString("message").ifBlank { "Avatar upload failed" }, status)
    }
    json.optJSONObject("data")?.optString("avatar_url").orEmpty().ifBlank {
        throw ApiException("Avatar upload failed", status)
    }
}

private const val API_BASE_URL = "https://wallpaperexchange.com/api/v1"

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
            Text(coinTransactionTitle(tx), color = scheme.ink, fontWeight = FontWeight.SemiBold)
            Text("${tx.createdAt.take(10)} · ${stringResource(R.string.coin_ledger_balance, tx.balance)}", color = scheme.muted, fontSize = 12.sp)
        }
    }
}

@Composable
fun coinTransactionTitle(tx: CoinTransaction): String = when (tx.txType) {
    "register_bonus" -> stringResource(R.string.coin_tx_register_bonus)
    "upload_reward" -> stringResource(R.string.coin_tx_upload_reward)
    "download_cost", "download_spent" -> stringResource(R.string.coin_tx_download_cost)
    "download_earned", "download_received" -> stringResource(R.string.coin_tx_download_earned)
    "admin_grant" -> stringResource(R.string.coin_tx_admin_grant)
    else -> tx.description.ifBlank { tx.txType }
}

@Composable
fun WallpaperGrid(wallpapers: List<Wallpaper>, onWallpaper: (Wallpaper) -> Unit) {
    Column(Modifier.padding(horizontal = 14.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        wallpapers.chunked(2).forEachIndexed { rowIndex, row ->
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.fillMaxWidth()) {
                row.forEachIndexed { columnIndex, wallpaper ->
                    WallpaperCard(
                        wallpaper = wallpaper,
                        onWallpaper = onWallpaper,
                        modifier = Modifier.weight(1f),
                        index = rowIndex * 2 + columnIndex,
                    )
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun WallpaperCard(wallpaper: Wallpaper, onWallpaper: (Wallpaper) -> Unit, modifier: Modifier = Modifier, index: Int = 0) {
    val scheme = LocalArchiveScheme.current
    val lockPreview = LocalLockPreviewState.current
    val tint = hexColor(wallpaper.dominantColor, scheme.paper3)
    var entered by remember(wallpaper.id) { mutableStateOf(false) }
    val delayMillis = (index.coerceAtMost(7) * 34)
    val cardAlpha by animateFloatAsState(
        targetValue = if (entered) 1f else 0f,
        animationSpec = tween(durationMillis = 260, delayMillis = delayMillis),
        label = "wallpaper-card-alpha",
    )
    val cardScale by animateFloatAsState(
        targetValue = if (entered) 1f else 0.965f,
        animationSpec = tween(durationMillis = 280, delayMillis = delayMillis),
        label = "wallpaper-card-scale",
    )
    LaunchedEffect(wallpaper.id) {
        entered = true
    }
    Box(
        modifier
            .alpha(cardAlpha)
            .scale(cardScale)
            .aspectRatio(9f / 19.5f)
            .then(paletteReactiveModifier(wallpaper.colorPalette, wallpaper.dominantColor))
            .clip(RoundedCornerShape(15.dp))
            .background(tint.copy(alpha = 0.65f))
            .clickable { onWallpaper(wallpaper) },
    ) {
        RemoteImage(
            url = wallpaper.previewUrl.ifBlank { wallpaper.thumbUrl },
            modifier = Modifier.fillMaxSize(),
            placeholder = tint.copy(alpha = 0.55f),
            fallbackUrl = wallpaper.thumbUrl,
            showLoadingOverFallback = true,
        )
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
            url = tiles.getOrNull(0)?.previewUrl ?: collection.coverUrl,
            modifier = Modifier.weight(0.62f).fillMaxHeight().clip(RoundedCornerShape(10.dp)),
            placeholder = accent.copy(alpha = 0.35f),
            fallbackUrl = tiles.getOrNull(0)?.thumbUrl,
            showLoadingOverFallback = true,
        )
        Column(Modifier.weight(0.38f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            RemoteImage(
                url = tiles.getOrNull(1)?.previewUrl,
                modifier = Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(9.dp)),
                placeholder = accent.copy(alpha = 0.24f),
                fallbackUrl = tiles.getOrNull(1)?.thumbUrl,
                showLoadingOverFallback = true,
            )
            RemoteImage(
                url = tiles.getOrNull(2)?.previewUrl,
                modifier = Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(9.dp)),
                placeholder = accent.copy(alpha = 0.30f),
                fallbackUrl = tiles.getOrNull(2)?.thumbUrl,
                showLoadingOverFallback = true,
            )
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
    val previewUrl = initial.displayUrl
    val fullImageUrl = wallpaper.originalUrl.ifBlank { wallpaper.displayUrl }
    LaunchedEffect(initial.slug) {
        runCatching { ApiClient.fetchWallpaperDetail(initial.slug) }.onSuccess { detail = it }
    }
    Box(Modifier.fillMaxSize().background(hexColor(wallpaper.dominantColor, scheme.paper3))) {
        RemoteImage(
            url = fullImageUrl,
            modifier = Modifier.fillMaxSize(),
            placeholder = hexColor(wallpaper.dominantColor, scheme.paper3),
            fallbackUrl = previewUrl,
            cacheTarget = false,
        )
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.35f), Color.Transparent, Color.Black.copy(alpha = 0.62f)))))
        if (showDevicePreview) {
            LockScreenOverlay(compact = false, modifier = Modifier.fillMaxSize())
        }
        DetailTopBar(
            onBack = onClose,
            onInfo = { showInfo = true },
        )
        DetailToolbar(
            modifier = Modifier.align(Alignment.BottomCenter).padding(18.dp).navigationBarsPadding(),
            previewActive = showDevicePreview,
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
            onPreview = { showDevicePreview = !showDevicePreview },
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
    previewActive: Boolean,
    onDownload: () -> Unit,
    onLike: () -> Unit,
    onFavorite: () -> Unit,
    onPreview: () -> Unit,
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
        ToolbarButton(Icons.Outlined.PhoneIphone, stringResource(R.string.preview), onPreview, scheme, selected = previewActive)
        ToolbarButton(Icons.Outlined.Download, stringResource(R.string.download), onDownload, scheme, selected = true)
        ToolbarButton(Icons.Outlined.Wallpaper, stringResource(R.string.set_wallpaper), onSetWallpaper, scheme, selected = true)
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
                InfoLine(stringResource(R.string.views), "${wallpaper.viewCount}")
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
            .addRequestHeader("X-Wallpaper-Client", "android")
            .addRequestHeader("User-Agent", "WallpaperExchange/android ${BuildConfig.VERSION_NAME}")
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

fun startApkDownload(context: Context, release: AndroidRelease, fileName: String): PendingApkDownload? =
    runCatching {
        val uri = androidReleaseApkUri(release)
        val target = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), fileName)
        if (target.exists()) target.delete()
        val request = DownloadManager.Request(uri)
            .setTitle(context.getString(R.string.update_download_title, release.versionName))
            .setDescription(context.getString(R.string.update_download_description))
            .setMimeType(APK_MIME)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, fileName)
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        PendingApkDownload(manager.enqueue(request), fileName, release).also {
            Toast.makeText(context, context.getString(R.string.update_download_started), Toast.LENGTH_SHORT).show()
        }
    }.getOrElse {
        Toast.makeText(context, context.getString(R.string.download_failed), Toast.LENGTH_SHORT).show()
        null
    }

fun androidReleaseApkUri(release: AndroidRelease): Uri {
    val url = release.apkUrl
    return Uri.parse(
        if (url.startsWith("http://") || url.startsWith("https://")) {
            url
        } else {
            "https://wallpaperexchange.com$url"
        }
    )
}

fun isDownloadSuccessful(context: Context, id: Long): Boolean {
    val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    manager.query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
        if (cursor.moveToFirst()) {
            val statusIndex = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
            return statusIndex >= 0 && cursor.getInt(statusIndex) == DownloadManager.STATUS_SUCCESSFUL
        }
    }
    return false
}

fun installDownloadedApk(context: Context, fileName: String, allowInstallText: String, failedText: String) {
    runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !context.packageManager.canRequestPackageInstalls()) {
            Toast.makeText(context, allowInstallText, Toast.LENGTH_LONG).show()
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            return
        }
        val file = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), fileName)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(intent)
    }.onFailure {
        Toast.makeText(context, failedText, Toast.LENGTH_SHORT).show()
    }
}

private const val APK_MIME = "application/vnd.android.package-archive"

suspend fun setAsWallpaper(context: Context, wallpaper: Wallpaper, token: String) = withContext(Dispatchers.IO) {
    runCatching {
        val connection = (URL(ApiClient.downloadEndpoint(wallpaper.id)).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15000
            readTimeout = 60000
            instanceFollowRedirects = true
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "image/*,*/*")
            setRequestProperty("X-Wallpaper-Client", "android")
            setRequestProperty("User-Agent", "WallpaperExchange/android ${BuildConfig.VERSION_NAME}")
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
                PasswordTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = stringResource(R.string.password),
                    resetKey = mode,
                )
                error?.let { Text(it, color = Color.Red) }
                TextButton(onClick = { session.present(if (mode == AuthMode.Login) AuthMode.Register else AuthMode.Login) }) {
                    Text(if (mode == AuthMode.Login) stringResource(R.string.register) else stringResource(R.string.sign_in))
                }
            }
        },
    )
}

@Composable
fun PasswordTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    resetKey: Any? = Unit,
) {
    var passwordVisible by remember(resetKey) { mutableStateOf(false) }
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        singleLine = true,
        visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        trailingIcon = {
            val iconLabel = stringResource(if (passwordVisible) R.string.hide_password else R.string.show_password)
            IconButton(onClick = { passwordVisible = !passwordVisible }) {
                Icon(
                    imageVector = if (passwordVisible) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                    contentDescription = iconLabel,
                )
            }
        },
        modifier = modifier,
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
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            SkeletonBlock(Modifier.fillMaxWidth().aspectRatio(1.12f), 28)
        }
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
