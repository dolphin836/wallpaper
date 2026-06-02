import SwiftUI

// v2.2 main window. Left sidebar (Browse + My Library + footer
// identity cell) and a thin top toolbar above the content area.
// Full-page push for detail / profile / collection / device / etc.
struct MainWindow: View {
    @State private var auth = AuthService.shared
    @State private var manager = WallpaperManager.shared

    @State private var sidebar: SidebarItem = .home
    @State private var path: [MainRoute] = []
    @State private var search: String = ""
    @State private var committedSearch: String = ""
    @State private var showingUpload = false

    enum SidebarItem: String, CaseIterable, Hashable {
        // Browse section.
        case home, discover, weekly, collections
        // My Library section (signed-in only).
        case myUploads, myCollections, myDownloads, myFavorites, myLikes, myCoins
        // Actions section (always visible). Upload triggers the
        // existing UploadView sheet; Settings routes to SettingsView.
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
            case .upload:        "plus.circle.fill"
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
        // macOS 26's Liquid-Glass sidebar — rounded card with a small
        // gap to the window edge — is exactly the look Claude.app /
        // Linear use, and it's what NavigationSplitView gives us for
        // free. We just need the sidebar to extend into the title-bar
        // area so the traffic lights sit *inside* the sidebar's
        // rounded top-left (not on a separate strip above it).
        NavigationSplitView {
            MainSidebar(selection: $sidebar)
                .frame(minWidth: 220, idealWidth: 240)
                .toolbar(removing: .sidebarToggle)
                // Push the sidebar up into the title-bar region so
                // the traffic lights overlay the sidebar's top-left
                // rounded corner — without this the sidebar pane
                // starts BELOW the title-bar strip leaving a gap.
                .ignoresSafeArea(.container, edges: .top)
        } detail: {
            NavigationStack(path: $path) {
                ZStack {
                    // Page-mesh palette tint behind content. Lives at
                    // the detail-pane root so hover-driven palette
                    // changes paint behind every page, just like the
                    // web's .d3-discover-mesh.
                    Color.paper.ignoresSafeArea()
                    PageMesh()

                    // Top toolbar removed. Upload + all utility actions
                    // (logout, downloads, shuffle, theme) now live in
                    // the sidebar (Upload row + Settings row).
                    // .ignoresSafeArea(.container, edges: .top) makes
                    // the detail pane start at the window's true top
                    // edge (same as the sidebar) so the two panes
                    // share the same y=0 origin. Inner pages add
                    // WindowChrome.topInset for traffic-light
                    // clearance so the first row lines up with the
                    // sidebar logo, regardless of full-screen state.
                    ContentRouter(
                        sidebar: sidebar,
                        search: committedSearch,
                        onPick: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) },
                        onDevice: { d in path.append(.device(slug: d.slug, name: d.name)) },
                        onWeeklyWeek: { y, w in path.append(.weeklyWeek(year: y, week: w)) },
                        onCategory: { c in path.append(.category(id: c.id, name: c.name, slug: c.slug)) },
                        onUploader: { username in path.append(.profile(username: username)) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .top)
                }
                .navigationDestination(for: MainRoute.self) { route in
                    switch route {
                    case .detail(let slug, _):
                        DetailPage(slug: slug,
                                   onUploader: { path.append(.profile(username: $0)) },
                                   onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
                    case .profile(let username):
                        ProfileView(username: username,
                                    onWallpaper: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) })
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
            .onChange(of: sidebar) { _, new in
                path.removeAll()
                // Upload row is a synthetic sidebar selection — it
                // opens the upload sheet then immediately routes back
                // to Home so the row doesn't stay "selected" with an
                // empty pane underneath.
                if new == .upload {
                    showingUpload = true
                    DispatchQueue.main.async { sidebar = .home }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.paper)
        .task { await auth.refreshProfile() }
        .sheet(isPresented: $showingUpload) {
            UploadView(onClose: { showingUpload = false })
                .frame(minWidth: 720, minHeight: 560)
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
    var onPick: (Wallpaper) -> Void
    var onDevice: (DeviceProfile) -> Void
    var onWeeklyWeek: (Int, Int) -> Void
    var onCategory: (Category) -> Void
    var onUploader: (String) -> Void

    var body: some View {
        switch sidebar {
        case .home:          HomeView(onPick: onPick, onOpenWeek: onWeeklyWeek)
        case .discover:      DiscoverView(search: search, onPick: onPick)
        case .weekly:        WeeklyArchiveView(onOpenWeek: onWeeklyWeek)
        case .collections:   CollectionsListView()
        case .myUploads:     MyLibraryGridView(kind: .uploads, onPick: onPick)
        case .myCollections: MyLibraryCollectionsView()
        case .myDownloads:   MyLibraryGridView(kind: .downloads, onPick: onPick)
        case .myFavorites:   MyLibraryGridView(kind: .favorites, onPick: onPick)
        case .myLikes:       MyLibraryGridView(kind: .likes, onPick: onPick)
        case .myCoins:       MyCoinsView()
        case .settings:      SettingsView(onOpenProfile: onUploader)
        // .upload is handled in MainWindow via a side-effect on
        // sidebar selection — it shows the UploadView sheet and
        // bounces the selection back to home. Render nothing here.
        case .upload:        Color.clear
        }
    }
}
