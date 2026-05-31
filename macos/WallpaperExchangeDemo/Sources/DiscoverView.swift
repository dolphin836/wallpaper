import SwiftUI

// Main content view for the Discover tab. Editorial header with kicker
// + display-serif title, filter pill row, then the wallpaper grid.
// Grid uses LazyVGrid with adaptive minimum so the column count scales
// to the window width — the same affordance the web's discover feed
// has, ported to a fixed-aspect tile.
struct DiscoverView: View {
    let search: String
    var onPick: (DemoWallpaper) -> Void

    @State private var filter: String = "Latest"
    private let filters = ["Latest", "Trending", "For You", "My Device", "Dynamic", "AI"]

    private var filtered: [DemoWallpaper] {
        let s = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return DemoData.wallpapers }
        return DemoData.wallpapers.filter {
            $0.title.lowercased().contains(s) ||
            $0.category.lowercased().contains(s) ||
            $0.tags.contains { $0.lowercased().contains(s) }
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                editorialHeader
                filterPills

                // Adaptive grid. min: 260 → fits 4 tiles at the
                // default 1280 window width with 24 px gutters.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 16, alignment: .top)],
                    spacing: 16
                ) {
                    ForEach(filtered) { wp in
                        WallpaperTile(wallpaper: wp)
                            .onTapGesture { onPick(wp) }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 80)
        }
    }

    private var editorialHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: "Today · 31 May 2026")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Find something for your")
                    .font(.dDisplay32)
                    .foregroundStyle(Color.dInk)
                Text("Mac.")
                    .font(.dDisplay32)
                    .foregroundStyle(Color.dAccent)
            }
            Text("Hand-picked wallpapers from the community. Try the device-matched section for sizes tailored to your screen.")
                .font(.dSans13)
                .foregroundStyle(Color.dMuted)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var filterPills: some View {
        HStack(spacing: 6) {
            ForEach(filters, id: \.self) { f in
                let isOn = filter == f
                Button(action: { filter = f }) {
                    Text(f)
                        .font(.dSans12)
                        .foregroundStyle(isOn ? Color.dPaper : Color.dInk2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isOn ? Color.dInk : Color.dPaper2)
                        )
                        .overlay(
                            Capsule().stroke(Color.dHair, lineWidth: isOn ? 0 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            // Right-side: layout density toggle (icon-only). Static in
            // the demo but communicates that the redesign honours
            // user preference for tile size.
            HStack(spacing: 4) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dInk2)
                Rectangle().fill(Color.dHair).frame(width: 1, height: 14)
                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.dMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.dPaper2))
        }
    }
}
