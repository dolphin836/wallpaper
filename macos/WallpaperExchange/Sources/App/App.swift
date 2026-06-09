import AppKit
import SwiftUI

// v2 bootstrap. Hands top-level lifecycle to SwiftUI's App protocol so
// the redesigned main window mounts as a Dock-visible app, while
// reusing the existing AppDelegate (via @NSApplicationDelegateAdaptor)
// to attach the status-bar quick action and run the launch-time
// UpdateService check.
//
// LSUIElement was removed from Info.plist in the same pass so closing
// the window doesn't quit the process — the menu-bar item stays live.
@main
struct WallpaperExchangeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Wallpaper Exchange", id: "main") {
            MainWindowRoot(delegate: delegate)
        }
        // Hidden title bar lets content extend up to the very top of
        // the window — the traffic-light buttons float over the
        // content, matching Claude.app / Linear / Things 3.
        // AppDelegate.configureMainWindow() also enables
        // titlebarAppearsTransparent + .fullSizeContentView so the
        // empty title-bar strip is gone entirely.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                Button("Open Wallpaper Exchange") {
                    delegate.openMainWindowExternally()
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            }
        }
    }
}

private struct MainWindowRoot: View {
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    // Persisted appearance choice from SettingsView. Applied to the
    // window root so light/dark take effect immediately when toggled.
    @AppStorage(AppearancePref.storageKey) private var appearanceRaw: String = AppearancePref.system.rawValue

    var body: some View {
        MainWindow()
            .frame(minWidth: 1080, minHeight: 720)
            .preferredColorScheme(AppearancePref.fromStorage(appearanceRaw).colorScheme)
            .onAppear {
                AppearancePref.applyToApp(appearanceRaw)
                delegate.setOpenMainWindowHandler {
                    openWindow(id: "main")
                }
            }
            .onChange(of: appearanceRaw) { _, newValue in
                AppearancePref.applyToApp(newValue)
            }
    }
}
