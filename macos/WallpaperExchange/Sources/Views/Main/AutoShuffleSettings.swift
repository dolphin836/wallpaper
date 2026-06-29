import SwiftUI

// Auto-shuffle cadence controls. The rotation source can be all local
// downloads, or a prioritized collection whose wallpapers are local.
private struct AutoShufflePreset: Identifiable {
    let seconds: TimeInterval
    var id: TimeInterval { seconds }
}

struct AutoShuffleSettings: View {
    @State private var manager = WallpaperManager.shared

    private let presets: [AutoShufflePreset] = [
        .init(seconds: 30 * 60),
        .init(seconds: 1 * 3600),
        .init(seconds: 2 * 3600),
        .init(seconds: 4 * 3600),
        .init(seconds: 8 * 3600),
        .init(seconds: 12 * 3600),
        .init(seconds: 24 * 3600),
    ]

    private var minuteBinding: Binding<Double> {
        Binding(
            get: { manager.autoRotateInterval / 60 },
            set: { manager.setAutoRotateInterval($0 * 60) }
        )
    }

    private var sourceDescription: String {
        if let title = manager.autoRotateCollectionTitle {
            return L10n.account.collectionAutoPlayStatus(title)
        }
        return L10n.account.autoShuffleLocalStatus(manager.autoRotateIntervalLabel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(
                get: { manager.autoRotate },
                set: { manager.setAutoRotate($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.account.autoShuffleTitle).font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text(sourceDescription)
                        .font(.system(size: 11)).foregroundStyle(Color.muted)
                }
            }
            .toggleStyle(.switch)
            .tint(Color.accent)

            Divider().background(Color.hair)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.account.autoShuffleInterval)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink2)
                    Spacer()
                    Text(manager.autoRotateIntervalLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accent)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 76, maximum: 110), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(presets) { preset in
                        intervalChip(preset)
                    }
                }

                Stepper(
                    value: minuteBinding,
                    in: (WallpaperManager.minAutoRotateInterval / 60)...(WallpaperManager.maxAutoRotateInterval / 60),
                    step: 15
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.account.autoShuffleCustom)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.ink)
                            Text(L10n.account.autoShuffleStepDetail)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.muted)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func intervalChip(_ preset: AutoShufflePreset) -> some View {
        let isOn = abs(manager.autoRotateInterval - preset.seconds) < 1
        return Button(action: { manager.setAutoRotateInterval(preset.seconds) }) {
            Text(WallpaperManager.formatAutoRotateInterval(preset.seconds))
                .font(.system(size: 11, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? Color.paper : Color.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isOn ? Color.ink : Color.paper2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isOn ? Color.clear : Color.hair, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
