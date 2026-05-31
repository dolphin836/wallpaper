import SwiftUI

// Devices index — grid of device profiles grouped by platform.
struct DevicesIndexView: View {
    var onPick: (DeviceProfile) -> Void

    @State private var devices: [DeviceProfile] = []
    @State private var loading = false
    @State private var loadError: String?

    private var grouped: [(platform: String, items: [DeviceProfile])] {
        let order = ["desktop", "laptop", "tablet", "phone", "watch", "tv", "other"]
        let buckets = Dictionary(grouping: devices) { $0.platform }
        return order.compactMap { p in
            guard let items = buckets[p], !items.isEmpty else { return nil }
            return (p, items.sorted { $0.sortOrder < $1.sortOrder })
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Find wallpapers sized for your hardware")
                    Text("Devices").font(.display32).foregroundStyle(Color.ink)
                }

                if loading && devices.isEmpty {
                    ProgressView().padding(.top, 30)
                } else if let err = loadError {
                    Text(err).font(.sans12).foregroundStyle(Color.warn)
                } else {
                    ForEach(grouped, id: \.platform) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Kicker(text: "\(group.platform.uppercased()) · \(group.items.count)")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 12, alignment: .top)], spacing: 12) {
                                ForEach(group.items) { d in
                                    Button(action: { onPick(d) }) {
                                        DeviceCard(device: d)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .center)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            devices = try await APIClient.shared.fetchDevices().filter { $0.isActive }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct DeviceCard: View {
    let device: DeviceProfile
    @State private var hover = false

    private var iconName: String {
        switch device.platform {
        case "phone":   "iphone"
        case "tablet":  "ipad"
        case "laptop":  "laptopcomputer"
        case "watch":   "applewatch"
        case "tv":      "tv"
        default:        "desktopcomputer"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.paper2)
                Image(systemName: iconName)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.ink2)
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hair, lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.sans13).foregroundStyle(Color.ink).lineLimit(1)
                Text("\(device.width)×\(device.height) · \(device.ppi) ppi")
                    .font(.mono10).tracking(0.4).foregroundStyle(Color.muted)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(hover ? Color.paper : Color.clear))
        .scaleEffect(hover ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: hover)
        .onHover { hover = $0 }
    }
}

// Device detail — header with device info + wallpapers grid.
struct DeviceDetailView: View {
    let slug: String
    let name: String
    var onWallpaper: (Wallpaper) -> Void

    @State private var info: DeviceProfileDetail?
    @State private var items: [Wallpaper] = []
    @State private var cursor: Int?
    @State private var hasMore = false
    @State private var loading = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if let d = info?.device {
                    header(d)
                } else {
                    Text(name).font(.display32).foregroundStyle(Color.ink)
                }

                if loading && items.isEmpty {
                    ProgressView()
                } else if items.isEmpty {
                    Text("No wallpapers for this device yet.")
                        .font(.sans13).foregroundStyle(Color.muted).padding(.top, 24)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(items) { wp in
                            Button(action: { onWallpaper(wp) }) {
                                MainGridTile(wallpaper: wp)
                            }
                            .buttonStyle(.plain)
                            .onAppear { maybeLoadMore(wp) }
                        }
                    }
                    if hasMore {
                        HStack { Spacer(); ProgressView().controlSize(.small).opacity(loading ? 1 : 0); Spacer() }
                            .frame(height: 24)
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 60)
            .frame(maxWidth: 1200).frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.paper.ignoresSafeArea())
        .task(id: slug) { await reload() }
    }

    private func header(_ d: DeviceProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: "\(d.platform.uppercased()) · \(d.brand) · \(info?.wallpaperCount ?? 0) wallpapers")
            Text(d.name).font(.display32).foregroundStyle(Color.ink)
            Text("\(d.width)×\(d.height) · \(d.ppi) ppi")
                .font(.mono11).tracking(0.5).foregroundStyle(Color.muted)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hair).frame(height: 1) }
    }

    private func reload() async {
        items = []; cursor = nil; hasMore = false
        if let d = try? await APIClient.shared.fetchDevice(slug: slug) { info = d }
        await loadMore()
    }
    private func loadMore() async {
        guard !loading else { return }
        loading = true; defer { loading = false }
        if let data = try? await APIClient.shared.fetchDeviceWallpapers(slug: slug, cursor: cursor, limit: 24) {
            items.append(contentsOf: data.items)
            cursor = data.nextCursor
            hasMore = data.hasMore
        }
    }
    private func maybeLoadMore(_ wp: Wallpaper) {
        guard hasMore, !loading, let last = items.last, wp.id == last.id else { return }
        Task { await loadMore() }
    }
}
