import SwiftUI
import AppKit

// v3 main window. No sidebar — a floating liquid-glass nav pill fixed
// at the window's top-centre (Home / Discover / Weekly / Collections)
// plus an icon toolbar on the right (upload, settings, refresh, theme,
// avatar). Full-page push for detail / profile / collection / etc.
struct MainWindow: View {
    @State private var auth = AuthService.shared
    @State private var manager = WallpaperManager.shared
    @AppStorage(AppearancePref.storageKey) private var appearanceRaw: String = AppearancePref.system.rawValue

    @State private var sidebar: SidebarItem = .home
    // Set when a Home "browse more" CTA jumps to Discover with a filter
    // (e.g. Live / AI). Cleared when leaving Discover.
    @State private var pendingDiscoverFilter: DiscoverView.Filter?
    @State private var path: [MainRoute] = []
    @State private var search: String = ""
    @State private var committedSearch: String = ""
    // Wallpaper detail is presented as a modal overlay, not a navigation
    // push. The overlay now fills the window visually so list scroll
    // position stays intact while the detail feels immersive.
    @State private var detailTarget: DetailTarget?
    @State private var refreshToken = UUID()
    @State private var forwardPath: [MainRoute] = []
    @State private var isRestoringForward = false
    @State private var isFullScreen = false
    @State private var palette = PaletteEnv.shared

    enum SidebarItem: String, CaseIterable, Hashable {
        // Browse section.
        case home, discover, weekly, collections
        // My Library section (signed-in only).
        case myUploads, myCollections, myDownloads, myFavorites, myLikes, myCoins
        // Toolbar-only destinations.
        case upload, settings

        var label: String {
            switch self {
            case .home:          L10n.shell.home
            case .discover:      L10n.shell.discover
            case .weekly:        L10n.shell.weekly
            case .collections:   L10n.shell.collections
            case .myUploads:     L10n.shell.myUploads
            case .myCollections: L10n.shell.myCollections
            case .myDownloads:   L10n.shell.myDownloads
            case .myFavorites:   L10n.shell.myFavorites
            case .myLikes:       L10n.shell.myLikes
            case .myCoins:       L10n.shell.myCoins
            case .upload:        L10n.shell.upload
            case .settings:      L10n.shell.settings
            }
        }
        var icon: String {
            switch self {
            case .home:          "house"
            case .discover:      "sparkles"
            case .weekly:        "calendar.badge.clock"
            case .collections:   "rectangle.stack"
            case .myUploads:     "tray.and.arrow.up"
            case .myCollections: "rectangle.stack.badge.person.crop"
            case .myDownloads:   "arrow.down.circle"
            case .myFavorites:   "star"
            case .myLikes:       "heart"
            case .myCoins:       "circle.hexagongrid.fill"
            case .upload:        "square.and.arrow.up"
            case .settings:      "gearshape"
            }
        }
        var isMine: Bool {
            switch self {
            case .myUploads, .myCollections, .myDownloads, .myFavorites, .myLikes, .myCoins: true
            default: false
            }
        }
    }

    enum MainRoute: Hashable {
        case detail(slug: String, fallbackID: Int)
        case profile(username: String)
        case collection(slug: String, title: String)
        case device(slug: String, name: String)
        case search(query: String)
        case weeklyWeek(year: Int, week: Int)
        case category(id: Int, name: String, slug: String)
    }

