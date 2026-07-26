import AppKit
import SwiftUI

struct GenerativeWallpapersView: View {
    var onOpen: (GenerativePreset) -> Void

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(1, proxy.size.width - 80)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: min(420, contentWidth), maximum: 760), spacing: 24)],
                        alignment: .leading,
                        spacing: 24
                    ) {
                        ForEach(GenerativePreset.allCases) { preset in
                            GenerativePresetCard(preset: preset) {
                                onOpen(preset)
                            }
                        }
                    }
                    .padding(.top, 30)
                }
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Kicker(text: L10n.generative.kicker)
                Text(L10n.generative.title)
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                    .tracking(-0.8)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text(L10n.generative.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink2)
                    .lineSpacing(3)
                    .frame(maxWidth: 650, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid")
                    .font(.system(size: 11, weight: .semibold))
                Text(L10n.generative.realtimeMetal)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
            }
            .foregroundStyle(Color.muted)
            .padding(.horizontal, 13)
            .frame(height: 31)
            .background(Capsule().fill(Color.paper2.opacity(0.78)))
            .overlay(Capsule().strokeBorder(Color.hair.opacity(0.9), lineWidth: 1))
        }
    }
}

private struct GenerativePresetCard: View {
    let preset: GenerativePreset
    let action: () -> Void

    @State private var hovering = false
    @State private var controller = GenerativeWallpaperController.shared

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    GenerativeWallpaperPreview(preset: preset, framesPerSecond: 20)
                        .aspectRatio(16.0 / 9.6, contentMode: .fit)
                        .scaleEffect(hovering ? 1.035 : 1.0)
                        .animation(.easeOut(duration: 0.7), value: hovering)

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: .black.opacity(0.72), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(preset.accent)
                                .frame(width: 6, height: 6)
                                .shadow(color: preset.accent.opacity(0.75), radius: 5)
                            Text(L10n.generative.livePreview)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1.0)
                        }
                        .foregroundStyle(Color.white.opacity(0.88))
                        Spacer(minLength: 0)
                        if controller.isActive(preset) {
                            Text(L10n.generative.active)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1.0)
                                .foregroundStyle(Color.black.opacity(0.78))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(preset.accent))
                        }
                    }
                    .padding(14)
                }
                .clipped()

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(preset.title)
                            .font(.system(size: 27, weight: .regular, design: .serif))
                            .tracking(-0.4)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(hovering ? preset.accent : Color.muted)
                            .offset(x: hovering ? 2 : 0, y: hovering ? -2 : 0)
                    }
                    Text(preset.subtitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.ink2)
                        .padding(.top, 7)
                    HStack(spacing: 8) {
                        Text(preset.atmosphere)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .tracking(0.35)
                            .foregroundStyle(Color.muted)
                        Spacer(minLength: 0)
                        Image(systemName: "display")
                            .font(.system(size: 10, weight: .medium))
                        Text(L10n.generative.requiresApp)
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(Color.muted)
                    .padding(.top, 18)
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
                .background(Color.paper.opacity(0.94))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(hovering ? preset.accent.opacity(0.38) : Color.hair.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(hovering ? 0.22 : 0.13), radius: hovering ? 20 : 11, y: hovering ? 10 : 6)
            .scaleEffect(hovering ? 1.012 : 1)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .pointerCursor()
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: hovering)
    }
}

struct GenerativeDetailPage: View {
    let preset: GenerativePreset
    let isWindowFullScreen: Bool
    let onClose: () -> Void
    let onSelect: (GenerativePreset) -> Void

    @State private var controller = GenerativeWallpaperController.shared
    @State private var settings = GenerativeWallpaperSettings.standard
    @State private var paused = false
    @State private var showingFullscreen = false
    @State private var showingDisplayPicker = false
    @State private var selectedTargetID = WallpaperDisplayTarget.allID
    @State private var applying = false
    @State private var statusMessage: String?

    private var presetIndex: Int {
        GenerativePreset.allCases.firstIndex(of: preset) ?? 0
    }

    private var previousPreset: GenerativePreset {
        let all = GenerativePreset.allCases
        return all[(presetIndex - 1 + all.count) % all.count]
    }

