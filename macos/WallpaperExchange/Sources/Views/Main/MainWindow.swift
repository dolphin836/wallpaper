import SwiftUI

// Top-level main window scene. Sidebar on the left (NavigationSplitView)
// + inner NavigationStack for full-page detail / profile / collection
// drill-downs. Search field is centered in the unified toolbar; the
// upload sheet is hoisted to this window so it's reachable from both
// the sidebar CTA and ⌘U.
struct MainWindow: View {
    @State private var auth = AuthService.shared
    @State private var manager = WallpaperManager.shared

    @State private var sidebar: SidebarItem = .discover
    @State private var path: [MainRoute] = []
    @State private var search: String = ""
    @State private var showingUpload = false

    enum SidebarItem: String, CaseIterable, Hashable {
        case discover, weekly, device, categories, downloads, collections, liked, uploaded
        var label: String {
            switch self {
            case .discover:    "Discover"
            case .weekly:      "Weekly Picks"
            case .device:      "For Your Device"
            case .categories:  "Categories"
            case .downloads:   "Downloads"
            case .collections: "Collections"
            case .liked:       "Liked"
            case .uploaded:    "Uploaded by Me"
            }
        }
        var icon: String {
            switch self {
            case .discover:    "sparkles"
            case .weekly:      "calendar.badge.clock"
            case .device:      "laptopcomputer"
            case .categories:  "square.grid.3x2"
            case .downloads:   "arrow.down.circle"
            case .collections: "rectangle.stack"
            case .liked:       "heart"
            case .uploaded:    "tray.and.arrow.up"
            }
        }
    }

    // Routes pushed onto the inner NavigationStack so deep-link state
    // survives a window resize without an extra ID lookup.
    enum MainRoute: Hashable {
        case detail(slug: String, fallbackID: Int)
        case profile(username: String)
        case collection(slug: String, title: String)
    }

    var body: some View {
        NavigationSplitView {
            MainSidebar(selection: $sidebar, onUpload: { showingUpload = true })
                .frame(minWidth: 230, idealWidth: 250)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack(path: $path) {
                ContentRouter(
                    sidebar: sidebar,
                    search: search,
                    onPick: { wp in path.append(.detail(slug: wp.slug, fallbackID: wp.id)) }
                )
                .background(Color.paper.ignoresSafeArea())
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
                    }
                }
                .toolbar { mainToolbar }
            }
            // Reset the inner stack when the sidebar root changes so a
            // deep breadcrumb from one section doesn't leak into another.
            .onChange(of: sidebar) { _, _ in path.removeAll() }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.paper)
        .task { await auth.refreshProfile() }
        .sheet(isPresented: $showingUpload) {
            UploadView(onClose: { showingUpload = false })
                .frame(minWidth: 720, minHeight: 560)
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(toolbarTitle)
                .font(.displayLg)
                .foregroundStyle(Color.ink)
                .help(toolbarTitle)
        }
        ToolbarItemGroup(placement: .principal) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
                TextField("Search wallpapers, devices, tags…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.sans12)
                    .frame(width: 320)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.paper2)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hair, lineWidth: 1))
            )
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { showingUpload = true }) {
                Label("Upload", systemImage: "tray.and.arrow.up")
                    .font(.sans12)
            }
            .help("Share a wallpaper (⌘U)")
            .keyboardShortcut("u", modifiers: .command)

            Button(action: { manager.setAutoRotate(!manager.autoRotate) }) {
                Image(systemName: manager.autoRotate ? "shuffle.circle.fill" : "shuffle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(manager.autoRotate ? Color.accent : Color.ink2)
            }
            .help("Auto-shuffle wallpaper every 4 hours")

            if auth.isLoggedIn, let u = auth.user {
                HStack(spacing: 6) {
                    Circle().fill(Color.accent).frame(width: 14, height: 14)
                    Text("\(u.coins)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.paper)
                        .monospacedDigit()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.ink))

                Button(action: { path.append(.profile(username: u.username)) }) {
                    Circle()
                        .fill(Color.paper2)
                        .overlay(Text(String((u.nickname.isEmpty ? u.username : u.nickname).prefix(1)).uppercased()).font(.displayMd).foregroundStyle(Color.ink))
                        .overlay(Circle().stroke(Color.hair, lineWidth: 1))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Open your profile")
            } else {
                Button("Sign in") { auth.login() }
                    .controlSize(.small)
            }
        }
    }

    private var toolbarTitle: String {
        if let last = path.last {
            switch last {
            case .detail: return "Wallpaper"
            case .profile(let u): return "@\(u)"
            case .collection(_, let title): return title
            }
        }
        return sidebar.label
    }
}

// Routes the sidebar selection to the right top-level content view.
struct ContentRouter: View {
    let sidebar: MainWindow.SidebarItem
    let search: String
    var onPick: (Wallpaper) -> Void

    var body: some View {
        switch sidebar {
        case .discover:    DiscoverView(search: search, onPick: onPick)
        case .weekly:      ComingSoonStub(title: "Weekly Picks", kicker: "Curated each Friday")
        case .device:      DiscoverView(search: search, onPick: onPick, deviceMatch: true)
        case .categories:  ComingSoonStub(title: "Categories", kicker: "Nature · City · Anime · Abstract · Tech · …")
        case .downloads:   DownloadsView(onPick: onPick)
        case .collections: CollectionsListView()
        case .liked:       MyLikesView(onPick: onPick)
        case .uploaded:    MyUploadsView(onPick: onPick)
        }
    }
}

// Generic placeholder for sections that aren't yet built out. Lets
// the user navigate without hitting empty screens.
struct ComingSoonStub: View {
    let title: String
    let kicker: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: kicker)
            Text(title).font(.display32).foregroundStyle(Color.ink)
            Text("This section is being wired into the new design. Use the menu-bar popover for now.")
                .font(.sans13)
                .foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(40)
    }
}