    var body: some View {
        // Manual layout (no NavigationSplitView) so the chrome is fully
        // deterministic:
        //   • The native traffic lights float at their natural top-left
        //     position (we do NOT reposition them).
        //   • A liquid-glass nav pill floats at the top-centre; the icon
        //     toolbar sits on the right of the same row. No divider —
        //     the chrome reads as loose elements over the page backdrop.
        //   • A transparent content surface over the full-window palette
        //     mesh (and, on Home, over the weekly-hero wallpaper backdrop).
        ZStack(alignment: .topLeading) {
            // Full-window palette mesh. Tiles still drive PaletteEnv, but
            // the responsive backdrop now spans the toolbar row and the
            // content surface.
            PageMesh()

            // Home-only immersive backdrop: the current weekly hero
            // wallpaper fills the whole window behind the chrome.
            if sidebar == .home && path.isEmpty {
                HomeBackdropView()
                    .transition(.opacity)
            }

            detailPane
                .padding(.top, WindowChrome.topBar + WindowChrome.toolbarGap)

            topToolbar
                .zIndex(3)

            // Wallpaper detail modal — full-window overlay instead of a
            // navigation push, so the grid/list underneath keeps its
            // scroll position. Backdrop tap / ESC / toolbar back close.
            if let target = detailTarget {
                DetailModalOverlay(
                    target: target,
                    isFullScreen: isFullScreen,
                    onClose: { detailTarget = nil },
                    onWallpaper: { wp in openDetail(wp) },
                    onUploader: { username in detailTarget = nil; push(.profile(username: username)) }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            if let flow = auth.authFlow {
                AuthModalOverlay(mode: flow)
                    .id(flow.id)
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .ignoresSafeArea(.all)
        .background(Color.clear)
        .background(WindowBackdropClearer())
        .background(WindowFullScreenReader(isFullScreen: $isFullScreen))
        // Load the persisted JWT only after the window is on screen. The
        // Keychain read can raise a system-modal consent prompt (ad-hoc
        // signing re-arms it every update); doing it here — not in
        // AuthService.init — keeps that prompt from blocking the initial
        // window presentation. refreshProfile then runs with the token in
        // place (and again on every remount, e.g. a language change).
        .task {
            await auth.loadPersistedToken()
            await auth.refreshProfile()
        }
    }

    private func openDetail(_ wallpaper: Wallpaper) {
        openDetail(slug: wallpaper.slug, fallbackID: wallpaper.id, initialWallpaper: wallpaper)
    }

    private func openDetail(slug: String, fallbackID: Int, initialWallpaper: Wallpaper? = nil) {
        withAnimation(.easeOut(duration: 0.18)) {
            detailTarget = DetailTarget(slug: slug, fallbackID: fallbackID, initialWallpaper: initialWallpaper)
        }
    }

    private var canGoBack: Bool {
        !path.isEmpty
    }

    private var canGoForward: Bool {
        !forwardPath.isEmpty
    }

    // Top chrome row: brand + back/forward on the left, the liquid-glass
    // nav pill centred on the window, and the icon toolbar (upload,
    // settings, refresh, theme, avatar) on the right. No bottom divider.
    private var topToolbar: some View {
        ZStack {
            HStack(spacing: 12) {
                brandMark

                ToolbarButtonGroup(style: .navigation) {
                    ChromeToolbarButton(
                        icon: "chevron.left",
                        help: L10n.shell.back,
                        role: .navigation,
                        disabled: !canGoBack,
                        action: goBack
                    )
                    ChromeToolbarButton(
                        icon: "chevron.right",
                        help: L10n.shell.forward,
                        role: .navigation,
                        disabled: !canGoForward,
                        action: goForward
                    )
                }

                Spacer(minLength: 16)

                ToolbarButtonGroup(style: .utility) {
                    ChromeToolbarButton(
                        icon: "square.and.arrow.up",
                        help: L10n.shell.upload,
                        role: .utility,
                        active: sidebar == .upload,
                        action: { selectTopLevel(.upload) }
                    )
                    ChromeToolbarButton(
                        icon: "gearshape",
                        help: L10n.shell.settings,
                        role: .utility,
                        active: sidebar == .settings,
                        action: { selectTopLevel(.settings) }
                    )
                    ChromeToolbarButton(
                        icon: "arrow.clockwise",
                        help: L10n.shell.refreshPage,
                        role: .utility,
                        action: refreshCurrentPage
                    )
                    ChromeToolbarButton(
                        icon: themeToolbarIcon,
                        help: themeToolbarHelp,
                        role: .utility,
                        action: toggleTheme
                    )
                }

                ToolbarAvatarButton(active: sidebar.isMine) {
                    if auth.isLoggedIn {
                        selectTopLevel(.myUploads)
                    } else {
                        auth.login()
                    }
                }
            }
            .padding(.leading, isFullScreen ? 16 : 86)
            .padding(.trailing, 16)

            GlassNavBar(selection: navSelection) { item in
                selectTopLevel(item)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: WindowChrome.topBar)
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.22), value: isFullScreen)
        .animation(.easeOut(duration: 0.42), value: palette.c2)
    }

    // The glass nav only highlights top-level browse pages; account /
    // upload / settings selections leave the pill unhighlighted.
    private var navSelection: SidebarItem? {
        switch sidebar {
        case .home, .discover, .weekly, .collections: sidebar
        default: nil
        }
    }

    @ViewBuilder
    private var brandMark: some View {
        if let nsImg = BrandAsset.logo {
            Image(nsImage: nsImg)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
        }
    }

    private var themeToolbarIcon: String {
        AppearancePref.fromStorage(appearanceRaw) == .dark ? "sun.max" : "moon"
    }

    private var themeToolbarHelp: String {
        AppearancePref.fromStorage(appearanceRaw) == .dark ? L10n.shell.switchToLight : L10n.shell.switchToDark
    }

    private func selectTopLevel(_ item: SidebarItem) {
        sidebar = item
    }

    private func goBack() {
        guard let last = path.popLast() else { return }
        forwardPath.append(last)
    }

    private func goForward() {
        guard let next = forwardPath.popLast() else { return }
        isRestoringForward = true
        path.append(next)
    }

    private func push(_ route: MainRoute) {
        forwardPath.removeAll()
        path.append(route)
    }

    private func refreshCurrentPage() {
        refreshToken = UUID()
    }

    private func toggleTheme() {
        let current = AppearancePref.fromStorage(appearanceRaw)
        appearanceRaw = current == .dark ? AppearancePref.light.rawValue : AppearancePref.dark.rawValue
    }

    // Detail surface: routed content and full-page pushes. The palette mesh
    // now lives at the root window layer so it can continue underneath the
    // toolbar and sidebar as well.
    private var detailPane: some View {
        ZStack {
            routedContent
                .id(refreshToken)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .background(TransparentAppKitBackground())
        .onChange(of: sidebar) { _, new in
            path.removeAll()
            forwardPath.removeAll()
            // Don't let a Home-CTA filter linger when Discover is opened
            // directly from the sidebar later.
            if new != .discover { pendingDiscoverFilter = nil }
        }
        .onChange(of: path) { old, new in
            if new.count > old.count {
                if isRestoringForward {
                    isRestoringForward = false
                } else {
                    forwardPath.removeAll()
                }
            }
        }
    }

    @ViewBuilder
    private var routedContent: some View {
        if let route = path.last {
            routeContent(route)
        } else {
            ContentRouter(
                sidebar: sidebar,
                search: committedSearch,
                discoverInitialFilter: pendingDiscoverFilter,
                onPick: { wp in openDetail(wp) },
                onDevice: { d in push(.device(slug: d.slug, name: d.name)) },
                onWeeklyWeek: { y, w in push(.weeklyWeek(year: y, week: w)) },
                onCategory: { c in push(.category(id: c.id, name: c.name, slug: c.slug)) },
                onUploader: { username in push(.profile(username: username)) },
                onCollection: { c in push(.collection(slug: c.slug, title: c.title)) },
                onUpload: { sidebar = .upload },
                onCancelUpload: { sidebar = auth.isLoggedIn ? .myUploads : .home },
                onOpenDiscover: { f in pendingDiscoverFilter = f; sidebar = .discover },
                onOpenCollections: { sidebar = .collections },
                onOpenWeeklyArchive: { sidebar = .weekly }
            )
        }
    }

    @ViewBuilder
    private func routeContent(_ route: MainRoute) -> some View {
        switch route {
        case .detail(let slug, _):
            DetailPage(slug: slug,
                       onUploader: { push(.profile(username: $0)) },
                       onWallpaper: { wp in openDetail(wp) },
                       isWindowFullScreen: isFullScreen)
        case .profile(let username):
            AccountView(username: username,
                        onWallpaper: { wp in openDetail(wp) },
                        onCollection: { c in push(.collection(slug: c.slug, title: c.title)) })
        case .collection(let slug, _):
            CollectionDetailView(slug: slug,
                                 onWallpaper: { wp in openDetail(wp) })
        case .device(let slug, let name):
            DeviceDetailView(slug: slug, name: name,
                             onWallpaper: { wp in openDetail(wp) })
        case .search(let q):
            SearchResultsView(query: q,
                              onWallpaper: { wp in openDetail(wp) })
        case .weeklyWeek(let y, let w):
            WeeklyWeekView(year: y, week: w,
                           onWallpaper: { wp in openDetail(wp) })
        case .category(let id, let name, let slug):
            CategoryFeedView(category: Category(id: id, name: name, slug: slug, sortOrder: nil),
                             onWallpaper: { wp in openDetail(wp) })
        }
    }

    private func commitSearch() {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            committedSearch = ""
        } else {
            committedSearch = q
            push(.search(query: q))
        }
    }
}

private final class MouseTransparentView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct TransparentAppKitBackground: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = MouseTransparentView(frame: .zero)
        clearAround(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        clearAround(view, coordinator: context.coordinator)
    }

    private func clearAround(_ view: NSView, coordinator: Coordinator) {
        guard coordinator.shouldSchedule else { return }
        coordinator.shouldSchedule = false
        DispatchQueue.main.async {
            defer { coordinator.shouldSchedule = coordinator.didClear == false }
            guard view.window != nil else { return }

            var current: NSView? = view
            var depth = 0
            while let node = current, depth < 12 {
                if let scroll = node as? NSScrollView {
                    scroll.drawsBackground = false
                    scroll.backgroundColor = .clear
                    scroll.contentView.drawsBackground = false
                } else if let clip = node as? NSClipView {
                    clip.drawsBackground = false
                    clip.backgroundColor = .clear
                } else if !(node is NSVisualEffectView) {
                    node.wantsLayer = true
                    node.layer?.backgroundColor = NSColor.clear.cgColor
                }
                current = node.superview
                depth += 1
            }
            coordinator.didClear = true
        }
    }

    final class Coordinator {
        var didClear = false
        var shouldSchedule = true
    }
}

private enum ToolbarGroupStyle {
    case navigation, primary, utility

    var horizontalPadding: CGFloat {
        switch self {
        case .primary: 0
        case .navigation, .utility: 3
        }
    }

    var fill: Color {
        switch self {
        case .navigation: Color.chromeControl
        case .primary: .clear
        case .utility: Color.chromeControl
        }
    }

    @MainActor
    func stroke(for palette: PaletteEnv) -> Color {
        switch self {
        case .navigation: ChromeLine.softBorder(for: palette)
        case .primary: .clear
        case .utility: ChromeLine.border(for: palette)
        }
    }

    var shadow: Color {
        switch self {
        case .navigation, .utility: Color.chromeShadow
        default: .clear
        }
    }
}

private enum ToolbarButtonRole {
    case navigation, primary, utility
}

private struct ToolbarButtonGroup<Content: View>: View {
    var style: ToolbarGroupStyle = .utility
    let content: Content
    @State private var palette = PaletteEnv.shared

    init(style: ToolbarGroupStyle = .utility, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 2) {
            content
        }
        .padding(style.horizontalPadding)
        .background(
            Capsule().fill(style.fill)
        )
        .overlay(
            Capsule().stroke(style.stroke(for: palette), lineWidth: 1)
        )
        .shadow(color: style.shadow, radius: 7, y: 2)
        .animation(.easeOut(duration: 0.42), value: palette.c2)
    }
}

private struct ChromeToolbarButton: View {
    let icon: String
    var label: String? = nil
    let help: String
    var role: ToolbarButtonRole = .utility
    var active: Bool = false
    var disabled: Bool = false
    var action: () -> Void

