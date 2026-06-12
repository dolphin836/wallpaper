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
    @State private var router = TabRouter.shared
    @State private var debugDetailSlug = LaunchOptions.detailSlug
    @State private var debugDetailPath = NavigationPath()
    @State private var debugCollections = LaunchOptions.showCollections
    @State private var debugWeekly = LaunchOptions.showWeekly

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selection) {
            HomeView()
                .tag(0)
            DiscoverView()
                .tag(1)
            MakeView()
                .tag(2)
            AccountView()
                .tag(3)
        }
        .environment(router)
        // Screenshot-automation overlays (LaunchOptions args only). The
        // detail route is pushed (not shown as a root) so the screenshots
        // exercise the same back-button context users navigate in.
        .fullScreenCoverCompat(isPresented: Binding(
            get: { debugDetailSlug != nil },
            set: { if !$0 { debugDetailSlug = nil } }
        )) {
            if let slug = debugDetailSlug {
                NavigationStack(path: $debugDetailPath) {
                    Color.paper
                        .navigationDestination(for: WallpaperRoute.self) { route in
                            WallpaperDetailView(slug: route.slug)
                        }
                        .onAppear {
                            if debugDetailPath.isEmpty {
                                debugDetailPath.append(WallpaperRoute(slug: slug))
                            }
                        }
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
        // Warm exchange accent drives every interactive tint; the system
        // tab bar is replaced by the floating capsule bar each root page
        // hosts in its bottom safe-area inset. Dark-only, per the brand.
        .tint(Color.accent)
        .background(Color.paper)
        .preferredColorScheme(.dark)
    }
}
