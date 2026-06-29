import AppKit
import SwiftUI

enum ParticleWallpaperPreset: String, CaseIterable, Identifiable {
    case starfield
    case snow
    case rain
    case fireflies
    case aurora
    case embers

    var id: String { rawValue }

    var baseCount: Int {
        switch self {
        case .starfield: 180
        case .snow: 130
        case .rain: 170
        case .fireflies: 90
        case .aurora: 70
        case .embers: 120
        }
    }

    var symbol: String {
        switch self {
        case .starfield: "sparkles"
        case .snow: "snowflake"
        case .rain: "cloud.rain"
        case .fireflies: "lightbulb"
        case .aurora: "waveform.path.ecg"
        case .embers: "flame"
        }
    }
}

struct ParticleWallpaperConfig: Equatable {
    var density: Double
    var speed: Double
    var brightness: Double
    var frameRate: Double

    static let `default` = ParticleWallpaperConfig(
        density: 0.52,
        speed: 0.50,
        brightness: 0.62,
        frameRate: 30
    )

    var clamped: ParticleWallpaperConfig {
        ParticleWallpaperConfig(
            density: min(max(density, 0.1), 1.0),
            speed: min(max(speed, 0.1), 1.0),
            brightness: min(max(brightness, 0.15), 1.0),
            frameRate: min(max(frameRate, 20), 60)
        )
    }
}

@MainActor
@Observable
final class ParticleWallpaperController {
    static let shared = ParticleWallpaperController()

    static let activeDefaultsKey = "particleWallpaper.active"
    static let presetDefaultsKey = "particleWallpaper.preset"
    static let densityDefaultsKey = "particleWallpaper.density"
    static let speedDefaultsKey = "particleWallpaper.speed"
    static let brightnessDefaultsKey = "particleWallpaper.brightness"
    static let targetDefaultsKey = "particleWallpaper.target"

    private struct ActiveParticle {
        let preset: ParticleWallpaperPreset
        let config: ParticleWallpaperConfig
        let targetID: String
    }

    private(set) var isRunning = false
    private(set) var activePreset: ParticleWallpaperPreset?

    private var activeByScreen: [String: ActiveParticle] = [:]
    private var sessionsByScreen: [String: ParticleWallpaperSession] = [:]
    private var screenObserver: NSObjectProtocol?

