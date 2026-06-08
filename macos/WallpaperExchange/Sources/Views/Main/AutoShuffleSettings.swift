import SwiftUI

// Auto-shuffle cadence controls. Lives on the owner's Downloads page
// because it only works with locally downloaded wallpapers.
private struct AutoShufflePreset: Identifiable {
    let label: String
    let seconds: TimeInterval
    var id: TimeInterval { seconds }
}

struct AutoShuffleSettings: View {
    @State private var manager = WallpaperManager.shared

    private let presets: [AutoShufflePreset] = [
        .init(label: "30 min", seconds: 30 * 60),
        .init(label: "1 hour", seconds: 1 * 3600),
        .init(label: "2 hours", seconds: 2 * 3600),
        .init(label: "4 hours", seconds: 4 * 3600),
        .init(label: "8 hours", seconds: 8 * 3600),
        .init(label: "12 hours", seconds: 12 * 3600),
        .init(label: "1 day", seconds: 24 * 3600),
    ]

    private var minuteBinding: Binding<Double> {
        Binding(
            get: { manager.autoRotateInterval / 60 },
            set: { manager.setAutoRotateInterval($0 * 60) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(
                get: { manager.autoRotate },
                set: { manager.setAutoRotate($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-shuffle").font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text("Switch to a random downloaded wallpaper every \(manager.autoRotateIntervalLabel)")
                        .font(.system(size: 11)).foregroundStyle(Color.muted)
                }
            }
            .toggleStyle(.switch)
            .tint(Color.accent)

            Divider().background(Color.hair)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Interval")
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
                            Text("Custom")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.ink)
                            Text("15-minute steps")
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
            Text(preset.label)
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
