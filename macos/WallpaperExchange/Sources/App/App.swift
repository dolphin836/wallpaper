import AppKit
import SwiftUI

// v2 bootstrap. Hands top-level lifecycle to SwiftUI's App protocol so
// the redesigned main window mounts as a Dock-visible app, while
// reusing the existing AppDelegate (via @NSApplicationDelegateAdaptor)
// to attach the status-bar quick-action popover, register the
// wallxch:// URL handler, and run the launch-time UpdateService check.
//
// LSUIElement was removed from Info.plist in the same pass so closing
// the window doesn't quit the process — the menu-bar item stays live.
@main
struct WallpaperExchangeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Wallpaper Exchange") {
            MainWindow()
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                Button("Toggle Quick Popover") {
                    delegate.togglePopoverExternally()
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }
        }
    }
}