    @State private var hover = false

    private var size: CGSize {
        switch role {
        case .primary: CGSize(width: label == nil ? 34 : 86, height: 28)
        case .navigation, .utility: CGSize(width: 28, height: 24)
        }
    }

    private var cornerRadius: CGFloat {
        role == .primary ? 14 : 7
    }

    private var usesCircularUtilityHighlight: Bool {
        !disabled && (active || hover) && role == .utility && label == nil
    }

    private var activeHighlightDiameter: CGFloat {
        min(size.width, size.height)
    }

    private var iconColor: Color {
        if disabled { return Color.muted.opacity(0.55) }
        switch role {
        case .primary:
            return .white
        case .navigation:
            return hover || active ? Color.ink : Color.ink2
        case .utility:
            if active { return Color.accent }
            return hover ? Color.ink : Color.ink2
        }
    }

    private var fill: Color {
        if disabled { return .clear }
        switch role {
        case .primary:
            return hover || active ? Color.accent.blended(with: Color.ink, fraction: 0.12) : Color.accent
        case .navigation:
            if active { return Color.ink.opacity(0.08) }
            return hover ? Color.ink.opacity(0.06) : .clear
        case .utility:
            if active { return Color.accent.opacity(0.13) }
            return hover ? Color.ink.opacity(0.06) : .clear
        }
    }

