// Suppress the console window on release builds — the user only sees
// the tray icon. Debug builds keep the console attached for log output.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod tray;
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
        ])
        .setup(|app| {
            // System tray icon. tray::install holds the per-platform
            // wiring so main.rs stays declarative.
            tray::install(app.handle())?;

            // The window starts hidden (configured in tauri.conf.json).
            // Show on first launch so the user has something to interact
            // with; subsequent runs honor the tray toggle.
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            // Closing the window hides it rather than quitting the app —
            // the tray icon remains. Matches the macOS client's
            // status-bar-only behavior.
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running wallpaper-exchange-windows");
}
