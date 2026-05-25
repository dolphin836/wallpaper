// Suppress the console window on release builds — the user only sees
// the tray icon. Debug builds keep the console attached for log output.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod downloads;
mod tray;
mod uninstall;
mod wallpaper;

use tauri::{Manager, WindowEvent};

fn main() {
    env_logger::Builder::from_default_env()
        .filter_level(log::LevelFilter::Info)
        .init();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            wallpaper::set_static_wallpaper,
            wallpaper::set_wallpaper_by_id,
            downloads::download_wallpaper,
            downloads::list_downloaded,
            downloads::remove_downloaded,
            downloads::downloads_total_bytes,
        ])
        .setup(|app| {
            tray::install(app.handle())?;

            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running wallpaper-exchange-windows");
}
