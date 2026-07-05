import SwiftUI
import AppKit

// ═══════════════════════════════════════════════════════════════
// GlassKit — the app's liquid-glass design system.
//
// Every piece of floating chrome (bars, buttons, chips, menus,
// panels) builds on the primitives in this file, so future styling
// passes only touch GlassKit instead of every call site.
//
// Layers (bottom → top) of a glass surface:
//   1. Material — real Liquid Glass on macOS 26 (.glassEffect with
//      lensing + adaptive legibility), ultraThinMaterial + tint
//      fallback on macOS 14–25.
//   2. GlassLightingOverlay — sculpted light: 45° specular sheen,
//      bright top rim + dark counter-rim, chromatic edge fringe.
//   3. Split shadows — tight contact + wide ambient, so surfaces
//      float at a definite height.
//
// Two tones cover every context:
//   .light — chrome over paper/mesh pages (ink text on paper tint)
//   .dark  — immersive surfaces over photos (white text, dark tint)
// ═══════════════════════════════════════════════════════════════

// ─── Tone ───────────────────────────────────────────────────────

enum GlassTone {
    case light
    case dark

    /// Tint blended into the native Liquid Glass material (macOS 26).
    var glassTint: Color? {
        switch self {
        case .light: nil
        case .dark: Color.black.opacity(0.40)
        }
    }

    /// Tint under the fallback material (macOS 14–25).
    var fallbackTint: Color {
        switch self {
        case .light: Color.paper.opacity(0.28)
        case .dark: Color.black.opacity(0.50)
        }
    }

    var fgPrimary: Color {
        switch self {
        case .light: Color.ink
        case .dark: .white
        }
    }

    var fgSecondary: Color {
        switch self {
        case .light: Color.ink2
        case .dark: Color.white.opacity(0.85)
        }
    }

    var fgMuted: Color {
        switch self {
        case .light: Color.muted
        case .dark: Color.white.opacity(0.55)
        }
    }

    var hoverFill: Color {
        switch self {
        case .light: Color.ink.opacity(0.08)
        case .dark: Color.white.opacity(0.12)
        }
    }

    var activeFill: Color {
        switch self {
        case .light: Color.accent.opacity(0.13)
        case .dark: Color.white.opacity(0.18)
        }
    }

    var divider: Color {
        switch self {
        case .light: Color.ink.opacity(0.16)
        case .dark: Color.white.opacity(0.22)
        }
    }
}

// ─── Shadow presets ─────────────────────────────────────────────

enum GlassShadow {
    /// Contact + ambient pair — floating chrome (bars, buttons, panels).
    case floating
    /// Single soft shadow — small inline elements (chips, droplets).
    case subtle
    case none
}

// ─── Surface modifier ───────────────────────────────────────────

extension View {
    /// Applies the full glass surface stack (material + lighting +
    /// shadows) in the given shape. The single source of truth for
    /// how "glass" looks in this app.
    func glassSurface<S: InsettableShape>(
        _ shape: S,
        tone: GlassTone = .light,
        lighting: Double = 0.9,
        shadow: GlassShadow = .floating
    ) -> some View {
        modifier(GlassSurface(shape: shape, tone: tone, lighting: lighting, shadow: shadow))
    }
}

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tone: GlassTone
    let lighting: Double
    let shadow: GlassShadow

    func body(content: Content) -> some View {
        materialized(content)
            .overlay(GlassLightingOverlay(shape: shape, intensity: lighting))
            .modifier(GlassShadowModifier(shadow: shadow))
    }

    @ViewBuilder
    private func materialized(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let glass: Glass = tone.glassTint.map { Glass.regular.tint($0).interactive() }
                ?? Glass.regular.interactive()
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(shape.fill(tone.fallbackTint))
        }
    }
}

private struct GlassShadowModifier: ViewModifier {
    let shadow: GlassShadow

    func body(content: Content) -> some View {
        switch shadow {
        case .floating:
            content
                .shadow(color: Color.black.opacity(0.18), radius: 3, y: 2)
                .shadow(color: Color.black.opacity(0.20), radius: 18, y: 8)
        case .subtle:
            content
                .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
        case .none:
            content
        }
    }
}

// ─── Lighting overlay ───────────────────────────────────────────

// Hand-drawn light passes layered over the glass (from Aave's
// "Building Glass for the Web"): a 45° specular sheen where light
// enters the lens, a bright top rim with a dark counter-rim
// underneath (reads as physical thickness), and a whisper of
// chromatic fringe hugging opposite edges.
struct GlassLightingOverlay<S: InsettableShape>: View {
    var shape: S
    var intensity: Double = 1.0