    private var nextPreset: GenerativePreset {
        let all = GenerativePreset.allCases
        return all[(presetIndex + 1) % all.count]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                detailBackground
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        topBar
                        detailLayout(for: proxy.size)
                    }
                    .padding(.horizontal, proxy.size.width < 760 ? 18 : 30)
                    .padding(.top, 22)
                    .padding(.bottom, 52)
                    .frame(maxWidth: 1420)
                    .frame(maxWidth: .infinity)
                }

                if showingFullscreen {
                    fullscreenPreview
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .animation(.easeOut(duration: 0.2), value: showingFullscreen)
        .onChange(of: preset) { _, _ in
            settings = .standard
            paused = false
            statusMessage = nil
            showingDisplayPicker = false
        }
    }

    private var detailBackground: some View {
        ZStack {
            Color.paper
            RadialGradient(
                colors: [preset.accent.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 720
            )
            RadialGradient(
                colors: [preset.palette[1].opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 680
            )
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassSurface(Circle(), lighting: 0.75)
            .help(L10n.detail.fullscreenClose)
            .pointerCursor()

            VStack(alignment: .leading, spacing: 2) {
                Kicker(text: L10n.generative.kicker, tint: preset.accent)
                Text(preset.title)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ink)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                navigationButton(title: L10n.generative.previous, symbol: "chevron.left") {
                    onSelect(previousPreset)
                }
                navigationButton(title: L10n.generative.next, symbol: "chevron.right", iconAfter: true) {
                    onSelect(nextPreset)
                }
            }
        }
    }

    @ViewBuilder
    private func detailLayout(for size: CGSize) -> some View {
        if size.width < 940 {
            VStack(spacing: 20) {
                previewPanel
                informationPanel
            }
        } else {
            HStack(alignment: .top, spacing: 22) {
                previewPanel
                    .frame(maxWidth: .infinity)
                informationPanel
                    .frame(width: min(390, size.width * 0.32))
            }
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                GenerativeWallpaperPreview(
                    preset: preset,
                    settings: settings,
                    framesPerSecond: 30,
                    paused: paused || showingFullscreen
                )
                .aspectRatio(16.0 / 10.0, contentMode: .fit)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.48)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                HStack(spacing: 9) {
                    Circle()
                        .fill(preset.accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: preset.accent, radius: 6)
                    Text(paused ? L10n.generative.pause.uppercased() : L10n.generative.livePreview)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                    Spacer(minLength: 0)
                    previewButton(symbol: paused ? "play.fill" : "pause.fill", help: paused ? L10n.generative.resume : L10n.generative.pause) {
                        paused.toggle()
                    }
                    previewButton(symbol: "arrow.up.left.and.arrow.down.right", help: L10n.generative.fullscreen) {
                        showingFullscreen = true
                    }
                }
                .foregroundStyle(Color.white.opacity(0.90))
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 28, y: 14)

            HStack(spacing: 8) {
                metaChip(L10n.generative.realtimeMetal, symbol: "circle.hexagongrid")
                metaChip("30 FPS", symbol: "waveform.path")
                metaChip(L10n.generative.builtIn, symbol: "internaldrive")
                Spacer(minLength: 0)
            }
        }
    }

    private var informationPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(preset.title)
                        .font(.system(size: 36, weight: .regular, design: .serif))
                        .tracking(-0.7)
                        .foregroundStyle(Color.ink)
                    Text(preset.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 0)
                if controller.isActive(preset) {
                    Text(L10n.generative.active)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(Color.black.opacity(0.78))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(preset.accent))
                }
            }

            Text(preset.description)
                .font(.system(size: 13))
                .foregroundStyle(Color.ink2)
                .lineSpacing(4)
                .padding(.top, 18)

            Divider().overlay(Color.hair).padding(.vertical, 20)

            settingSlider(
                title: L10n.generative.intensity,
                leading: "circle.dotted",
                value: Binding(
                    get: { Double(settings.intensity) },
                    set: { settings.intensity = Float($0) }
                )
            )
            .padding(.bottom, 17)
            settingSlider(
                title: L10n.generative.speed,
                leading: "gauge.with.dots.needle.33percent",
                value: Binding(
                    get: { Double(settings.speed) },
                    set: { settings.speed = Float($0) }
                )
            )

            HStack(spacing: 7) {
                ForEach(Array(preset.palette.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 17, height: 17)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.40), lineWidth: 1))
                }
                Text(preset.atmosphere)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .tracking(0.25)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
            }
            .padding(.top, 20)

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "app.badge")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(preset.accent)
                    .padding(.top, 1)
                Text(L10n.generative.requiresAppDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.muted)
                    .lineSpacing(2)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.paper2.opacity(0.78)))
            .padding(.top, 18)

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusMessage == L10n.generative.applied ? preset.accent : Color.red)
                    .padding(.top, 12)
            }

            GlassCapsuleButton(
                title: applying ? L10n.generative.applying : L10n.generative.setAsWallpaper,
                icon: applying ? nil : "display",
                style: .accent,
                height: 42,
                fontSize: 13
            ) {
                showingDisplayPicker.toggle()
            }
            .disabled(applying)
            .padding(.top, 20)
            .popover(isPresented: $showingDisplayPicker, arrowEdge: .bottom) {
                displayPicker
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.paper.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.hair.opacity(0.86), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 18, y: 8)
    }

    private var displayPicker: some View {
        let targets = WallpaperManager.displayTargets()
        return VStack(alignment: .leading, spacing: 14) {
            Text(L10n.generative.chooseDisplay)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
            VStack(spacing: 8) {
                ForEach(targets) { target in
                    Button {
                        selectedTargetID = target.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: target.isAll ? "rectangle.on.rectangle" : "display")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(selectedTargetID == target.id ? preset.accent : Color.muted)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                                Text(target.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.muted)
                            }
                            Spacer(minLength: 8)
                            if selectedTargetID == target.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(preset.accent)
                            }
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selectedTargetID == target.id ? preset.accent.opacity(0.10) : Color.paper2)
                        )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }

            GlassCapsuleButton(
                title: applying ? L10n.generative.applying : L10n.generative.apply,
                icon: applying ? nil : "checkmark",
                style: .accent,
                height: 36,
                fontSize: 12
            ) {
                applySelectedTarget(targets)
            }
            .disabled(applying)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 330)
        .background(Color.paper)
    }

    private var fullscreenPreview: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            GenerativeWallpaperPreview(
                preset: preset,
                settings: settings,
                framesPerSecond: 30,
                paused: false,
                interactive: true
            )
            .ignoresSafeArea()

            Button {
                showingFullscreen = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .glassSurface(Circle(), tone: .dark, lighting: 0.8)
            .padding(24)
            .help(L10n.generative.closeFullscreen)
            .pointerCursor()
        }
    }

    private func navigationButton(
        title: String,
        symbol: String,
        iconAfter: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !iconAfter { Image(systemName: symbol) }
                Text(title)
                if iconAfter { Image(systemName: symbol) }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.ink2)
            .padding(.horizontal, 13)
            .frame(height: 34)
        }
        .buttonStyle(.plain)
        .glassSurface(Capsule(), lighting: 0.68, shadow: .subtle)
        .pointerCursor()
    }

    private func previewButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.90))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.11)))
        }
        .buttonStyle(.plain)
        .help(help)
        .pointerCursor()
    }

    private func metaChip(_ text: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.55)
        }
        .foregroundStyle(Color.muted)
        .padding(.horizontal, 10)
        .frame(height: 27)
        .background(Capsule().fill(Color.paper2.opacity(0.74)))
        .overlay(Capsule().strokeBorder(Color.hair.opacity(0.72), lineWidth: 1))
    }

    private func settingSlider(title: String, leading: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: leading)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(preset.accent)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink2)
                Spacer(minLength: 0)
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.muted)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1)
                .tint(preset.accent)
        }
    }

    private func applySelectedTarget(_ targets: [WallpaperDisplayTarget]) {
        guard let target = targets.first(where: { $0.id == selectedTargetID }) ?? targets.first else { return }
        applying = true
        statusMessage = nil
        do {
            try controller.apply(preset: preset, settings: settings, target: target)
            statusMessage = L10n.generative.applied
            showingDisplayPicker = false
        } catch {
            statusMessage = error.localizedDescription.isEmpty ? L10n.generative.applyFailed : error.localizedDescription
        }
        applying = false
    }
}