    private init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restartActive()
            }
        }
    }

    func restoreIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.activeDefaultsKey) else { return }
        let presetRaw = UserDefaults.standard.string(forKey: Self.presetDefaultsKey) ?? ParticleWallpaperPreset.starfield.rawValue
        let preset = ParticleWallpaperPreset(rawValue: presetRaw) ?? .starfield
        let savedDensity = UserDefaults.standard.double(forKey: Self.densityDefaultsKey)
        let savedSpeed = UserDefaults.standard.double(forKey: Self.speedDefaultsKey)
        let savedBrightness = UserDefaults.standard.double(forKey: Self.brightnessDefaultsKey)
        let config = ParticleWallpaperConfig(
            density: savedDensity > 0 ? savedDensity : ParticleWallpaperConfig.default.density,
            speed: savedSpeed > 0 ? savedSpeed : ParticleWallpaperConfig.default.speed,
            brightness: savedBrightness > 0 ? savedBrightness : ParticleWallpaperConfig.default.brightness,
            frameRate: ParticleWallpaperConfig.default.frameRate
        )
        let targetID = UserDefaults.standard.string(forKey: Self.targetDefaultsKey) ?? WallpaperDisplayTarget.allID
        let target = Self.displayTargets().first { $0.id == targetID } ?? Self.displayTargets().first
        guard let target else { return }
        start(preset: preset, config: config, target: target)
    }

    func start(preset: ParticleWallpaperPreset, config rawConfig: ParticleWallpaperConfig, target: WallpaperDisplayTarget) {
        let config = rawConfig.clamped
        let targetScreens = screens(for: target)
        let targetKeys = Set(targetScreens.compactMap(Self.screenKey))
        if coversAllConnectedScreens(targetKeys) {
            stopScreens(excluding: targetKeys)
        }

        VideoWallpaperController.shared.stop(screens: targetScreens)

        for screen in targetScreens {
            guard let key = Self.screenKey(screen) else { continue }
            sessionsByScreen[key]?.close()
            sessionsByScreen[key] = ParticleWallpaperSession(
                screen: screen,
                screenKey: key,
                preset: preset,
                config: config
            )
            activeByScreen[key] = ActiveParticle(preset: preset, config: config, targetID: target.id)
        }

        persistActive(preset: preset, config: config, targetID: target.id)
        updateState()
    }

    func restartActive() {
        closeSessions()
        let screens = Self.connectedScreens()
        let allActive = activeByScreen.values.first?.targetID == WallpaperDisplayTarget.allID
        if allActive, let active = activeByScreen.values.first {
            activeByScreen.removeAll()
            for screen in screens {
                guard let key = Self.screenKey(screen) else { continue }
                activeByScreen[key] = active
                sessionsByScreen[key] = ParticleWallpaperSession(
                    screen: screen,
                    screenKey: key,
                    preset: active.preset,
                    config: active.config
                )
            }
        } else {
            for screen in screens {
                guard let key = Self.screenKey(screen), let active = activeByScreen[key] else { continue }
                sessionsByScreen[key] = ParticleWallpaperSession(
                    screen: screen,
                    screenKey: key,
                    preset: active.preset,
                    config: active.config
                )
            }
        }
        updateState()
    }

    func stop(screens requestedScreens: [NSScreen]? = nil) {
        guard let requestedScreens else {
            activeByScreen.removeAll()
            closeSessions()
            UserDefaults.standard.set(false, forKey: Self.activeDefaultsKey)
            updateState()
            return
        }

        let requestedKeys = Set(requestedScreens.compactMap(Self.screenKey))
        if coversAllConnectedScreens(requestedKeys) {
            stop()
            return
        }
        stopScreens(matching: requestedKeys)
        updateState()
    }

    private func persistActive(preset: ParticleWallpaperPreset, config: ParticleWallpaperConfig, targetID: String) {
        UserDefaults.standard.set(true, forKey: Self.activeDefaultsKey)
        UserDefaults.standard.set(preset.rawValue, forKey: Self.presetDefaultsKey)
        UserDefaults.standard.set(config.density, forKey: Self.densityDefaultsKey)
        UserDefaults.standard.set(config.speed, forKey: Self.speedDefaultsKey)
        UserDefaults.standard.set(config.brightness, forKey: Self.brightnessDefaultsKey)
        UserDefaults.standard.set(targetID, forKey: Self.targetDefaultsKey)
    }

    private func updateState() {
        isRunning = !activeByScreen.isEmpty
        activePreset = activeByScreen.values.first?.preset
        if !isRunning {
            UserDefaults.standard.set(false, forKey: Self.activeDefaultsKey)
        }
    }

    private func closeSessions() {
        sessionsByScreen.values.forEach { $0.close() }
        sessionsByScreen.removeAll()
    }

    private func screens(for target: WallpaperDisplayTarget) -> [NSScreen] {
        guard let key = target.screenKey else { return Self.connectedScreens() }
        let screens = Self.connectedScreens().filter { Self.screenKey($0) == key }
        return screens.isEmpty ? Self.connectedScreens() : screens
    }

    private func coversAllConnectedScreens(_ keys: Set<String>) -> Bool {
        let connectedKeys = Set(Self.connectedScreens().compactMap(Self.screenKey))
        return !connectedKeys.isEmpty && keys == connectedKeys
    }

    private func stopScreens(matching keys: Set<String>) {
        for key in keys {
            sessionsByScreen[key]?.close()
            sessionsByScreen.removeValue(forKey: key)
            activeByScreen.removeValue(forKey: key)
        }
    }

    private func stopScreens(excluding keys: Set<String>) {
        let staleKeys = Set(activeByScreen.keys).subtracting(keys)
        stopScreens(matching: staleKeys)
    }

    static func displayTargets() -> [WallpaperDisplayTarget] {
        let screens = connectedScreens()
        var targets: [WallpaperDisplayTarget] = [
            WallpaperDisplayTarget(
                id: WallpaperDisplayTarget.allID,
                name: L10n.detail.wallpaperAllDisplays,
                detail: L10n.detail.wallpaperAllDisplaysDetail(screens.count),
                screenKey: nil,
                isMain: false
            )
        ]

        for screen in screens {
            guard let key = screenKey(screen) else { continue }
            let detail = screen == NSScreen.main
                ? "\(L10n.detail.wallpaperMainDisplay) · \(Int(screen.frame.width))×\(Int(screen.frame.height))"
                : "\(L10n.detail.wallpaperSecondaryDisplay) · \(Int(screen.frame.width))×\(Int(screen.frame.height))"
            targets.append(WallpaperDisplayTarget(
                id: key,
                name: screen.localizedName,
                detail: detail,
                screenKey: key,
                isMain: screen == NSScreen.main
            ))
        }
        return targets
    }

    private static func connectedScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        if !screens.isEmpty { return screens }
        if let main = NSScreen.main { return [main] }
        return []
    }

    private static func screenKey(_ screen: NSScreen) -> String? {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}

