import SwiftUI

// Collections list — used when the sidebar 'Collections' destination
// is selected. Renders a grid of collection cards, each a 2×2
// composition of its first 4 wallpapers + a serif title + count.
// Clicking opens CollectionDetailView.
struct CollectionsListView: View {
    var onOpen: (Int, String) -> Void

    private struct DemoCollection: Identifiable, Hashable {
        static func == (lhs: DemoCollection, rhs: DemoCollection) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
        let id: Int
        let title: String
        let kicker: String
        let count: Int
        let tiles: [DemoWallpaper]
    }
    private let collections: [DemoCollection] = [
        .init(id: 1, title: "Pacific Northwest", kicker: "5 wallpapers · curated", count: 5, tiles: Array(DemoData.wallpapers.shuffled().prefix(4))),
        .init(id: 2, title: "Cabin Mood",        kicker: "8 wallpapers",          count: 8, tiles: Array(DemoData.wallpapers.shuffled().prefix(4))),
        .init(id: 3, title: "Neon Nights",       kicker: "12 wallpapers",         count: 12, tiles: Array(DemoData.wallpapers.shuffled().prefix(4))),
        .init(id: 4, title: "Studio Gradients",  kicker: "6 wallpapers",          count: 6, tiles: Array(DemoData.wallpapers.shuffled().prefix(4))),
        .init(id: 5, title: "Game Fanart Drop",  kicker: "9 wallpapers",          count: 9, tiles: Array(DemoData.wallpapers.shuffled().prefix(4))),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Curated lists · yours and the community's")
                    Text("Collections")
                        .font(.dDisplay32)
                        .foregroundStyle(Color.dInk)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 18, alignment: .top)],
                    spacing: 18
                ) {
                    ForEach(collections) { c in
                        Button(action: { onOpen(c.id, c.title) }) {
                            CollectionCard(title: c.title, kicker: c.kicker, count: c.count, tiles: c.tiles)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct CollectionCard: View {
    let title: String
    let kicker: String
    let count: Int
    let tiles: [DemoWallpaper]

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 2×2 cover composition.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    if i < tiles.count {
                        AsyncImage(url: tiles[i].previewURL) { phase in
                            if case .success(let img) = phase {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                tiles[i].dominant.opacity(0.5)
                            }
                        }
                        .frame(height: 80)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    } else {
                        Color.dPaper2.frame(height: 80)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.dHair, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.dDisplay16).foregroundStyle(Color.dInk)
                HStack(spacing: 4) {
                    Text(kicker.uppercased()).font(.dKicker).tracking(1.5).foregroundStyle(Color.dMuted)
                    Spacer()
                    Text("\(count)").font(.dMono10).foregroundStyle(Color.dMuted)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(hover ? Color.dPaper : Color.clear)
        )
        .scaleEffect(hover ? 1.01 : 1.0)
        .shadow(color: Color.black.opacity(hover ? 0.08 : 0), radius: 10, x: 0, y: 4)
        .animation(.easeOut(duration: 0.18), value: hover)
        .onHover { hover = $0 }
    }
}

// CollectionDetailView — opens when a collection card is clicked.
// Editorial header + grid of the items.
struct CollectionDetailView: View {
    let id: Int
    let title: String
    var onPick: (DemoWallpaper) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Collection №\(id) · curated by @forest_walker")
                    Text(title)
                        .font(.dDisplay32)
                        .foregroundStyle(Color.dInk)
                    Text("A standing selection — fog-soaked forests, alpine lakes, and the occasional cabin shot. Pulls grow each week.")
                        .font(.dSans13)
                        .foregroundStyle(Color.dMuted)
                        .frame(maxWidth: 600, alignment: .leading)
                    HStack(spacing: 16) {
                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "heart").font(.system(size: 11))
                                Text("Like collection").font(.dSans11)
                            }
                            .foregroundStyle(Color.dInk2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.dPaper))
                            .overlay(Capsule().stroke(Color.dHair, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 11))
                                Text("Follow").font(.dSans11)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.dAccent))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.dHair).frame(height: 1) }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14, alignment: .top)],
                    spacing: 14
                ) {
                    ForEach(DemoData.wallpapers) { wp in
                        Button(action: { onPick(wp) }) {
                            WallpaperTile(wallpaper: wp)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.dPaper.ignoresSafeArea())
    }
}