    var body: some View {
        ZStack {
            shape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.26 * intensity), location: 0),
                            .init(color: .white.opacity(0.05 * intensity), location: 0.34),
                            .init(color: .clear, location: 0.58),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.plusLighter)

            shape
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.60 * intensity), location: 0),
                            .init(color: .white.opacity(0.10 * intensity), location: 0.42),
                            .init(color: .clear, location: 0.78),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)

            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.15 * intensity)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )

            shape
                .strokeBorder(Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.10 * intensity), lineWidth: 0.5)
                .offset(x: -0.4, y: -0.4)
                .blendMode(.plusLighter)
            shape
                .strokeBorder(Color(red: 1.0, green: 0.62, blue: 0.45).opacity(0.10 * intensity), lineWidth: 0.5)
                .offset(x: 0.4, y: 0.4)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

extension GlassLightingOverlay where S == Capsule {
    init(intensity: Double = 1.0) {
        self.init(shape: Capsule(), intensity: intensity)
    }
}

// ─── Press feedback ─────────────────────────────────────────────

// Quick squish with a springy release, so clicks feel like pressing
// into the material rather than a flat state swap.
struct GlassBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// ─── Hover tip ──────────────────────────────────────────────────

// Small dark capsule label shown under chrome buttons on hover.
struct HoverTip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(red: 15.0 / 255, green: 12.0 / 255, blue: 8.0 / 255).opacity(0.92)))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.22), radius: 6, y: 2)
            .allowsHitTesting(false)
            .transition(.opacity)
            .zIndex(10)
    }
}

// ─── Containers ─────────────────────────────────────────────────

// Capsule glass container — nav bars, toolbars, action bars.
struct GlassPill<Content: View>: View {
    var tone: GlassTone = .light
    var lighting: Double = 0.8
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 2) {
            content
        }
        .padding(5)
        .glassSurface(Capsule(), tone: tone, lighting: lighting)
    }
}

// Hairline separator between groups inside a GlassPill.
struct GlassPillDivider: View {
    var tone: GlassTone = .light

    var body: some View {
        Capsule()
            .fill(tone.divider)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}

extension View {
    /// Rounded-rect glass panel — dropdown/info/picker surfaces.
    func glassPanel(cornerRadius: CGFloat = 18, tone: GlassTone = .dark) -> some View {
        glassSurface(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tone: tone,
            lighting: 0.65
        )
    }
}

// ─── Buttons ────────────────────────────────────────────────────

// Icon button that lives INSIDE a glass container (pill/bar) — flat
// tint highlights only, per the no-glass-on-glass rule. Hover swells
// it and shows a tip capsule underneath.
struct GlassIconButton: View {
    let icon: String
    var help: String = ""
    var tone: GlassTone = .light
    var size: CGFloat = 28
    var iconSize: CGFloat? = nil
    var active: Bool = false
    var activeColor: Color = Color.accent
    var showTip: Bool = true
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize ?? size * 0.43, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: size, height: size)
                .background {
                    if active {
                        Circle().fill(tone == .light ? activeColor.opacity(0.13) : tone.activeFill)
                    } else if hover && isEnabled {
                        Circle().fill(tone.hoverFill)
                    }
                }
                .scaleEffect(hover && isEnabled ? 1.10 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(GlassBounceButtonStyle())
        .focusEffectDisabled()
        .focusable(false)
        .overlay(alignment: .top) {
            if hover, showTip, !help.isEmpty {
                HoverTip(text: help)
                    .offset(y: size + 8)
            }
        }
        .onHover { h in
            hover = h
            if h && isEnabled { NSCursor.pointingHand.push() } else if h == false { NSCursor.pop() }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: hover)
        .animation(.easeOut(duration: 0.14), value: active)
    }

    private var iconColor: Color {
        if !isEnabled { return tone.fgMuted.opacity(0.6) }
        if active { return tone == .light ? activeColor : activeColor }
        return hover ? tone.fgPrimary : tone.fgSecondary
    }
}

