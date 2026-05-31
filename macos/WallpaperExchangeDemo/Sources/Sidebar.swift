import SwiftUI

// Left-side navigation. Two grouped sections (Browse / My Library)
// matching the web's IA, plus a footer with the coin-pill profile cell
// + Settings shortcut. SwiftUI's List in .sidebar style gives us the
// translucent vibrant material and the standard selection chrome the
// rest of macOS uses, so the redesign feels native rather than
// re-inventing chrome.
struct Sidebar: View {
    @Binding var selection: String
    var onUpload: () -> Void = {}

    var body: some View {
        List(selection: Binding(get: { selection }, set: { selection = $0 ?? "discover" })) {
            // Logo row at the top of the sidebar — replaces the title
            // bar, since we run with .unified showsTitle=false.
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.dInk)
                    Image(systemName: "rectangle.stack.badge.play")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.dPaper)
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wallpaper")
                        .font(.dDisplay16)
                        .foregroundStyle(Color.dInk)
                    Text("EXCHANGE")
                        .font(.dKicker)
                        .tracking(2.5)
                        .foregroundStyle(Color.dMuted)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .selectionDisabled()

            ForEach(SidebarSection.allCases, id: \.self) { section in
                Section {
                    ForEach(DemoData.destinations.filter { $0.section == section }) { dest in
                        SidebarRow(destination: dest, isSelected: dest.id == selection)
                            .tag(dest.id)
                    }
                } header: {
                    Text(section.rawValue.uppercased())
                        .font(.dKicker)
                        .tracking(1.8)
                        .foregroundStyle(Color.dMuted)
                        .padding(.top, 4)
                }
            }

            // Big share/upload CTA — surfaces the contributor flow
            // without burying it behind a menu.
            Button(action: onUpload) {
                HStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.up").font(.system(size: 12, weight: .semibold))
                    Text("Share a wallpaper").font(.dSans12)
                    Spacer()
                    Text("⌘U").font(.dMono10).tracking(0.5).opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.dAccent))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("u", modifiers: .command)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .selectionDisabled()
            .padding(.top, 6)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
        }
    }
}

struct SidebarRow: View {
    let destination: DemoDestination
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: destination.icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(isSelected ? Color.dAccent : Color.dInk2)
            Text(destination.label)
                .font(.dSans13)
                .foregroundStyle(Color.dInk)
            Spacer()
            if let badge = destination.badge {
                Text(badge)
                    .font(.dMono10)
                    .tracking(0.6)
                    .foregroundStyle(Color.dMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule().fill(Color.dPaper2)
                    )
            }
        }
        .padding(.vertical, 1)
    }
}

// Profile + coin pill anchored to the sidebar's bottom edge so the
// signed-in state stays glanceable regardless of which destination is
// open. Tapping anywhere here in the real app would jump to a profile
// view; in the demo it's static.
struct SidebarFooter: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Color.dPaper2
                Text("E").font(.dDisplay16).foregroundStyle(Color.dInk)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.dHair, lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                Text("Eric").font(.dSans12).foregroundStyle(Color.dInk)
                HStack(spacing: 4) {
                    Circle().fill(Color.dAccent).frame(width: 8, height: 8)
                    Text("124 coins")
                        .font(.dMono10)
                        .tracking(0.5)
                        .foregroundStyle(Color.dMuted)
                }
            }
            Spacer()
            Button(action: {}) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.dInk2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.dHair).frame(height: 1)
        }
    }
}
