// System tray icon + menu. Left-click toggles the main window;
// right-click opens a small menu (Show / Quit). The icon image is
// resolved from src-tauri/icons/icon.png at build time.

use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, Runtime,
};

pub fn install<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<()> {
    let show_item = MenuItem::with_id(app, "show", "Show", true, None::<&str>)?;
    let uninstall_item =
        MenuItem::with_id(app, "uninstall", "Uninstall Wallpaper Exchange…", true, None::<&str>)?;
    let quit_item = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    // separator + uninstall sits visually distant from Quit so a
    // mis-click on the menu's last item doesn't nuke the install.
    let menu = Menu::with_items(
        app,
        &[
            &show_item,
            &tauri::menu::PredefinedMenuItem::separator(app)?,
            &uninstall_item,
            &tauri::menu::PredefinedMenuItem::separator(app)?,
            &quit_item,
        ],
    )?;

    TrayIconBuilder::with_id("main-tray")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "show" => toggle_window(app, true),
            "uninstall" => crate::uninstall::run_uninstaller(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            // Left-click toggles visibility — Windows users expect
            // clicking the tray icon to bring the app forward, not
            // open the right-click menu (which has its own button).
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(window) = app.get_webview_window("main") {
                    let visible = window.is_visible().unwrap_or(false);
                    toggle_window(app, !visible);
                }
            }
        })
        .build(app)?;

    Ok(())
}

fn toggle_window<R: Runtime>(app: &AppHandle<R>, show: bool) {
    if let Some(window) = app.get_webview_window("main") {
        if show {
            let _ = window.show();
            let _ = window.unminimize();
            let _ = window.set_focus();
        } else {
            let _ = window.hide();
        }
    }
}
