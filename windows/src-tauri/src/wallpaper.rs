// Wallpaper application. The static-image path uses Win32's
// SystemParametersInfoW(SPI_SETDESKWALLPAPER), available since
// Windows 95. Multi-monitor per-display wallpapers + the video
// (WorkerW reparenting) path will land in a later commit.
//
// The whole platform-specific block is cfg-gated on
// target_os = "windows" so cargo dev on macOS / Linux still
// compiles. On non-Windows the command returns Ok but only logs.

use tauri::{AppHandle, Runtime};

use crate::downloads;

#[tauri::command]
pub fn set_static_wallpaper(path: String) -> Result<(), String> {
    set_static_wallpaper_impl(&path).map_err(|e| e.to_string())
}

/// High-level "apply wallpaper by id". The React layer hands us the
/// wallpaper id and the original URL; we look the file up in
/// downloads (downloading first if missing) and call SystemParameters
/// Info. The Downloaded column will show the local copy on next
/// list_downloaded poll.
#[tauri::command]
pub async fn set_wallpaper_by_id<R: Runtime>(
    app: AppHandle<R>,
    id: i64,
    url: String,
) -> Result<String, String> {
    // Reuse the existing download command — idempotent + Ok if the
    // file is already local.
    let path = downloads::download_wallpaper(app.clone(), id, url).await?;
    let pb = std::path::PathBuf::from(&path);
    if !downloads::is_settable_static(&pb) {
        return Err(
            "This wallpaper isn't a still image — the Windows desktop wallpaper API only \
             accepts JPG / PNG / BMP / WebP. Video wallpaper support is coming soon."
                .to_string(),
        );
    }
    set_static_wallpaper_impl(&path).map_err(|e| e.to_string())?;
    Ok(path)
}

#[cfg(target_os = "windows")]
fn set_static_wallpaper_impl(path: &str) -> Result<(), Box<dyn std::error::Error>> {
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;
    use windows::core::PCWSTR;
    use windows::Win32::UI::WindowsAndMessaging::{
        SystemParametersInfoW, SPI_SETDESKWALLPAPER, SPIF_SENDCHANGE, SPIF_UPDATEINIFILE,
    };

    // SPI_SETDESKWALLPAPER wants a NUL-terminated wide string.
    let wide: Vec<u16> = OsStr::new(path).encode_wide().chain(Some(0)).collect();

    unsafe {
        SystemParametersInfoW(
            SPI_SETDESKWALLPAPER,
            0,
            Some(wide.as_ptr() as *mut _),
            SPIF_UPDATEINIFILE | SPIF_SENDCHANGE,
        )?;
    }
    log::info!("set static wallpaper: {}", path);
    Ok(())
}

#[cfg(not(target_os = "windows"))]
fn set_static_wallpaper_impl(_path: &str) -> Result<(), Box<dyn std::error::Error>> {
    // Dev mode on macOS / Linux. Log the call so the React side can
    // verify the IPC works without actually changing the wallpaper.
    log::info!("set static wallpaper (no-op on non-Windows): {}", _path);
    Ok(())
}