    private var stroke: Color {
        if disabled { return .clear }
        switch role {
        case .primary:
            return Color.white.opacity(0.24)
        case .navigation, .utility:
            return active ? Color.accent.opacity(0.22) : .clear
        }
    }

    private var shadowColor: Color {
        if role == .primary && !disabled {
            return Color.accent.opacity(hover || active ? 0.34 : 0.24)
        }
        return .clear
    }

    var body: some View {
        Button(action: {
            guard !disabled else { return }
            action()
        }) {
            HStack(spacing: label == nil ? 0 : 6) {
                Image(systemName: icon)
                    .font(.system(size: role == .primary ? 13 : 12, weight: .semibold))
                if let label {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(iconColor)
            .frame(width: size.width, height: size.height)
            .background {
                if usesCircularUtilityHighlight {
                    Circle()
                        .fill(fill)
                        .frame(width: activeHighlightDiameter, height: activeHighlightDiameter)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)
                }
            }
            .overlay {
                if usesCircularUtilityHighlight {
                    Circle()
                        .stroke(stroke, lineWidth: 1)
                        .frame(width: activeHighlightDiameter, height: activeHighlightDiameter)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                }
            }
            .shadow(color: shadowColor, radius: role == .primary ? 10 : 0, y: role == .primary ? 4 : 0)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .focusEffectDisabled()
        .focusable(false)
        .help(help)
        .onHover { h in
            hover = h
            guard !disabled else { return }
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

private struct WindowFullScreenReader: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen)
    }

    func makeNSView(context: Context) -> NSView {
        let view = MouseTransparentView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
    }

    final class Coordinator {
        private var isFullScreen: Binding<Bool>
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else {
                update()
                return
            }

            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            self.window = window
            update()

            guard let window else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in self?.update() })
            observers.append(center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in self?.update() })
        }

