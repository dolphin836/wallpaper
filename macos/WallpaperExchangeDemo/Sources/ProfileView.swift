import SwiftUI

// Uploader / user profile page. Editorial header with avatar + name +
// bio + stats, then a tab segment for Uploaded / Liked / Favorited /
// Downloaded, then a grid below. Uses sample data so any tab clicks
// just show the same sample wallpapers — the goal is to validate the
// chrome.
struct ProfileView: View {
    let username: String
    var onPick: (DemoWallpaper) -> Void

    @State private var tab: Tab = .uploaded
    enum Tab: String, CaseIterable { case uploaded = "Uploaded", liked = "Liked", favorited = "Favorited", downloads = "Downloads" }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                tabRow
                grid
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.dPaper.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            // Avatar — 96 px circle, serif initial as fallback.
            Circle()
                .fill(Color.dPaper2)
                .frame(width: 96, height: 96)
                .overlay(
                    Text(String(username.prefix(1)).uppercased())
                        .font(.system(size: 40, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.dInk)
                )
                .overlay(Circle().stroke(Color.dHair, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "Uploader · Member since May 2025")
                Text("@\(username)")
                    .font(.dDisplay32)
                    .foregroundStyle(Color.dInk)
                Text("Nature photography from the Pacific Northwest. Long-exposure, foggy mornings, and the occasional alpine cabin.")
                    .font(.dSans13)
                    .foregroundStyle(Color.dMuted)
                    .frame(maxWidth: 600, alignment: .leading)

                // Stats row.
                HStack(spacing: 24) {
                    statBlock(label: "UPLOADS", value: "47")
                    statBlock(label: "DOWNLOADS", value: "2.1K")
                    statBlock(label: "LIKES", value: "880")
                    statBlock(label: "COLLECTIONS", value: "5")
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)

            // Right rail — Follow + Share. Follow is the accent action,
            // share is secondary.
            VStack(spacing: 8) {
                Button(action: {}) {
                    Text("Follow")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.dAccent))
                }
                .buttonStyle(.plain)
                Button(action: {}) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 11))
                        Text("Share profile").font(.dSans11)
                    }
                    .foregroundStyle(Color.dInk2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.dPaper))
                    .overlay(Capsule().stroke(Color.dHair, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.dHair).frame(height: 1)
        }
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(text: label)
            Text(value).font(.dDisplay18).foregroundStyle(Color.dInk)
        }
    }

    private var tabRow: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button(action: { tab = t }) {
                    Text(t.rawValue)
                        .font(.dSans12)
                        .foregroundStyle(tab == t ? Color.dInk : Color.dMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(tab == t ? Color.dPaper : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(4)
        .background(Capsule().fill(Color.dPaper2))
        .overlay(Capsule().stroke(Color.dHair, lineWidth: 1))
        .frame(maxWidth: 480, alignment: .leading)
    }

    private var grid: some View {
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
}
