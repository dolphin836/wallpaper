# Wallpaper Exchange Android

Native Android client scaffolded with Kotlin and Jetpack Compose.

## Requirements

- Android Studio Koala or newer
- JDK 17
- Android SDK 35

## Run

Open the `android` directory in Android Studio, let Gradle sync, then run the `app` configuration on a simulator or device.

The app points at `https://wallpaperexchange.com/api/v1`, matching the iOS client.

## Release APK

From the repository root, run:

```bash
./release-android.sh
```

The task builds the installable APK, copies it to `frontend/public/downloads/android/WallpaperExchange-<version>.apk`, updates `backend/internal/handler/android_release.json`, and removes superseded APKs from the static download folder.
