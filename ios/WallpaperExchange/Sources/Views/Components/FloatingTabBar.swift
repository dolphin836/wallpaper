import SwiftUI

// Cross-tab selection state shared between the TabView and the floating
// bar instances living inside each tab's safe-area inset.
@MainActor
@Observable
final class TabRouter {
    static let shared = TabRouter()

    var selection = LaunchOptions.tab

    private init() {}
}

// Floating capsule tab bar: dark glass, line icons, the selected item
// carried by an accent rounded square. Lives in each root page's bottom
// safe-area inset so pushed pages naturally cover it.
struct FloatingTabBar: View {
    @Environment(TabRouter.self) private var router
    @Namespace private var tabSelection

    private let items: [(title: String, icon: String, selected: String, tag: Int)] = [
        ("Home", "mountain.2", "mountain.2.fill", 0),
        ("Discover", "square.grid.2x2", "square.grid.2x2.fill", 1),
        ("Make", "wand.and.stars", "wand.and.stars.inverse", 2),
        ("Me", "person", "person.fill", 3),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tag) { item in
                let isOn = router.selection == item.tag
                Button {
                    guard router.selection != item.tag else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        router.selection = item.tag
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isOn ? item.selected : item.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(item.title)
                            .font(.system(size: 10, weight: isOn ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(isOn ? Color.black.opacity(0.82) : .white.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        if isOn {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.accent)
                                .matchedGeometryEffect(id: "tab-selection", in: tabSelection)
                        }
                    }
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 66)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.46), radius: 22, y: 10)
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
        .environment(\.colorScheme, .dark)
        .archiveSelectionFeedback(trigger: router.selection)
    }
}