// Standalone floating circular glass button — back / close / info.
// Carries its own glass surface. `prominent` renders a solid paper
// disc with an accent ring instead (primary affordance on photos).
struct GlassCircleButton: View {
    let icon: String
    var help: String = ""
    var tone: GlassTone = .light
    var size: CGFloat = 38
    var iconSize: CGFloat? = nil
    var prominent: Bool = false
    var showTip: Bool = true
    var keyEquivalent: KeyboardShortcut? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        button
            .buttonStyle(GlassBounceButtonStyle())
            .focusEffectDisabled()
            .focusable(false)
            .scaleEffect(hover && isEnabled ? 1.08 : 1)
            .overlay(alignment: .top) {
                if hover, showTip, !help.isEmpty {
                    HoverTip(text: help)
                        .offset(y: size + 8)
                }
            }
            .onHover { h in
                hover = h
                if h && isEnabled { NSCursor.pointingHand.push() } else if h == false { NSCursor.pop() }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.6), value: hover)
    }

    @ViewBuilder
    private var button: some View {
        if let keyEquivalent {
            core.keyboardShortcut(keyEquivalent)
        } else {
            core
        }
    }

    private var core: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize ?? size * 0.38, weight: .semibold))
                .foregroundStyle(fg)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .modifier(GlassCircleChrome(tone: tone, prominent: prominent))
    }

    private var fg: Color {
        if !isEnabled { return tone.fgMuted.opacity(0.6) }
        if prominent { return Color.ink }
        return hover ? tone.fgPrimary : tone.fgSecondary
    }
}

private struct GlassCircleChrome: ViewModifier {
    let tone: GlassTone
    let prominent: Bool

    func body(content: Content) -> some View {
        if prominent {
            content
                .background(Circle().fill(Color.white.opacity(0.92)))
                .overlay(Circle().strokeBorder(Color.accent.opacity(0.42), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.18), radius: 3, y: 2)
                .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
        } else {
            content.glassSurface(Circle(), tone: tone, lighting: 0.9)
        }
    }
}

// Capsule text button. Three styles:
//   .glass(tone) — translucent secondary action
//   .paper       — solid white primary action on photos
//   .accent      — brand-orange call to action
struct GlassCapsuleButton: View {
    enum Style {
        case glass(GlassTone)
        case paper
        case accent
    }

    let title: String
    var icon: String? = nil
    var style: Style = .glass(.light)
    var height: CGFloat = 34
    var fontSize: CGFloat = 12.5
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: fontSize - 1, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: fontSize, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, height * 0.5)
            .frame(height: height)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassBounceButtonStyle())
        .focusEffectDisabled()
        .focusable(false)
        .modifier(GlassCapsuleChrome(style: style, hover: hover))
        .scaleEffect(hover && isEnabled ? 1.04 : 1)
        .opacity(isEnabled ? 1 : 0.55)
        .onHover { h in
            hover = h
            if h && isEnabled { NSCursor.pointingHand.push() } else if h == false { NSCursor.pop() }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: hover)
    }

    private var fg: Color {
        switch style {
        case .glass(let tone): hover ? tone.fgPrimary : tone.fgSecondary
        case .paper: Color.ink
        case .accent: .white
        }
    }
}

private struct GlassCapsuleChrome: ViewModifier {
    let style: GlassCapsuleButton.Style
    let hover: Bool

    func body(content: Content) -> some View {
        switch style {
        case .glass(let tone):
            content.glassSurface(Capsule(), tone: tone, lighting: 0.8)
        case .paper:
            content
                .background(Capsule().fill(Color.white.opacity(0.96)))
                .overlay(GlassLightingOverlay(intensity: 0.5))
                .shadow(color: Color.black.opacity(0.16), radius: 3, y: 2)
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
        case .accent:
            content
                .background(Capsule().fill(Color.accent))
                .overlay(GlassLightingOverlay(intensity: 0.7))
                .shadow(color: Color.accent.opacity(hover ? 0.38 : 0.26), radius: hover ? 12 : 8, y: 4)
        }
    }
}

// ─── Chip ───────────────────────────────────────────────────────

// Small toggle chip (categories, filters, pagination). Lightweight
// glass at rest — deliberately no heavy shadows since chips appear
// in rows — and a solid ink capsule when active.
struct GlassChip: View {
    let label: String
    var icon: String? = nil
    var active: Bool = false
    var tone: GlassTone = .light
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12, weight: active ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(chipBackground)
            .overlay(
                Capsule().strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(GlassBounceButtonStyle())
        .focusEffectDisabled()
        .focusable(false)
        .scaleEffect(hover && isEnabled && !active ? 1.05 : 1)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { h in
            hover = h
            if h && isEnabled { NSCursor.pointingHand.push() } else if h == false { NSCursor.pop() }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: hover)
        .animation(.easeOut(duration: 0.14), value: active)
    }

