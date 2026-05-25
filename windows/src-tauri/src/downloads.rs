// Local download storage + Tauri commands the React layer invokes
// for the Download / Set actions. Files land in the user's local
// AppData directory under Downloads/, keyed by wallpaper id +
// extension so subsequent re-downloads are idempotent.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use serde::Serialize;
use tauri::{AppHandle, Manager, Runtime};

const DOWNLOADS_SUBDIR: &str = "Downloads";

/// Resolve %LOCALAPPDATA%\WallpaperExchange\Downloads (Windows) or
/// equivalent app-local data dir on other platforms.
pub fn downloads_dir<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf, String> {
    let base = app
        .path()
        .app_local_data_dir()
        .map_err(|e| format!("locate app local data dir: {e}"))?;
    let dir = base.join(DOWNLOADS_SUBDIR);
    fs::create_dir_all(&dir).map_err(|e| format!("mkdir {dir:?}: {e}"))?;
    Ok(dir)
}

/// File name we use on disk for a given wallpaper. Pulling the
/// extension out of `original_url` keeps the file recognizable on
/// disk + preserves the playback behavior of the Set step (Windows
/// can't apply a video as a static wallpaper, but a JPG/PNG works).
fn local_filename(id: i64, original_url: &str) -> String {
    let ext = original_url
        .rsplit('/')
        .next()
        .and_then(|name| name.rsplit_once('.').map(|(_, e)| e))
        .filter(|e| !e.contains('?') && e.len() < 8)
        .unwrap_or("jpg");
    format!("{id}.{ext}")
}

#[derive(Debug, Serialize)]
pub struct DownloadedItem {
    pub id: i64,
    pub path: String,
}

/// Download a wallpaper to local disk. Idempotent — if the file
/// already exists with non-zero size, returns its path without
/// re-fetching. The React layer is responsible for tracking which
/// IDs are downloaded; this command is just I/O.
#[tauri::command]
pub async fn download_wallpaper<R: Runtime>(
    app: AppHandle<R>,
    id: i64,
    url: String,
) -> Result<String, String> {
    let dir = downloads_dir(&app)?;
    let path = dir.join(local_filename(id, &url));
    if path.exists() && fs::metadata(&path).map(|m| m.len() > 0).unwrap_or(false) {
        return Ok(path.to_string_lossy().to_string());
    }
    let bytes = reqwest::get(&url)
        .await
        .map_err(|e| format!("fetch {url}: {e}"))?
        .bytes()
        .await
        .map_err(|e| format!("read body: {e}"))?;
    let mut f = fs::File::create(&path).map_err(|e| format!("create {path:?}: {e}"))?;
    f.write_all(&bytes).map_err(|e| format!("write {path:?}: {e}"))?;
    Ok(path.to_string_lossy().to_string())
}

/// Enumerate everything in the downloads dir. Returns the wallpaper
/// id parsed off each filename so the React layer can intersect
/// with the server list to render the Downloaded column.
#[tauri::command]
pub fn list_downloaded<R: Runtime>(app: AppHandle<R>) -> Result<Vec<DownloadedItem>, String> {
    let dir = downloads_dir(&app)?;
    let mut items = Vec::new();
    let entries = match fs::read_dir(&dir) {
        Ok(e) => e,
        Err(_) => return Ok(items),
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
            if let Ok(id) = stem.parse::<i64>() {
                items.push(DownloadedItem {
                    id,
                    path: path.to_string_lossy().to_string(),
                });
            }
        }
    }
    Ok(items)
}

/// Remove a previously-downloaded wallpaper from local disk.
#[tauri::command]
pub fn remove_downloaded<R: Runtime>(app: AppHandle<R>, id: i64) -> Result<(), String> {
    let dir = downloads_dir(&app)?;
    for entry in fs::read_dir(&dir).map_err(|e| e.to_string())?.flatten() {
        let path = entry.path();
        let stem_matches = path
            .file_stem()
            .and_then(|s| s.to_str())
            .and_then(|s| s.parse::<i64>().ok())
            == Some(id);
        if stem_matches {
            fs::remove_file(&path).map_err(|e| format!("remove {path:?}: {e}"))?;
        }
    }
    Ok(())
}

/// Bytes-on-disk total for the downloads dir. Surfaces in the footer
/// matching the macOS client's storage indicator.
#[tauri::command]
pub fn downloads_total_bytes<R: Runtime>(app: AppHandle<R>) -> Result<u64, String> {
    let dir = downloads_dir(&app)?;
    let mut total = 0u64;
    for entry in fs::read_dir(&dir).map_err(|e| e.to_string())?.flatten() {
        if let Ok(meta) = entry.metadata() {
            total += meta.len();
        }
    }
    Ok(total)
}

/// Path-only helper for external callers. Useful for the wallpaper
/// service to look up "where does id=N live locally" without a
/// readdir scan.
pub fn local_path_for<R: Runtime>(app: &AppHandle<R>, id: i64) -> Result<Option<PathBuf>, String> {
    let dir = downloads_dir(app)?;
    for entry in fs::read_dir(&dir).map_err(|e| e.to_string())?.flatten() {
        let path = entry.path();
        if path
            .file_stem()
            .and_then(|s| s.to_str())
            .and_then(|s| s.parse::<i64>().ok())
            == Some(id)
        {
            return Ok(Some(path));
        }
    }
    Ok(None)
}

/// Sanity: a path is considered an "image" we can apply via the
/// static-wallpaper API if it has one of the common still-image
/// extensions. Video files arrive as mp4 / webm / mkv and the
/// Windows desktop wallpaper API ignores them.
pub fn is_settable_static(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|e| e.to_str()).map(|e| e.to_lowercase()).as_deref(),
        Some("jpg") | Some("jpeg") | Some("png") | Some("bmp") | Some("webp")
    )
}