        private func update() {
            isFullScreen.wrappedValue = window?.styleMask.contains(.fullScreen) == true
        }
    }
}

private struct WindowBackdropClearer: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = MouseTransparentView(frame: .zero)
        clear(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        clear(from: view, coordinator: context.coordinator)
    }

    private func clear(from view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.applyIfNeeded(to: view.window)
        }
    }

    final class Coordinator {
        private var clearedWindowIDs = Set<ObjectIdentifier>()

        func applyIfNeeded(to window: NSWindow?) {
            guard let window else { return }
            let windowID = ObjectIdentifier(window)
            guard clearedWindowIDs.insert(windowID).inserted else { return }

            apply(to: window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak window] in
                guard self != nil, let window else { return }
                self?.apply(to: window)
            }
        }

        private func apply(to window: NSWindow) {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

            guard let root = window.contentView?.superview else { return }

            func scrub(_ node: NSView) {
                let className = String(describing: type(of: node))
                let isChrome =
                    className.contains("NSThemeFrame") ||
                    className.contains("NSTitlebar") ||
                    className.contains("AppKitWindowHostingView")
                let isTitlebarDecoration =
                    className.contains("TitlebarBackground") ||
                    className.contains("TitlebarDecoration")

                if isChrome || isTitlebarDecoration {
                    node.wantsLayer = true
                    node.layer?.backgroundColor = NSColor.clear.cgColor
                }

                if isTitlebarDecoration {
                    node.isHidden = true
                }

                if let effect = node as? NSVisualEffectView, isChrome {
                    effect.material = .windowBackground
                    effect.blendingMode = .behindWindow
                    effect.state = .inactive
                }

                for child in node.subviews {
                    scrub(child)
                }
            }

            scrub(root)
        }
    }
}

// Routes the sidebar selection to the appropriate top-level view.
struct ContentRouter: View {
    let sidebar: MainWindow.SidebarItem
    let search: String
    var discoverInitialFilter: DiscoverView.Filter? = nil
    var onPick: (Wallpaper) -> Void
    var onDevice: (DeviceProfile) -> Void
    var onWeeklyWeek: (Int, Int) -> Void
    var onCategory: (Category) -> Void
    var onUploader: (String) -> Void
    var onCollection: (CollectionItem) -> Void = { _ in }
    var onUpload: () -> Void = {}
    var onCancelUpload: () -> Void = {}
    var onOpenDiscover: (DiscoverView.Filter) -> Void = { _ in }
    var onOpenCollections: () -> Void = {}
    var onOpenWeeklyArchive: () -> Void = {}

