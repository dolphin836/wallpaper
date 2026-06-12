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

    private let items: [(icon: String, selected: String, tag: Int)] = [
        ("mountain.2", "mountain.2.fill", 0),
        ("square.grid.2x2", "square.grid.2x2.fill", 1),
        ("wand.and.stars", "wand.and.stars.inverse", 2),
        ("person", "person.fill", 3),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tag) { item in
                let isOn = router.selection == item.tag
                Button {
                    router.selection = item.tag
                } label: {
                    Image(systemName: isOn ? item.selected : item.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isOn ? Color.black.opacity(0.82) : .white.opacity(0.85))
                        .frame(width: 46, height: 46)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(Color.accent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 60)
        .background(.black.opacity(0.32), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
        .environment(\.colorScheme, .dark)
    }
}
