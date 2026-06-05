import SwiftUI
import AppKit

// v2.2 main window. Left sidebar (Browse + My Library + footer
// identity cell) and a thin top toolbar above the content area.
// Full-page push for detail / profile / collection / device / etc.
struct MainWindow: View {
    @State private var auth = AuthService.shared
    @State private var manager = WallpaperManager.shared

    @State private var sidebar: SidebarItem = .home
    @State private var sidebarCollapsed = false
    // Set when a Home "browse more" CTA jumps to Discover with a filter
    // (e.g. Live / AI). Cleared when leaving Discover.
    @State private var pendingDiscoverFilter: DiscoverView.Filter?
    @State private var path: [MainRoute] = []
    @State private var search: String = ""
    @State private var committedSearch: String = ""
    @State private var showingUpload = false

    enum SidebarItem: String, CaseIterable, Hashable {
        // Browse section.
        case home, discover, weekly, collections
        // My Library section (signed-in only).
        case myUploads, myCollections, myDownloads, myFavorites, myLikes, myCoins
        // Actions group at the bottom of the sidebar. Upload opens the
        // upload sheet (handled by a tap side-effect, never becomes the
        // active selection); Settings routes to SettingsView.
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
                MainSidebar(selection: $sidebar, collapsed: $sidebarCollapsed,
                            onUpload: { showingUpload = true })
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
            .padding(.top, WindowChrome.topBar)
        }
        .ignoresSafeArea(.all)
        .background(Color.paper)
        .task { await auth.refreshProfile() }
        .sheet(isPresented: $showingUpload) {
            UploadView(onClose: { showingUpload = false })
                .frame(minWidth: 720, minHeight: 560)
        }
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
                    onPick: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) },
                    onDevice: { d in path.append(.device(slug: d.slug, name: d.name)) },
                    onWeeklyWeek: { y, w in path.append(.weeklyWeek(year: y, week: w)) },
                    onCategory: { c in path.append(.category(id: c.id, name: c.name, slug: c.slug)) },
                    onUploader: { username in path.append(.profile(username: username)) },
                    onCollection: { c in path.append(.collection(slug: c.slug, title: c.title)) },
                    onOpenDiscover: { f in pendingDiscoverFilter = f; sidebar = .discover },
                    onOpenCollections: { sidebar = .collections },
                    onOpenWeeklyArchive: { sidebar = .weekly }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationDestination(for: MainRoute.self) { route in
                switch route {
                case .detail(let slug, _):
                    DetailPage(slug: slug,
                               onUploader: { path.append(.profile(username: $0)) },
                               onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .profile(let username):
                    AccountView(username: username,
                                onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) },
                                onCollection: { c in path.append(.collection(slug: c.slug, title: c.title)) })
                case .collection(let slug, _):
                    CollectionDetailView(slug: slug,
                                         onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .device(let slug, let name):
                    DeviceDetailView(slug: slug, name: name,
                                     onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .search(let q):
                    SearchResultsView(query: q,
                                      onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .weeklyWeek(let y, let w):
                    WeeklyWeekView(year: y, week: w,
                                   onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                case .category(let id, let name, let slug):
                    CategoryFeedView(category: Category(id: id, name: name, slug: slug, sortOrder: nil),
                                     onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                }
                }
            }
        }
        .onChange(of: sidebar) { _, new in
            path.removeAll()
            // Don't let a Home-CTA filter linger when Discover is opened
            // directly from the sidebar later.
            if new != .discover { pendingDiscoverFilter = nil }
        }
    }

    private func commitSearch() {
        let q = search.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            committedSearch = ""
        } else {
            committedSearch = q
            path.append(.search(query: q))
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
        // Upload never becomes the active selection — its sidebar row
        // opens the upload sheet via a tap side-effect. Render nothing.
        case .upload:        Color.clear
        }
    }

    // The owner's account page, opened on a specific tab. The whole
    // "My Library" group + Settings now route here so the personal area
    // is one tabbed page (matching the web profile, plus a Settings tab).
    @ViewBuilder private func account(_ tab: AccountTab) -> some View {
        if let me = AuthService.shared.user?.username {
            AccountView(username: me, initialTab: tab, onWallpaper: onPick, onCollection: onCollection)
        } else {
            VStack(spacing: 12) {
                Text("Sign in to view your account.").font(.sans13).foregroundStyle(Color.muted)
                Button("Sign in") { AuthService.shared.login() }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