    var body: some View {
        switch sidebar {
        case .home:          HomeView(onPick: onPick, onOpenWeek: onWeeklyWeek,
                                      onOpenDiscover: onOpenDiscover,
                                      onOpenCollections: onOpenCollections,
                                      onOpenWeeklyArchive: onOpenWeeklyArchive,
                                      onCollection: onCollection)
        case .discover:      DiscoverView(search: search, onPick: onPick, initialFilter: discoverInitialFilter)
        case .weekly:        WeeklyArchiveView(onOpenWeek: onWeeklyWeek)
        case .collections:   CollectionsListView(onCollection: onCollection)
        case .myUploads:     account(.uploads)
        case .myCollections: account(.collections)
        case .myDownloads:   account(.downloads)
        case .myFavorites:   account(.favorites)
        case .myLikes:       account(.likes)
        case .myCoins:       account(.ledger)
        case .settings:      account(.settings)
        case .upload:        UploadView(onCancel: onCancelUpload)
        }
    }

    // The owner's account page, opened on a specific tab. The whole
    // "My Library" group + Settings now route here so the personal area
    // is one tabbed page (matching the web profile, plus a Settings tab).
    @ViewBuilder private func account(_ tab: AccountTab) -> some View {
        if let me = AuthService.shared.user?.username {
            AccountView(username: me, initialTab: tab, onWallpaper: onPick, onCollection: onCollection, onUpload: onUpload)
        } else {
            VStack(spacing: 12) {
                Text(L10n.shell.signInToViewAccount).font(.sans13).foregroundStyle(Color.muted)
                Button(L10n.shell.signIn) { AuthService.shared.login() }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// Identifies the wallpaper currently shown in the detail modal. slug is
// the canonical key; fallbackID covers list rows whose slug is empty.
struct DetailTarget: Identifiable, Equatable {
    let slug: String
    let fallbackID: Int
    let initialWallpaper: Wallpaper?
    var id: String { slug.isEmpty ? "\(fallbackID)" : slug }

    static func == (lhs: DetailTarget, rhs: DetailTarget) -> Bool {
        lhs.slug == rhs.slug && lhs.fallbackID == rhs.fallbackID
    }
}

private struct WindowTrafficLightVisibility: NSViewRepresentable {
    let hidden: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = MouseTransparentView(frame: .zero)
        apply(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(from: view, coordinator: context.coordinator)
    }

    private func apply(from view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            coordinator.attach(to: view.window)
            coordinator.setHidden(hidden)
        }
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var originalHidden: [NSWindow.ButtonType: Bool] = [:]
        private let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        deinit {
            restore()
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            restore()
            self.window = window
            originalHidden.removeAll()
        }

        func setHidden(_ hidden: Bool) {
            guard let window else { return }
            if hidden {
                for type in buttonTypes {
                    guard let button = window.standardWindowButton(type) else { continue }
                    if originalHidden[type] == nil {
                        originalHidden[type] = button.isHidden
                    }
                    button.isHidden = true
                }
            } else {
                restore()
            }
        }

        private func restore() {
            guard let window else { return }
            for (type, wasHidden) in originalHidden {
                window.standardWindowButton(type)?.isHidden = wasHidden
            }
            originalHidden.removeAll()
        }
    }
}

// Detail modal: a dim scrim under a full-window DetailPage. It remains
// an overlay so the underlying grid/list scroll position is preserved.
struct DetailModalOverlay: View {
    let target: DetailTarget
    let isFullScreen: Bool
    var onClose: () -> Void
    var onWallpaper: (Wallpaper) -> Void
    var onUploader: (String) -> Void
    var body: some View {
        ZStack {
            WindowTrafficLightVisibility(hidden: true)
                .frame(width: 0, height: 0)

            Rectangle()
                .fill(Color.black.opacity(0.66))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            DetailPage(
                slug: target.slug,
                initialWallpaper: target.initialWallpaper,
                onUploader: onUploader,
                onWallpaper: onWallpaper,
                onClose: onClose,
                isWindowFullScreen: isFullScreen
            )
                .id(target.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onClose) {
                Color.clear.frame(width: 1, height: 1)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityHidden(true)
        }
    }
}
