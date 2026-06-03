import SwiftUI
import AppKit

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
        // Settings routes to SettingsView. (Upload is now a top-bar
        // button over the content area, not a sidebar item.)
        case settings

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
                MainSidebar(selection: $sidebar)
                    .frame(width: 240)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.93, green: 0.95, blue: 0.97), Color.paper],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: WindowChrome.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: WindowChrome.radius, style: .continuous)
                            .strokeBorder(Color.hair, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 2)
                    .padding(.bottom, WindowChrome.inset)

                detailPane
                    .clipShape(.rect(topLeadingRadius: WindowChrome.radius))
            }
            .padding(.leading, WindowChrome.inset)
            .padding(.top, WindowChrome.topBar)
        }
        // Upload sits in the paper top bar, centred over the detail
        // content and on the same row as the traffic lights.
        .overlay(alignment: .top) { uploadTopBar }
        .ignoresSafeArea(.all)
        .background(Color.paper)
        .task { await auth.refreshProfile() }
        .sheet(isPresented: $showingUpload) {
            UploadView(onClose: { showingUpload = false })
                .frame(minWidth: 720, minHeight: 560)
        }
    }

    // Top-bar Upload button, horizontally centred over the detail
    // content. The leading clear spacer skips the sidebar column so the
    // pill centres over the content pane, not the whole window.
    private var uploadTopBar: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: WindowChrome.inset * 2 + 240)
            Spacer(minLength: 0)
            UploadPillButton { showingUpload = true }
            Spacer(minLength: 0)
        }
        .frame(height: WindowChrome.topBar)
    }

    // Detail surface: page-mesh palette tint behind every page (mirrors
    // the web's .d3-discover-mesh), the routed content, and the
    // navigation stack for full-page pushes.
    private var detailPane: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.paper
                PageMesh()
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
        .onChange(of: sidebar) { _, _ in
            path.removeAll()
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
        }
    }
}

// Accent pill Upload button that lives in the window top bar, on the
// same row as the traffic lights and centred over the content area.
private struct UploadPillButton: View {
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                Text("Upload").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.accent.opacity(hover ? 1.0 : 0.92)))
            .shadow(color: Color.accent.opacity(hover ? 0.35 : 0.0), radius: 6, y: 1)
        }
        .buttonStyle(.plain)
        .help("Upload a wallpaper")
        .scaleEffect(hover ? 1.03 : 1.0)
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}
