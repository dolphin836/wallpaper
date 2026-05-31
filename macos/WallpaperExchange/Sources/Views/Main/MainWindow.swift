import SwiftUI

// v2.1 main window. Web-parity layout: a single horizontal top
// navigation bar (logo / nav links / search / coin pill / avatar),
// then a content area that pushes detail / profile / collection /
// device pages onto an inner NavigationStack. Drops the sidebar
// per the design review — Mac client now reads the same as the
// web app.
struct MainWindow: View {
    @State private var auth = AuthService.shared
    @State private var manager = WallpaperManager.shared

    @State private var tab: TopTab = .discover
    @State private var path: [MainRoute] = []
    @State private var search: String = ""
    @State private var committedSearch: String = ""
    @State private var showingUpload = false

    enum TopTab: String, CaseIterable, Hashable {
        case home = "Home"
        case discover = "Discover"
        case weekly = "Weekly"
        case collections = "Collections"
        case uploaders = "Uploaders"
        case devices = "Devices"
        case macApp = "Mac App"

        var routeKey: String { rawValue.lowercased() }
    }

    enum MainRoute: Hashable {
        case detail(slug: String, fallbackID: Int)
        case profile(username: String)
        case collection(slug: String, title: String)
        case device(slug: String, name: String)
        case search(query: String)
        case weeklyWeek(year: Int, week: Int)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                TopNavBar(
                    tab: $tab,
                    search: $search,
                    onCommitSearch: { commitSearch() },
                    onUpload: { showingUpload = true },
                    onProfile: {
                        if let u = auth.user { path.append(.profile(username: u.username)) }
                    },
                    onLogin: { auth.login() },
                    onLogout: { auth.logout() },
                    auth: auth,
                    manager: manager
                )
                Divider().background(Color.hair)

                ContentRouter(
                    tab: tab,
                    search: committedSearch,
                    onPick: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) },
                    onDevice: { d in path.append(.device(slug: d.slug, name: d.name)) },
                    onWeeklyWeek: { y, w in path.append(.weeklyWeek(year: y, week: w)) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.paper.ignoresSafeArea())
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
                }
            }
        }
        .background(Color.paper)
        .task { await auth.refreshProfile() }
        .sheet(isPresented: $showingUpload) {
            UploadView(onClose: { showingUpload = false })
                .frame(minWidth: 720, minHeight: 560)
        }
        .onChange(of: tab) { _, _ in path.removeAll() }
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

// Routes the active top tab to its content view.
struct ContentRouter: View {
    let tab: MainWindow.TopTab
    let search: String
    var onPick: (Wallpaper) -> Void
    var onDevice: (DeviceProfile) -> Void
    var onWeeklyWeek: (Int, Int) -> Void

    var body: some View {
        switch tab {
        case .home, .discover:
            DiscoverView(search: search, onPick: onPick)
        case .weekly:
            WeeklyArchiveView(onOpenWeek: onWeeklyWeek)
        case .collections:
            CollectionsListView()
        case .uploaders:
            ComingSoonStub(title: "Uploaders", kicker: "Top contributors · this week")
        case .devices:
            DevicesIndexView(onPick: onDevice)
        case .macApp:
            ComingSoonStub(title: "Mac App", kicker: "You're already on it.")
        }
    }
}

// Generic placeholder. Kept so the user can navigate without hitting
// empty screens; only Uploaders and Mac App tabs still use it.
struct ComingSoonStub: View {
    let title: String
    let kicker: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: kicker)
            Text(title).font(.display32).foregroundStyle(Color.ink)
            Text("This section is being wired into the new design. Use the menu-bar popover for now.")
                .font(.sans13).foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(40)
    }
}
