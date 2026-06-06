import SwiftUI
import AppKit

// v2.2 main window. Left sidebar (Browse + My Library + footer
// identity cell) and a thin top toolbar above the content area.
// Full-page push for detail / profile / collection / device / etc.
struct MainWindow: View {
    @State private var auth = AuthService.shared
    @State private var manager = WallpaperManager.shared
    @AppStorage(AppearancePref.storageKey) private var appearanceRaw: String = AppearancePref.system.rawValue

    @State private var sidebar: SidebarItem = .home
    @State private var sidebarCollapsed = false
    // Set when a Home "browse more" CTA jumps to Discover with a filter
    // (e.g. Live / AI). Cleared when leaving Discover.
    @State private var pendingDiscoverFilter: DiscoverView.Filter?
    @State private var path: [MainRoute] = []
    @State private var search: String = ""
    @State private var committedSearch: String = ""
    // Wallpaper detail is presented as a modal overlay (web-style inset
    // panel + scrim), not a navigation push.
    @State private var detailTarget: DetailTarget?
    @State private var refreshToken = UUID()
    @State private var forwardPath: [MainRoute] = []
    @State private var isRestoringForward = false
    @State private var isFullScreen = false

    enum SidebarItem: String, CaseIterable, Hashable {
        // Browse section.
        case home, discover, weekly, collections
        // My Library section (signed-in only).
        case myUploads, myCollections, myDownloads, myFavorites, myLikes, myCoins
        // Toolbar-only destinations.
        case upload, settings

        var label: String {
            switch self {
            case .home:          "Home"
            case .discover:      "Discover"
            case .weekly:        "Weekly"
            case .collections:   "Collections"
            case .myUploads:     "My Uploads"
            case .myCollections: "My Collections"
            case .myDownloads:   "My Downloads"
            case .myFavorites:   "My Favorites"
            case .myLikes:       "My Likes"
            case .myCoins:       "My Coins"
            case .upload:        "Upload"
            case .settings:      "Settings"
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
        // Manual split layout (no NavigationSplitView) so the chrome is
        // fully deterministic and matches the reference mockup exactly:
        //   • A paper top bar across the window top — the native traffic
        //     lights float on it at their natural top-left position
        //     (we do NOT reposition them). Full-screen drops the buttons
        //     and the bar simply reads as a top margin.
        //   • A floating Liquid-Glass sidebar card: inset on left / top /
        //     bottom, rounded on all corners, hairline border, with a
        //     cool→warm vertical gradient fill.
        //   • A full-bleed detail surface reaching the window's right and
        //     bottom edges, rounded only on its top-leading corner.
        ZStack(alignment: .topLeading) {
            // Warm paper behind everything — shows as the top bar and the
            // thin gaps around the floating sidebar card.
            Color.paper.ignoresSafeArea()

            HStack(spacing: WindowChrome.inset) {
                MainSidebar(selection: $sidebar, collapsed: $sidebarCollapsed)
                    .frame(width: sidebarCollapsed ? 64 : 240)
                    // Card visual lives in the BACKGROUND (not a clipShape)
                    // so the collapsed nav icons' hover tooltips can spill
                    // past the card's right edge without being clipped.
                    .background(
                        RoundedRectangle(cornerRadius: WindowChrome.radius, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.93, green: 0.95, blue: 0.97), Color.paper],
                                startPoint: .top, endPoint: .bottom))
                            .shadow(color: .black.opacity(0.06), radius: 10, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: WindowChrome.radius, style: .continuous)
                            .strokeBorder(Color.hair, lineWidth: 1)
                    )
                    // Alternate (form #2) collapse toggle: a circle
                    // straddling the sidebar's right edge, vertically
                    // centred on the logo. Kept alongside the
                    // traffic-light toggle for comparison.
                    .overlay(alignment: .topTrailing) {
                        SidebarEdgeToggle(collapsed: sidebarCollapsed) {
                            withAnimation(.easeInOut(duration: 0.22)) { sidebarCollapsed.toggle() }
                        }
                        // x: half the button straddles the edge.
                        // y: logo centre = topInset + half the 24pt logo,
                        //    minus half the button to get its top.
                        .offset(x: SidebarEdgeToggle.size / 2,
                                y: WindowChrome.topInset + 12 - SidebarEdgeToggle.size / 2)
                    }
                    .padding(.bottom, WindowChrome.inset)
                    // Draw above the detail pane so overflowing hover
                    // tooltips aren't covered by it.
                    .zIndex(1)
                    .animation(.easeInOut(duration: 0.22), value: sidebarCollapsed)

                detailPane
                    .clipShape(.rect(topLeadingRadius: WindowChrome.radius))
            }
            .padding(.leading, WindowChrome.inset)
            .padding(.top, WindowChrome.topBar + WindowChrome.toolbarGap)

