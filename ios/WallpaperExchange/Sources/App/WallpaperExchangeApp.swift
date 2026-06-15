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
    @Environment(UIPrefs.self) private var prefs
    @Environment(AuthService.self) private var auth

    @State private var router = TabRouter.shared
    @State private var detailRouter = WallpaperDetailRouter.shared
    @State private var profileRouter = ProfileRouter.shared
    @State private var debugDetailSlug = LaunchOptions.detailSlug
    @State private var debugDetailPath = NavigationPath()
    @State private var debugDetailWasPushed = false
    @State private var debugCollections = LaunchOptions.showCollections
    @State private var debugWeekly = LaunchOptions.showWeekly

    var body: some View {
        @Bindable var router = router
        @Bindable var auth = auth
        ZStack {
            TabView(selection: $router.selection) {
                HomeView()
                    .tag(0)
                DiscoverView()
                    .tag(1)
                WeeklyTabView()
                    .tag(2)
                CollectionsTabView()
                    .tag(3)
                FavoritesView()
                    .tag(4)
            }
            .allowsHitTesting(detailRouter.route == nil && !profileRouter.isPresented)
            .accessibilityHidden(detailRouter.route != nil || profileRouter.isPresented)

            if let route = detailRouter.route {
                NavigationStack {
                    WallpaperDetailView(
                        slug: route.slug,
                        initialWallpaper: route.initialWallpaper,
                        showsModalCloseButton: true
                    ) {
                        detailRouter.dismiss()
                    }
                }
                .id(route.slug)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .zIndex(10)
            }

            if profileRouter.isPresented {
                ProfileView {
                    profileRouter.dismiss()
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
                .zIndex(20)
            }
        }
        .environment(router)
        .environment(detailRouter)
        .environment(profileRouter)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: detailRouter.route)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: profileRouter.isPresented)
        // Screenshot-automation overlays (LaunchOptions args only). The
        // detail route is pushed (not shown as a root) so the screenshots
        // exercise the same back-button context users navigate in.
        .fullScreenCoverCompat(isPresented: Binding(
            get: { debugDetailSlug != nil },
            set: {
                if !$0 {
                    debugDetailSlug = nil
                    debugDetailPath = NavigationPath()
                    debugDetailWasPushed = false
                }
            }
        )) {
            if let slug = debugDetailSlug {
                NavigationStack(path: $debugDetailPath) {
                    Color.paper
                        .navigationDestination(for: WallpaperRoute.self) { route in
                            WallpaperDetailView(slug: route.slug, initialWallpaper: route.initialWallpaper)
                        }
                        .onAppear {
                            if debugDetailPath.isEmpty {
                                debugDetailPath.append(WallpaperRoute(slug: slug))
                                debugDetailWasPushed = true
                            }
                        }
                        .onChange(of: debugDetailPath.count) { _, count in
                            if debugDetailWasPushed && count == 0 {
                                debugDetailSlug = nil
                                debugDetailWasPushed = false
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
                    .navigationDestination(for: WeeklyArchiveEntry.self) { entry in
                        WeeklyWeekView(year: entry.year, week: entry.week)
                    }
            }
        }
        .sheet(item: $auth.authFlow) { flow in
            AuthView(mode: flow == .register ? .register : .login)
                .authSheetPresentation()
        }
        // Warm exchange accent drives every interactive tint; the system
        // tab bar is replaced by the floating capsule bar each root page
        // hosts in its bottom safe-area inset.
        .tint(Color.accent)
        .background(Color.paper)
        .preferredColorScheme(prefs.appearance.colorScheme)
        .id(prefs.language.rawValue)
    }
}
