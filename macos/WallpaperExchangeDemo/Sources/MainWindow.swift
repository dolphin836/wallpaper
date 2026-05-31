import SwiftUI

// Top-level main window scene. Sidebar on the left, content grid in
// the middle, optional detail inspector on the right. Layout uses
// NavigationSplitView so macOS 14+ gives us native column resizing /
// sidebar collapse / unified toolbar for free.
struct MainWindow: View {
    @State private var selection: String = "discover"
    @State private var detail: DemoWallpaper? = nil
    @State private var search: String = ""

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .frame(minWidth: 220, idealWidth: 240)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            // Center: discover grid. The right-side inspector is a
            // transient sheet-style overlay rather than a third pane
            // so the grid keeps its full width when nothing is open.
            ZStack(alignment: .trailing) {
                ContentArea(selection: selection, search: $search, onPick: { detail = $0 })
                if let wp = detail {
                    DetailInspector(wallpaper: wp, onClose: { detail = nil })
                        .frame(width: 420)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .animation(.easeOut(duration: 0.22), value: detail)
            .toolbar { mainToolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.dPaper)
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(sectionTitle(for: selection))
                .font(.dDisplay18)
                .foregroundStyle(Color.dInk)
        }
        ToolbarItemGroup(placement: .principal) {
            // Centered search field — discover-style. Tracks selection
            // text but doesn't do anything in the demo.
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.dHair, lineWidth: 1)
                    )
            )
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: {}) {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .medium))
            }
            .help("Auto-shuffle wallpaper every 4 hours")
            .buttonStyle(.borderless)

            // Coin pill — accent.
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

            // Profile chip.
            Circle()
                .fill(Color.dPaper2)
                .overlay(Text("E").font(.dDisplay16).foregroundStyle(Color.dInk))
                .overlay(Circle().stroke(Color.dHair, lineWidth: 1))
                .frame(width: 28, height: 28)
        }
    }

    private func sectionTitle(for id: String) -> String {
        DemoData.destinations.first(where: { $0.id == id })?.label ?? "Discover"
    }
}

// Routing — picks the right content view per sidebar selection. The
// demo only renders the Discover grid; other destinations fall back
// to a stub placeholder so the user can navigate around to see the
// frame.
struct ContentArea: View {
    let selection: String
    @Binding var search: String
    var onPick: (DemoWallpaper) -> Void

    var body: some View {
        ZStack {
            // Soft paper backdrop with a subtle warm wash, mirroring the
            // web's body background.
            Color.dPaper.ignoresSafeArea()
            switch selection {
            case "discover":   DiscoverView(search: search, onPick: onPick)
            case "weekly":     StubView(title: "Weekly Picks", kicker: "Curated each Friday")
            case "device":     StubView(title: "Wallpapers for Your Device", kicker: "MacBook Pro 14\" · 3024 × 1964 · matched")
            case "category":   StubView(title: "Categories", kicker: "Nature · City · Anime · Abstract · Tech · …")
            case "downloads":  StubView(title: "Downloads", kicker: "12 wallpapers on this Mac")
            case "collections":StubView(title: "Collections", kicker: "5 lists")
            case "liked":      StubView(title: "Liked", kicker: "47 wallpapers")
            case "uploaded":   StubView(title: "Uploaded by You", kicker: "8 wallpapers · 412 coins earned")
            default: DiscoverView(search: search, onPick: onPick)
            }
        }
    }
}

// Placeholder for sections that aren't built out in the demo. Lets the
// user click around the sidebar without hitting empty screens.
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
