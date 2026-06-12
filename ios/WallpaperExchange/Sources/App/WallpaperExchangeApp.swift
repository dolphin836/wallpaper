import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct WallpaperExchangeApp: App {
    @State private var auth = AuthService.shared

    init() {
        if LaunchOptions.lockPreview {
            UIPrefs.shared.lockPreview = true
        }
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
                .environment(UIPrefs.shared)
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
    @State private var selection = LaunchOptions.tab
    @State private var debugDetailSlug = LaunchOptions.detailSlug
    @State private var debugCollections = LaunchOptions.showCollections
    @State private var debugWeekly = LaunchOptions.showWeekly

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles.rectangle.stack") }
                .tag(1)
            MakeView()
                .tabItem { Label("Make", systemImage: "wand.and.stars") }
                .tag(2)
            AccountView()
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
                .tag(3)
        }
        // Screenshot-automation overlays (LaunchOptions args only).
        .fullScreenCoverCompat(isPresented: Binding(
            get: { debugDetailSlug != nil },
            set: { if !$0 { debugDetailSlug = nil } }
        )) {
            if let slug = debugDetailSlug {
                NavigationStack {
                    WallpaperDetailView(slug: slug)
                }
            }
        }
        .fullScreenCoverCompat(isPresented: $debugCollections) {
            CollectionsBrowser()
        }
        .fullScreenCoverCompat(isPresented: $debugWeekly) {
            NavigationStack {
                WeeklyArchiveView()
            }
        }
        // Warm exchange accent drives every interactive tint, replacing
        // the stock blue/purple; paper behind everything.
        .tint(Color.accent)
        .background(Color.paper)
    }
}