@MainActor
private final class ParticleWallpaperSession {
    private let window: DesktopParticleWindow

    init(screen: NSScreen, screenKey: String, preset: ParticleWallpaperPreset, config: ParticleWallpaperConfig) {
        window = DesktopParticleWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        let view = NSHostingView(rootView: ParticleWallpaperScene(
            preset: preset,
            config: config,
            screenKey: screenKey
        ))
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

private final class DesktopParticleWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        configure()
    }

    convenience init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool,
        screen: NSScreen
    ) {
        self.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        setFrame(screen.frame, display: true)
    }

    private func configure() {
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
    }
}

private struct ParticleWallpaperScene: View {
    let preset: ParticleWallpaperPreset
    let config: ParticleWallpaperConfig
    let particles: [ParticleSeed]

    init(preset: ParticleWallpaperPreset, config: ParticleWallpaperConfig, screenKey: String) {
        self.preset = preset
        self.config = config.clamped
        let seed = Self.stableSeed(screenKey) ^ Self.stableSeed(preset.rawValue)
        particles = ParticleSeed.makeSeeds(preset: preset, config: config.clamped, seed: seed)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / config.frameRate, paused: false)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawBackground(in: &context, size: size, time: time)
                drawParticles(in: &context, size: size, time: time)
            }
        }
        .ignoresSafeArea()
        .drawingGroup()
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let rect = Path(CGRect(origin: .zero, size: size))
        switch preset {
        case .starfield:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.015, green: 0.020, blue: 0.050),
                    Color(red: 0.035, green: 0.055, blue: 0.120),
                    Color(red: 0.005, green: 0.008, blue: 0.020),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            ))
        case .snow:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.055, green: 0.080, blue: 0.130),
                    Color(red: 0.120, green: 0.160, blue: 0.220),
                    Color(red: 0.030, green: 0.045, blue: 0.075),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width * 0.4, y: size.height)
            ))
        case .rain:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.025, green: 0.038, blue: 0.052),
                    Color(red: 0.055, green: 0.075, blue: 0.092),
                    Color(red: 0.010, green: 0.015, blue: 0.020),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width * 0.2, y: size.height)
            ))
        case .fireflies:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.010, green: 0.045, blue: 0.038),
                    Color(red: 0.018, green: 0.080, blue: 0.060),
                    Color(red: 0.003, green: 0.020, blue: 0.018),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            ))
        case .aurora:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.010, green: 0.020, blue: 0.060),
                    Color(red: 0.025, green: 0.050, blue: 0.100),
                    Color(red: 0.003, green: 0.010, blue: 0.030),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            ))
            drawAuroraBands(in: &context, size: size, time: time)
        case .embers:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.050, green: 0.018, blue: 0.010),
                    Color(red: 0.090, green: 0.036, blue: 0.020),
                    Color(red: 0.008, green: 0.004, blue: 0.004),
                ]),
                startPoint: CGPoint(x: size.width * 0.1, y: 0),
                endPoint: CGPoint(x: size.width * 0.9, y: size.height)
            ))
        }
    }

    private func drawAuroraBands(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for index in 0..<4 {
            var path = Path()
            let baseY = size.height * (0.22 + CGFloat(index) * 0.075)
            let amplitude = size.height * (0.035 + CGFloat(index) * 0.008)
            path.move(to: CGPoint(x: -60, y: baseY))
            for step in 0...16 {
                let x = CGFloat(step) / 16 * (size.width + 120) - 60
                let phase = time * (0.12 + Double(index) * 0.03) + Double(step) * 0.62
                let y = baseY + sin(phase) * amplitude + cos(phase * 0.7) * amplitude * 0.45
                path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(
                path,
                with: .color(
                    (index.isMultiple(of: 2)
                     ? Color(red: 0.18, green: 1.0, blue: 0.70)
                     : Color(red: 0.45, green: 0.40, blue: 1.0))
                        .opacity(0.12 + config.brightness * 0.20)
                ),
                lineWidth: 34 + CGFloat(index) * 12
            )
        }
    }

    private func drawParticles(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for particle in particles {
            switch preset {
            case .starfield:
                drawStar(particle, in: &context, size: size, time: time)
            case .snow:
                drawSnow(particle, in: &context, size: size, time: time)
            case .rain:
                drawRain(particle, in: &context, size: size, time: time)
            case .fireflies:
                drawFirefly(particle, in: &context, size: size, time: time)
            case .aurora:
                drawStar(particle, in: &context, size: size, time: time)
            case .embers:
                drawEmber(particle, in: &context, size: size, time: time)
            }
        }
    }

    private func drawStar(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let speed = 0.008 + config.speed * 0.018 * particle.speed
        let y = wrap(particle.y + time * speed, 1.0)
        let pulse = 0.55 + 0.45 * sin(time * (1.4 + particle.speed) + particle.phase)
        let radius = (0.8 + particle.radius * 1.9) * (preset == .aurora ? 0.75 : 1.0)
        let alpha = (0.16 + 0.52 * config.brightness) * (0.45 + 0.55 * pulse)
        let rect = CGRect(
            x: particle.x * size.width,
            y: y * size.height,
            width: radius,
            height: radius
        )
        context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
    }

    private func drawSnow(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let fall = 0.025 + config.speed * 0.065 * particle.speed
        let drift = sin(time * 0.55 + particle.phase) * 0.035 * particle.drift
        let x = wrap(particle.x + drift, 1.0) * size.width
        let y = wrap(particle.y + time * fall, 1.0) * size.height
        let radius = 1.6 + particle.radius * 3.8
        let alpha = 0.18 + config.brightness * 0.42
        context.fill(
            Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
            with: .color(Color.white.opacity(alpha))
        )
    }

    private func drawRain(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let fall = 0.18 + config.speed * 0.45 * particle.speed
        let x = wrap(particle.x + time * 0.03 * particle.drift, 1.0) * size.width
        let y = wrap(particle.y + time * fall, 1.0) * size.height
        let length = 18 + particle.radius * 44
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x - length * 0.18, y: y + length))
        context.stroke(
            path,
            with: .color(Color(red: 0.66, green: 0.78, blue: 0.92).opacity(0.15 + config.brightness * 0.32)),
            lineWidth: 0.7 + particle.radius * 1.3
        )
    }

    private func drawFirefly(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let x = wrap(particle.x + sin(time * 0.18 * config.speed + particle.phase) * 0.045 * particle.drift, 1.0) * size.width
        let y = wrap(particle.y + cos(time * 0.14 * config.speed + particle.phase) * 0.050 * particle.drift, 1.0) * size.height
        let pulse = 0.4 + 0.6 * max(0, sin(time * (0.9 + particle.speed) + particle.phase))
        let radius = 2.0 + particle.radius * 6.0
        let glow = radius * (3.2 + config.brightness * 2.8)
        context.fill(
            Path(ellipseIn: CGRect(x: x - glow * 0.5, y: y - glow * 0.5, width: glow, height: glow)),
            with: .color(Color(red: 0.85, green: 1.0, blue: 0.35).opacity(0.05 + pulse * 0.22 * config.brightness))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
            with: .color(Color(red: 1.0, green: 0.95, blue: 0.45).opacity(0.22 + pulse * 0.52 * config.brightness))
        )
    }

    private func drawEmber(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let rise = 0.030 + config.speed * 0.085 * particle.speed
        let x = wrap(particle.x + sin(time * 0.5 + particle.phase) * 0.018 * particle.drift, 1.0) * size.width
        let y = wrap(particle.y - time * rise, 1.0) * size.height
        let radius = 1.4 + particle.radius * 4.4
        let alpha = 0.18 + config.brightness * 0.48
        context.fill(
            Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
            with: .color(Color(red: 1.0, green: 0.46 + particle.hue * 0.24, blue: 0.12).opacity(alpha))
        )
    }

    private func wrap(_ value: Double, _ limit: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: limit)
        return r < 0 ? r + limit : r
    }

    private static func stableSeed(_ value: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

private struct ParticleSeed {
    let x: Double
    let y: Double
    let radius: Double
    let speed: Double
    let phase: Double
    let drift: Double
    let hue: Double

    static func makeSeeds(preset: ParticleWallpaperPreset, config: ParticleWallpaperConfig, seed: UInt64) -> [ParticleSeed] {
        let count = min(480, max(32, Int(Double(preset.baseCount) * (0.38 + config.density * 1.35))))
        var random = SeededRandom(seed: seed == 0 ? 0x7f4a7c15 : seed)
        return (0..<count).map { _ in
            ParticleSeed(
                x: random.next(),
                y: random.next(),
                radius: random.next(),
                speed: 0.45 + random.next() * 1.25,
                phase: random.next() * .pi * 2,
                drift: 0.35 + random.next() * 1.25,
                hue: random.next()
            )
        }
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> Double {
        state = state &* 2862933555777941757 &+ 3037000493
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}
