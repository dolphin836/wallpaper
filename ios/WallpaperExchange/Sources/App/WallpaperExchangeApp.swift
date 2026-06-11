import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct WallpaperExchangeApp: App {
    @State private var auth = AuthService.shared

    init() {
        #if os(macOS)
        // The macOS dev-preview runs as a bare SwiftPM executable with no
        // app bundle, so promote it to a regular foreground app or the
        // window stays behind the terminal.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(auth)
                .task {
                    // Hydrate the profile behind a persisted token so the
                    // Account tab doesn't show "Not signed in" while a
                    // valid session exists.
                    await auth.refreshProfile()
                }
                #if os(macOS)
                // Phone-ish canvas so the iOS layout reads correctly.
                .frame(minWidth: 420, idealWidth: 460, minHeight: 760, idealHeight: 860)
                #endif
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles.rectangle.stack") }
            WeeklyView()
                .tabItem { Label("Weekly", systemImage: "calendar") }
            CollectionsView()
                .tabItem { Label("Collections", systemImage: "rectangle.stack") }
            UploadView()
                .tabItem { Label("Upload", systemImage: "plus.circle") }
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        // Warm exchange accent drives every interactive tint, replacing
        // the stock blue/purple; paper behind everything.
        .tint(Color.accent)
        .background(Color.paper)
    }
}