            topToolbar
                .zIndex(3)

            // Wallpaper detail modal — web-style: dim scrim over the whole
            // window + an inset rounded panel hosting DetailPage. Sits at
            // the top of the ZStack so it covers the sidebar and any
            // pushed page. Backdrop tap / ✕ / ESC all close.
            if let target = detailTarget {
                DetailModalOverlay(
                    target: target,
                    onClose: { detailTarget = nil },
                    onWallpaper: { wp in openDetail(slug: wp.slug, fallbackID: wp.id) },
                    onUploader: { username in detailTarget = nil; push(.profile(username: username)) }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .ignoresSafeArea(.all)
        .background(Color.paper)
        .background(WindowFullScreenReader(isFullScreen: $isFullScreen))
        .task { await auth.refreshProfile() }
    }

    private func openDetail(slug: String, fallbackID: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            detailTarget = DetailTarget(slug: slug, fallbackID: fallbackID)
        }
    }

    private var canGoBack: Bool {
        !path.isEmpty
    }

    private var canGoForward: Bool {
        !forwardPath.isEmpty
    }

    private var contentLeading: CGFloat {
        WindowChrome.inset + (sidebarCollapsed ? 64 : 240) + WindowChrome.inset
    }

    private var topToolbar: some View {
        HStack(spacing: 12) {
            ToolbarButtonGroup(style: .navigation) {
                ChromeToolbarButton(
                    icon: "chevron.left",
                    help: "Back",
                    role: .navigation,
                    disabled: !canGoBack,
                    action: goBack
                )
                ChromeToolbarButton(
                    icon: "chevron.right",
                    help: "Forward",
                    role: .navigation,
                    disabled: !canGoForward,
                    action: goForward
                )
            }

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                ToolbarButtonGroup(style: .primary) {
                    ChromeToolbarButton(
                        icon: "square.and.arrow.up",
                        label: "Upload",
                        help: "Upload",
                        role: .primary,
                        active: sidebar == .upload,
                        action: { selectTopLevel(.upload) }
                    )
                }

                ToolbarButtonGroup(style: .utility) {
                    ChromeToolbarButton(
                        icon: "gearshape",
                        help: "Settings",
                        role: .utility,
                        active: sidebar == .settings,
                        action: { selectTopLevel(.settings) }
                    )
                    ChromeToolbarButton(
                        icon: "arrow.clockwise",
                        help: "Refresh current page",
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
            }
        }
        .padding(.leading, max(contentLeading, isFullScreen ? 12 : 86))
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity)
        .frame(height: WindowChrome.topBar)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                Rectangle().fill(Color.paper.opacity(0.74))
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hair.opacity(0.38)).frame(height: 1)
        }
        .animation(.easeInOut(duration: 0.22), value: sidebarCollapsed)
        .animation(.easeInOut(duration: 0.22), value: isFullScreen)
    }

    private var themeToolbarIcon: String {
        AppearancePref.fromStorage(appearanceRaw) == .dark ? "sun.max" : "moon"
    }

    private var themeToolbarHelp: String {
        AppearancePref.fromStorage(appearanceRaw) == .dark ? "Switch to light theme" : "Switch to dark theme"
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

    // Detail surface: page-mesh palette tint behind every page (mirrors
    // the web's .d3-discover-mesh), the routed content, and the
    // navigation stack for full-page pushes.
    private var detailPane: some View {
        // Mesh + paper sit BEHIND the NavigationStack (not inside its
        // root) so the palette background shows through pushed
        // destinations too — collection / weekly detail pages drive the
        // mesh on tile hover just like the list pages do.
        ZStack {
            Color.paper
            PageMesh()
            NavigationStack(path: $path) {
                ContentRouter(
                    sidebar: sidebar,
                    search: committedSearch,
                    discoverInitialFilter: pendingDiscoverFilter,
                    onPick: { wp in openDetail(slug: wp.slug, fallbackID: wp.id) },
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
                .id(refreshToken)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("")
                .navigationBarBackButtonHidden(true)
                .navigationDestination(for: MainRoute.self) { route in
                    Group {
                        switch route {
                        case .detail(let slug, _):
                            DetailPage(slug: slug,
                                       onUploader: { push(.profile(username: $0)) },
                                       onWallpaper: { wp in openDetail(slug: wp.slug, fallbackID: wp.id) })
                        case .profile(let username):
                            AccountView(username: username,
                                        onWallpaper: { wp in openDetail(slug: wp.slug, fallbackID: wp.id) },
                                        onCollection: { c in push(.collection(slug: c.slug, title: c.title)) })
                        case .collection(let slug, _):
                            CollectionDetailView(slug: slug,
                                                 onWallpaper: { wp in openDetail(slug: wp.slug, fallbackID: wp.id) })
                        case .device(let slug, let name):
                            DeviceDetailView(slug: slug, name: name,
                                             onWallpaper: { wp in openDetail(slug: wp.slug, fallbackID: wp.id) })
                        case .search(let q):
                            SearchResultsView(query: q,
                                              onWallpaper: { wp in openDetail(slug: wp.slug, fallbackID: wp.id) })
                        case .weeklyWeek(let y, let w):
                            WeeklyWeekView(year: y, week: w,
                                           onWallpaper: { wp in openDetail(slug: wp.slug, fallbackID: wp.id) })
                        case .category(let id, let name, let slug):
                            CategoryFeedView(category: Category(id: id, name: name, slug: slug, sortOrder: nil),
                                             onWallpaper: { wp in openDetail(slug: wp.slug, fallbackID: wp.id) })
                        }
                    }
                    .id(refreshToken)
                    .navigationTitle("")
                    .navigationBarBackButtonHidden(true)
                }
            }
        }
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
        case .navigation: Color.paper2.opacity(0.70)
        case .primary: .clear
        case .utility: Color.paper2.opacity(0.76)
        }
    }

    var stroke: Color {
        switch self {
        case .navigation: Color.hair.opacity(0.55)
        case .primary: .clear
        case .utility: Color.hair.opacity(0.9)
        }
    }

    var shadow: Color {
        switch self {
        case .utility: Color.black.opacity(0.035)
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
            Capsule().stroke(style.stroke, lineWidth: 1)
        )
        .shadow(color: style.shadow, radius: 7, y: 2)
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
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(stroke, lineWidth: 1))
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
        let view = NSView(frame: .zero)
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
                                      onOpenWeeklyArchive: onOpenWeeklyArchive)
        case .discover:      DiscoverView(search: search, onPick: onPick, initialFilter: discoverInitialFilter)
        case .weekly:        WeeklyArchiveView(onOpenWeek: onWeeklyWeek)
        case .collections:   CollectionsListView()
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
                Text("Sign in to view your account.").font(.sans13).foregroundStyle(Color.muted)
                Button("Sign in") { AuthService.shared.login() }.buttonStyle(.borderedProminent)
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
    var id: String { slug.isEmpty ? "\(fallbackID)" : slug }
}

