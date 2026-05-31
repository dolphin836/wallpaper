import SwiftUI

// Top-level main window scene. Sidebar on the left, content stack on
// the right. Detail navigation is now full-page push (not a side
// inspector) per the v2 design decision — the main content column
// owns its own NavigationStack so clicking a wallpaper, uploader or
// collection pushes a new page with a real back affordance, while the
// sidebar selection acts as the stack root.
struct MainWindow: View {
    @State private var selection: String = "discover"
    @State private var path: [Route] = []
    @State private var search: String = ""
    @State private var showingUpload = false

    // Routes that can be pushed onto the inner NavigationStack. Each
    // case carries the data it needs so deep-link state survives a
    // sidebar switch / window resize without an extra ID lookup.
    enum Route: Hashable {
        case detail(DemoWallpaper)
        case profile(uploader: String)
        case collection(id: Int, title: String)
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection, onUpload: { showingUpload = true })
                .frame(minWidth: 230, idealWidth: 250)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack(path: $path) {
                ContentArea(
                    selection: selection,
                    search: $search,
                    onPick: { path.append(.detail($0)) }
                )
                .background(Color.dPaper.ignoresSafeArea())
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .detail(let wp):
                        DetailPage(wallpaper: wp, onUploader: { username in
                            path.append(.profile(uploader: username))
                        }, onCollection: { id, title in
                            path.append(.collection(id: id, title: title))
                        })
                    case .profile(let uploader):
                        ProfileView(username: uploader, onPick: { path.append(.detail($0)) })
                    case .collection(let id, let title):
                        CollectionDetailView(id: id, title: title, onPick: { path.append(.detail($0)) })
                    }
                }
                .toolbar { mainToolbar }
            }
            // Reset the inner stack whenever the sidebar root changes —
            // pushing detail pages on top of one section then jumping
            // to another shouldn't leak the old breadcrumb.
            .onChange(of: selection) { _, _ in path.removeAll() }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.dPaper)
        .sheet(isPresented: $showingUpload) {
            UploadView(onClose: { showingUpload = false })
                .frame(minWidth: 720, minHeight: 560)
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(toolbarTitle)
                .font(.dDisplay18)
                .foregroundStyle(Color.dInk)
                .help(toolbarTitle)
        }
        ToolbarItemGroup(placement: .principal) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dMuted)
                TextField("Search wallpapers, devices, tags…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.dSans12)
                    .frame(width: 320)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.dPaper2)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.dHair, lineWidth: 1))
            )
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { showingUpload = true }) {
                Label("Upload", systemImage: "tray.and.arrow.up")
                    .font(.dSans12)
            }
            .help("Share a wallpaper (⌘U)")
            .keyboardShortcut("u", modifiers: .command)

            Button(action: {}) {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .medium))
            }
            .help("Auto-shuffle wallpaper every 4 hours")

            HStack(spacing: 6) {
                Circle().fill(Color.dAccent).frame(width: 14, height: 14)
                Text("124")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.dPaper)
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.dInk))

            Circle()
                .fill(Color.dPaper2)
                .overlay(Text("E").font(.dDisplay16).foregroundStyle(Color.dInk))
                .overlay(Circle().stroke(Color.dHair, lineWidth: 1))
                .frame(width: 28, height: 28)
        }
    }

    private var toolbarTitle: String {
        if let last = path.last {
            switch last {
            case .detail(let wp): return wp.title
            case .profile(let u): return "@\(u)"
            case .collection(_, let title): return title
            }
        }
        return DemoData.destinations.first(where: { $0.id == selection })?.label ?? "Discover"
    }
}

// Routes — picks the right content view per sidebar selection.
struct ContentArea: View {
    let selection: String
    @Binding var search: String
    var onPick: (DemoWallpaper) -> Void

    var body: some View {
        switch selection {
        case "discover":    DiscoverView(search: search, onPick: onPick)
        case "weekly":      StubView(title: "Weekly Picks", kicker: "Curated each Friday")
        case "device":      StubView(title: "Wallpapers for Your Device", kicker: "MacBook Pro 14\" · 3024 × 1964 · matched")
        case "category":    StubView(title: "Categories", kicker: "Nature · City · Anime · Abstract · Tech · …")
        case "downloads":   DiscoverView(search: search, onPick: onPick)
        case "collections": CollectionsListView(onOpen: { _, _ in })
        case "liked":       DiscoverView(search: search, onPick: onPick)
        case "uploaded":    DiscoverView(search: search, onPick: onPick)
        default:            DiscoverView(search: search, onPick: onPick)
        }
    }
}

struct StubView: View {
    let title: String
    let kicker: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Kicker(text: kicker)
            Text(title).font(.dDisplay32).foregroundStyle(Color.dInk)
            Text("Demo placeholder. The redesigned section would render here.")
                .font(.dSans13)
                .foregroundStyle(Color.dMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(40)
    }
}

struct SettingsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings (preview)").font(.dDisplay18).foregroundStyle(Color.dInk)
            Toggle("Launch at login", isOn: .constant(true))
            Toggle("Auto-shuffle every 4 hours", isOn: .constant(false))
            Toggle("Show menu-bar icon", isOn: .constant(true))
            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: 260)
    }
}
