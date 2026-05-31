import AppKit
import SwiftUI

// Standalone preview executable. Opens a single main window using the
// proposed redesign and renders sample wallpapers from picsum.photos
// so the layout can be evaluated without standing up real auth /
// network plumbing.

@main
struct WallpaperExchangeDemoApp: App {
    var body: some Scene {
        WindowGroup("Wallpaper Exchange — Preview") {
            MainWindow()
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.light)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        // Surface a Settings… menu item for completeness — preview only,
        // no real settings backing it.
        Settings {
            SettingsPreview()
        }
    }
}