// Web-style detail modal: a dim scrim over the whole window plus an
// inset rounded panel hosting DetailPage. ESC / ✕ / backdrop-tap close;
// tapping a "more like this" tile swaps the panel to that wallpaper.
struct DetailModalOverlay: View {
    let target: DetailTarget
    var onClose: () -> Void
    var onWallpaper: (Wallpaper) -> Void
    var onUploader: (String) -> Void

    @State private var closeHover = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            DetailPage(slug: target.slug, onUploader: onUploader, onWallpaper: onWallpaper, onClose: onClose)
                .id(target.id)
                // Fill the whole inset rectangle. The panel's own
                // background is DetailPage's blurred-wallpaper backdrop, so
                // no opaque paper fill here.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hair, lineWidth: 1))
                .overlay(alignment: .topTrailing) { closeButton }
                .shadow(color: .black.opacity(0.40), radius: 48, x: 0, y: 24)
                // Float the panel with a uniform gap on every side. The
                // whole window tree ignores the safe area, so the top must
                // also clear the floating title bar (WindowChrome.topBar) —
                // that keeps the visible gap below the chrome equal to the
                // side gaps in both windowed and full-screen modes.
                .padding(.top, WindowChrome.topBar + WindowChrome.modalInset)
                .padding(.bottom, WindowChrome.modalInset)
                .padding(.horizontal, WindowChrome.modalInset)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white).frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(closeHover ? 0.70 : 0.42)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .opacity(closeHover ? 1 : 0.55)
                .scaleEffect(closeHover ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        // ESC also closes (the in-content ESC pill was removed).
        .keyboardShortcut(.cancelAction)
        .padding(16)
        .onHover { h in closeHover = h; if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
    }
}