    private var fg: Color {
        if active { return tone == .light ? Color.paper : Color.ink }
        return hover ? tone.fgPrimary : tone.fgSecondary
    }

    @ViewBuilder
    private var chipBackground: some View {
        if active {
            Capsule().fill(tone == .light ? Color.ink : Color.white.opacity(0.92))
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .background(Capsule().fill(tone.fallbackTint.opacity(hover ? 1 : 0.7)))
        }
    }

    private var borderColor: Color {
        if active { return .clear }
        return tone == .light
            ? Color.white.opacity(hover ? 0.55 : 0.35)
            : Color.white.opacity(hover ? 0.35 : 0.18)
    }
}

// ─── Menu chrome ────────────────────────────────────────────────

extension View {
    /// Capsule glass chrome for a dropdown trigger (Menu label /
    /// custom popover anchor).
    func glassMenuLabel(tone: GlassTone = .light, height: CGFloat = 32) -> some View {
        self
            .frame(height: height)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .background(Capsule().fill(tone.fallbackTint.opacity(0.7)))
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
    }
}

// ─── Segmented control ──────────────────────────────────────────

struct GlassSegment<ID: Hashable> {
    let id: ID
    let label: String
    var icon: String? = nil
    /// Optional trailing count/badge text (e.g. tab item counts).
    var badge: String? = nil
}

// Capsule segmented control with the liquid selection droplet — the
// same interaction as the chrome nav bar, reusable for page-level
// tabs and mode pickers.
struct GlassSegmented<ID: Hashable>: View {
    let segments: [GlassSegment<ID>]
    @Binding var selection: ID
    var tone: GlassTone = .light
    /// Compact fits inline contexts (mode pickers); regular is the
    /// chrome-bar scale.
    var compact: Bool = false

    @Namespace private var dropletNS

    var body: some View {
        GlassPill(tone: tone) {
            ForEach(segments, id: \.id) { segment in
                GlassSegmentItem(
                    segment: segment,
                    isSelected: segment.id == selection,
                    tone: tone,
                    compact: compact,
                    dropletNamespace: dropletNS,
                    action: { selection = segment.id }
                )
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.68), value: selection)
    }
}

struct GlassSegmentItem<ID: Hashable>: View {
    let segment: GlassSegment<ID>
    let isSelected: Bool
    var tone: GlassTone = .light
    var compact: Bool = false
    let dropletNamespace: Namespace.ID
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = segment.icon {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 11 : 13, weight: isSelected ? .semibold : .medium))
                }
                Text(segment.label)
                    .font(.system(size: compact ? 11.5 : 13.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize()
                if let badge = segment.badge {
                    Text(badge)
                        .font(.system(size: compact ? 9 : 10, weight: .medium, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(isSelected ? tone.fgPrimary : tone.fgMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(isSelected ? tone.hoverFill : tone.hoverFill.opacity(0.6))
                        )
                }
            }
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 12 : 17)
            .frame(height: compact ? 26 : 34)
            .background {
                if isSelected {
                    GlassSelectionDroplet(tone: tone)
                        .matchedGeometryEffect(id: "glass-segment-droplet", in: dropletNamespace)
                } else if hover {
                    Capsule().fill(tone.hoverFill)
                }
            }
            .scaleEffect(hover && !isSelected ? 1.05 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(GlassBounceButtonStyle())
        .focusEffectDisabled()
        .focusable(false)
        .onHover { h in
            hover = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.6), value: hover)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }

    private var fg: Color {
        if isSelected { return tone.fgPrimary }
        return hover ? tone.fgPrimary : tone.fgSecondary
    }
}

// The raised droplet lens that marks the selected segment — real
// Liquid Glass on macOS 26, highlight-edged capsule fallback.
struct GlassSelectionDroplet: View {
    var tone: GlassTone = .light

    var body: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(dropletTint)
                .glassEffect(.regular.interactive(), in: Capsule())
                .overlay(GlassLightingOverlay(intensity: 1.5))
                .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
        } else {
            Capsule()
                .fill(tone == .light ? Color.paper.opacity(0.92) : Color.white.opacity(0.24))
                .overlay(GlassLightingOverlay(intensity: 1.3))
                .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
        }
    }

    private var dropletTint: Color {
        tone == .light ? Color.paper.opacity(0.30) : Color.white.opacity(0.16)
    }
}
