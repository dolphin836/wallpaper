import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import SwiftUI

enum ParticleWallpaperPreset: String, CaseIterable, Identifiable {
    case starfield
    case snow
    case rain
    case fireflies
    case aurora
    case embers
    case audioTerrain
    case sonicSilk
    case sonicTunnel
    case sonicOrbit
    case vinylPulse
    case wallpaperPulse

    var id: String { rawValue }

    var baseCount: Int {
        switch self {
        case .starfield: 260
        case .snow: 150
        case .rain: 190
        case .fireflies: 150
        case .aurora: 260
        case .embers: 180
        case .audioTerrain: 1180
        case .sonicSilk: 420
        case .sonicTunnel: 520
        case .sonicOrbit: 520
        case .vinylPulse: 360
        case .wallpaperPulse: 560
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
        case .audioTerrain: "waveform"
        case .sonicSilk: "waveform.path.ecg.rectangle"
        case .sonicTunnel: "tornado"
        case .sonicOrbit: "globe"
        case .vinylPulse: "record.circle"
        case .wallpaperPulse: "sparkles.rectangle.stack"
        }
    }

    var usesAudio: Bool {
        switch self {
        case .audioTerrain, .sonicSilk, .sonicTunnel, .sonicOrbit, .vinylPulse, .wallpaperPulse:
            true
        case .starfield, .snow, .rain, .fireflies, .aurora, .embers:
            false
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
private final class AudioReactiveMonitor: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    static let shared = AudioReactiveMonitor()

    @Published private(set) var level = 0.0
    @Published private(set) var beat = 0.0
    @Published private(set) var isCapturing = false

    private let outputQueue = DispatchQueue(label: "com.wallpaperexchange.audio-reactive")
    private var stream: SCStream?
    private var startTask: Task<Void, Never>?
    private var decayTask: Task<Void, Never>?
    private var lastAudioAt = Date.distantPast
    private var smoothedLevel = 0.0

    var hasRecentAudio: Bool {
        isCapturing && Date().timeIntervalSince(lastAudioAt) < 0.75 && level > 0.012
    }

    func startIfNeeded() {
        guard stream == nil, startTask == nil else { return }
        startTask = Task { [weak self] in
            await self?.startCapture()
        }
        startDecayLoop()
    }

    func stopIfNeeded() {
        startTask?.cancel()
        startTask = nil
        decayTask?.cancel()
        decayTask = nil
        let activeStream = stream
        stream = nil
        isCapturing = false
        level = 0
        beat = 0
        smoothedLevel = 0
        guard let activeStream else { return }
        Task {
            try? await activeStream.stopCapture()
        }
    }

    private func startCapture() async {
        defer { startTask = nil }
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 44_100
            configuration.channelCount = 2

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
            try await stream.startCapture()
            self.stream = stream
            isCapturing = true
        } catch {
            stream = nil
            isCapturing = false
            level = 0
            beat = 0
        }
    }

    private func startDecayLoop() {
        guard decayTask == nil else { return }
        decayTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                self?.decay()
            }
        }
    }

    private func decay() {
        if Date().timeIntervalSince(lastAudioAt) > 0.20 {
            level *= 0.90
            beat *= 0.78
            if level < 0.003 { level = 0 }
            if beat < 0.004 { beat = 0 }
        }
    }

    private func update(rawLevel: Double) {
        let shaped = min(1.0, pow(max(rawLevel, 0), 0.42) * 4.2)
        let previous = smoothedLevel
        smoothedLevel = previous * 0.72 + shaped * 0.28
        level = max(level * 0.70, smoothedLevel)
        beat = max(beat * 0.66, max(0, shaped - previous * 1.35) * 2.4)
        lastAudioAt = Date()
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let rawLevel = Self.rmsLevel(from: sampleBuffer), rawLevel > 0 else { return }
        Task { @MainActor in
            AudioReactiveMonitor.shared.update(rawLevel: rawLevel)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard AudioReactiveMonitor.shared.stream === stream else { return }
            AudioReactiveMonitor.shared.stopIfNeeded()
        }
    }

    private nonisolated static func rmsLevel(from sampleBuffer: CMSampleBuffer) -> Double? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        else {
            return nil
        }

        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer, totalLength > 0 else { return nil }

        let flags = streamDescription.mFormatFlags
        if flags & kAudioFormatFlagIsFloat != 0, streamDescription.mBitsPerChannel == 32 {
            let count = totalLength / MemoryLayout<Float>.size
            guard count > 0 else { return nil }
            let values = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
            let step = max(1, count / 1_024)
            var sum = 0.0
            var samples = 0
            var index = 0
            while index < count {
                let value = Double(values[index])
                sum += value * value
                samples += 1
                index += step
            }
            guard samples > 0 else { return nil }
            return sqrt(sum / Double(samples))
        }

        if streamDescription.mBitsPerChannel == 16 {
            let count = totalLength / MemoryLayout<Int16>.size
            guard count > 0 else { return nil }
            let values = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Int16.self)
            let step = max(1, count / 1_024)
            var sum = 0.0
            var samples = 0
            var index = 0
            while index < count {
                let value = Double(values[index]) / Double(Int16.max)
                sum += value * value
                samples += 1
                index += step
            }
            guard samples > 0 else { return nil }
            return sqrt(sum / Double(samples))
        }

        return nil
    }
}

private struct ParticleRipple: Identifiable {
    let id = UUID()
    let globalPoint: CGPoint
    let startTime: TimeInterval
}

private final class ParticleWallpaperInteractionStore: ObservableObject {
    static let shared = ParticleWallpaperInteractionStore()

    @Published private(set) var ripples: [ParticleRipple] = []

    @MainActor
    func recordClick(at globalPoint: CGPoint) {
        let now = Date.timeIntervalSinceReferenceDate
        ripples.append(ParticleRipple(globalPoint: globalPoint, startTime: now))
        ripples.removeAll { now - $0.startTime > 1.65 }
        if ripples.count > 10 {
            ripples.removeFirst(ripples.count - 10)
        }
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
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

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
        if preset == .audioTerrain {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.start(preset: preset, config: config, target: target)
            }
            return
        }
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
        updateInteractionMonitors()
        updateAudioCapture()
    }

    private func updateInteractionMonitors() {
        if isRunning {
            installClickMonitorsIfNeeded()
        } else {
            removeClickMonitors()
        }
    }

    private func installClickMonitorsIfNeeded() {
        guard globalClickMonitor == nil, localClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            Task { @MainActor in
                ParticleWallpaperInteractionStore.shared.recordClick(at: NSEvent.mouseLocation)
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            ParticleWallpaperInteractionStore.shared.recordClick(at: NSEvent.mouseLocation)
            return event
        }
    }

    private func removeClickMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func updateAudioCapture() {
        if activeByScreen.values.contains(where: { $0.preset.usesAudio }) {
            AudioReactiveMonitor.shared.startIfNeeded()
        } else {
            AudioReactiveMonitor.shared.stopIfNeeded()
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
            screenKey: screenKey,
            screenFrame: screen.frame
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
    let screenFrame: CGRect
    @ObservedObject private var audio = AudioReactiveMonitor.shared
    @ObservedObject private var interactions = ParticleWallpaperInteractionStore.shared

    init(preset: ParticleWallpaperPreset, config: ParticleWallpaperConfig, screenKey: String, screenFrame: CGRect) {
        self.preset = preset
        self.config = config.clamped
        self.screenFrame = screenFrame
        let seed = Self.stableSeed(screenKey) ^ Self.stableSeed(preset.rawValue)
        particles = ParticleSeed.makeSeeds(preset: preset, config: config.clamped, seed: seed)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: timelineInterval, paused: false)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawBackground(in: &context, size: size, time: time)
                drawParticles(in: &context, size: size, time: time)
                drawRipples(in: &context, size: size, time: time, ripples: interactions.ripples)
            }
        }
        .ignoresSafeArea()
        .drawingGroup()
    }

    private var timelineInterval: TimeInterval {
        switch preset {
        case .audioTerrain:
            max(1 / config.frameRate, 1.0 / 24.0)
        case .sonicSilk, .sonicTunnel, .sonicOrbit, .vinylPulse, .wallpaperPulse:
            max(1 / config.frameRate, 1.0 / 30.0)
        case .starfield, .snow, .rain, .fireflies, .aurora, .embers:
            1 / config.frameRate
        }
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let rect = Path(CGRect(origin: .zero, size: size))
        let minSide = max(1, min(size.width, size.height))
        switch preset {
        case .starfield:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.008, green: 0.012, blue: 0.034),
                    Color(red: 0.020, green: 0.050, blue: 0.105),
                    Color(red: 0.005, green: 0.008, blue: 0.020),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            ))
            let center = CGPoint(
                x: size.width * 0.5,
                y: size.height * (0.50 + CGFloat(sin(time * 0.28)) * 0.018)
            )
            drawSoftGlow(
                in: &context,
                center: center,
                radius: minSide * 0.58,
                color: Color(red: 0.38, green: 0.90, blue: 1.0),
                alpha: 0.10 * config.brightness,
                steps: 10
            )
            drawSoftGlow(
                in: &context,
                center: center,
                radius: minSide * 0.34,
                color: Color(red: 1.0, green: 0.82, blue: 0.45),
                alpha: 0.055 * config.brightness,
                steps: 8
            )
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
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.72, y: size.height * 0.24),
                radius: minSide * 0.38,
                color: Color(red: 0.78, green: 0.92, blue: 1.0),
                alpha: 0.055 * config.brightness,
                steps: 7
            )
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
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.34, y: size.height * 0.20),
                radius: minSide * 0.48,
                color: Color(red: 0.30, green: 0.55, blue: 0.76),
                alpha: 0.060 * config.brightness,
                steps: 8
            )
        case .fireflies:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.006, green: 0.030, blue: 0.028),
                    Color(red: 0.020, green: 0.085, blue: 0.060),
                    Color(red: 0.003, green: 0.020, blue: 0.018),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            ))
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.50, y: size.height * 0.58),
                radius: minSide * 0.52,
                color: Color(red: 0.92, green: 1.0, blue: 0.32),
                alpha: 0.075 * config.brightness,
                steps: 9
            )
        case .aurora:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.006, green: 0.014, blue: 0.045),
                    Color(red: 0.020, green: 0.050, blue: 0.100),
                    Color(red: 0.004, green: 0.010, blue: 0.028),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            ))
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.52, y: size.height * 0.38),
                radius: minSide * 0.70,
                color: Color(red: 0.40, green: 0.95, blue: 0.82),
                alpha: 0.075 * config.brightness,
                steps: 10
            )
            drawAuroraBands(in: &context, size: size, time: time)
        case .embers:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.040, green: 0.014, blue: 0.008),
                    Color(red: 0.090, green: 0.034, blue: 0.016),
                    Color(red: 0.008, green: 0.004, blue: 0.004),
                ]),
                startPoint: CGPoint(x: size.width * 0.1, y: 0),
                endPoint: CGPoint(x: size.width * 0.9, y: size.height)
            ))
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.46, y: size.height * 0.92),
                radius: minSide * 0.50,
                color: Color(red: 1.0, green: 0.38, blue: 0.10),
                alpha: 0.12 * config.brightness,
                steps: 9
            )
        case .audioTerrain:
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.002, green: 0.004, blue: 0.010),
                    Color(red: 0.008, green: 0.014, blue: 0.038),
                    Color(red: 0.001, green: 0.002, blue: 0.006),
                ]),
                startPoint: CGPoint(x: size.width * 0.28, y: 0),
                endPoint: CGPoint(x: size.width * 0.72, y: size.height)
            ))
            let energy = audioEnergy(time: time)
            let stage = audioTerrainStage(size: size)
            let stageCenter = CGPoint(x: stage.centerX, y: stage.top + stage.height * 0.56)
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: stageCenter.x, y: stageCenter.y + stage.height * 0.10),
                radius: stage.width * (0.28 + CGFloat(energy.level) * 0.050),
                color: Color(red: 0.06, green: 0.18, blue: 0.54),
                alpha: (0.115 + energy.level * 0.080) * config.brightness,
                steps: 14
            )
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: stageCenter.x, y: stageCenter.y + stage.height * 0.18),
                radius: stage.width * (0.20 + CGFloat(energy.beat) * 0.050),
                color: Color(red: 0.42, green: 0.10, blue: 0.90),
                alpha: (0.080 + energy.beat * 0.100) * config.brightness,
                steps: 12
            )
        case .sonicSilk:
            let energy = audioEnergy(time: time)
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.003, green: 0.004, blue: 0.014),
                    Color(red: 0.018, green: 0.030, blue: 0.078),
                    Color(red: 0.006, green: 0.004, blue: 0.020),
                ]),
                startPoint: CGPoint(x: size.width * 0.18, y: 0),
                endPoint: CGPoint(x: size.width * 0.86, y: size.height)
            ))
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.50, y: size.height * 0.52),
                radius: minSide * (0.46 + CGFloat(energy.level) * 0.08),
                color: Color(red: 0.18, green: 0.58, blue: 1.0),
                alpha: (0.075 + energy.level * 0.060) * config.brightness,
                steps: 10
            )
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.50, y: size.height * 0.70),
                radius: minSide * (0.32 + CGFloat(energy.beat) * 0.08),
                color: Color(red: 0.58, green: 0.18, blue: 0.92),
                alpha: (0.060 + energy.beat * 0.090) * config.brightness,
                steps: 9
            )
        case .sonicTunnel:
            let energy = audioEnergy(time: time)
            context.fill(rect, with: .radialGradient(
                Gradient(colors: [
                    Color(red: 0.030, green: 0.055, blue: 0.120),
                    Color(red: 0.006, green: 0.010, blue: 0.028),
                    Color(red: 0.001, green: 0.002, blue: 0.008),
                ]),
                center: CGPoint(x: size.width * 0.50, y: size.height * 0.50),
                startRadius: minSide * 0.04,
                endRadius: minSide * 0.70
            ))
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.50, y: size.height * 0.50),
                radius: minSide * (0.24 + CGFloat(energy.level) * 0.08),
                color: Color(red: 0.22, green: 0.78, blue: 1.0),
                alpha: (0.070 + energy.level * 0.070) * config.brightness,
                steps: 10
            )
        case .sonicOrbit:
            let energy = audioEnergy(time: time)
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.002, green: 0.006, blue: 0.018),
                    Color(red: 0.012, green: 0.030, blue: 0.072),
                    Color(red: 0.004, green: 0.002, blue: 0.016),
                ]),
                startPoint: CGPoint(x: size.width * 0.30, y: 0),
                endPoint: CGPoint(x: size.width * 0.70, y: size.height)
            ))
            let center = CGPoint(x: size.width * 0.50, y: size.height * 0.50)
            drawSoftGlow(
                in: &context,
                center: center,
                radius: minSide * (0.36 + CGFloat(energy.level) * 0.06),
                color: Color(red: 0.16, green: 0.42, blue: 0.92),
                alpha: (0.110 + energy.level * 0.080) * config.brightness,
                steps: 12
            )
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: center.x, y: center.y + minSide * 0.12),
                radius: minSide * (0.18 + CGFloat(energy.beat) * 0.05),
                color: Color(red: 0.56, green: 0.24, blue: 0.98),
                alpha: (0.070 + energy.beat * 0.080) * config.brightness,
                steps: 8
            )
        case .vinylPulse:
            let energy = audioEnergy(time: time)
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.006, green: 0.004, blue: 0.010),
                    Color(red: 0.030, green: 0.018, blue: 0.026),
                    Color(red: 0.001, green: 0.001, blue: 0.003),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            ))
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.50, y: size.height * 0.53),
                radius: minSide * (0.38 + CGFloat(energy.beat) * 0.05),
                color: Color(red: 1.0, green: 0.46, blue: 0.18),
                alpha: (0.070 + energy.beat * 0.080) * config.brightness,
                steps: 10
            )
        case .wallpaperPulse:
            let energy = audioEnergy(time: time)
            context.fill(rect, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.003, green: 0.012, blue: 0.024),
                    Color(red: 0.020, green: 0.048, blue: 0.086),
                    Color(red: 0.010, green: 0.004, blue: 0.028),
                ]),
                startPoint: CGPoint(x: 0, y: size.height * 0.1),
                endPoint: CGPoint(x: size.width, y: size.height)
            ))
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.38, y: size.height * 0.58),
                radius: minSide * (0.56 + CGFloat(energy.level) * 0.08),
                color: Color(red: 0.16, green: 0.72, blue: 0.92),
                alpha: (0.070 + energy.level * 0.070) * config.brightness,
                steps: 10
            )
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.64, y: size.height * 0.42),
                radius: minSide * (0.42 + CGFloat(energy.beat) * 0.07),
                color: Color(red: 0.78, green: 0.22, blue: 1.0),
                alpha: (0.055 + energy.beat * 0.095) * config.brightness,
                steps: 9
            )
        }
    }

    private func drawAuroraBands(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for index in 0..<5 {
            var path = Path()
            let band = CGFloat(index)
            let baseY = size.height * (0.18 + band * 0.092)
            let amplitude = size.height * (0.035 + band * 0.010)
            path.move(to: CGPoint(x: -90, y: baseY))
            for step in 0...24 {
                let progress = CGFloat(step) / 24
                let x = progress * (size.width + 180) - 90
                let phase = time * (0.070 + Double(index) * 0.018) + Double(progress) * 6.2 + Double(index) * 0.7
                let y = baseY
                    + CGFloat(sin(phase)) * amplitude
                    + CGFloat(cos(phase * 0.63 + Double(index))) * amplitude * 0.55
                path.addLine(to: CGPoint(x: x, y: y))
            }
            let color = index.isMultiple(of: 2)
                ? Color(red: 0.24, green: 1.0, blue: 0.72)
                : Color(red: 0.54, green: 0.48, blue: 1.0)
            context.stroke(
                path,
                with: .color(color.opacity(0.040 + config.brightness * 0.090)),
                lineWidth: 48 + band * 16
            )
        }
    }

    private func drawParticles(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        for particle in particles {
            switch preset {
            case .starfield:
                drawGalaxyParticle(particle, in: &context, size: size, time: time)
            case .snow:
                drawSnow(particle, in: &context, size: size, time: time)
            case .rain:
                drawRain(particle, in: &context, size: size, time: time)
            case .fireflies:
                drawFirefly(particle, in: &context, size: size, time: time)
            case .aurora:
                drawAuroraParticle(particle, in: &context, size: size, time: time)
            case .embers:
                drawEmber(particle, in: &context, size: size, time: time)
            case .audioTerrain:
                drawAudioTerrain(particle, in: &context, size: size, time: time)
            case .sonicSilk:
                drawSonicSilk(particle, in: &context, size: size, time: time)
            case .sonicTunnel:
                drawSonicTunnel(particle, in: &context, size: size, time: time)
            case .sonicOrbit:
                drawSonicOrbit(particle, in: &context, size: size, time: time)
            case .vinylPulse:
                drawVinylPulse(particle, in: &context, size: size, time: time)
            case .wallpaperPulse:
                drawWallpaperPulse(particle, in: &context, size: size, time: time)
            }
        }
    }

    private func drawGalaxyParticle(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(
            x: size.width * 0.5,
            y: size.height * (0.50 + CGFloat(sin(time * 0.28)) * 0.018)
        )
        let rx = Double(size.width * 0.40)
        let ry = Double(size.height * 0.30)
        let speed = 0.006 + config.speed * 0.020 * particle.speed
        let angle = particle.x * Double.pi * 2 + time * speed + sin(time * 0.07 + particle.phase) * 0.14
        let ring = 0.18 + particle.hue * 0.82
        let wobble = sin(time * (0.22 + particle.speed * 0.14) + particle.phase) * Double(size.height) * 0.012 * particle.drift
        let x = center.x + CGFloat(cos(angle) * rx * ring + sin(time * 0.11 + particle.phase) * 24 * particle.drift)
        let y = center.y + CGFloat(sin(angle * (1.0 + particle.radius * 0.16)) * ry * ring + wobble)
        let twinkle = pow(0.5 + 0.5 * sin(time * (0.50 + particle.speed * 0.42) + particle.phase), 4)
        let radius = CGFloat(max(0.8, (0.70 + particle.radius * 2.70) * (0.82 + twinkle * 1.18)))
        let color: Color
        if twinkle > 0.74 {
            color = Color(red: 1.0, green: 0.92, blue: 0.58)
        } else if particle.y > 0.55 {
            color = Color(red: 0.50, green: 0.98, blue: 0.86)
        } else {
            color = Color(red: 0.72, green: 0.92, blue: 1.0)
        }
        let alpha = clamp(0.040 + twinkle * 0.26 + config.brightness * 0.06, 0, 0.42)

        if particle.radius > 0.28 {
            let previousAngle = angle - speed * 22
            let previous = CGPoint(
                x: center.x + CGFloat(cos(previousAngle) * rx * ring + sin(time * 0.11 + particle.phase) * 24 * particle.drift),
                y: center.y + CGFloat(sin(previousAngle * (1.0 + particle.radius * 0.16)) * ry * ring + wobble)
            )
            drawTrail(
                in: &context,
                from: previous,
                to: CGPoint(x: x, y: y),
                color: color,
                alpha: alpha * 0.36,
                lineWidth: max(0.5, radius * 0.42)
            )
        }

        if twinkle > 0.66 || particle.radius > 0.86 {
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: x, y: y),
                radius: radius * (5.5 + CGFloat(twinkle) * 5.0),
                color: color,
                alpha: alpha * 0.30,
                steps: 5
            )
        }
        drawDot(
            in: &context,
            center: CGPoint(x: x, y: y),
            radius: radius,
            color: color,
            alpha: alpha
        )
    }

    private func drawSnow(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let fall = 0.025 + config.speed * 0.065 * particle.speed
        let drift = sin(time * 0.55 + particle.phase) * 0.035 * particle.drift
        let x = wrap(particle.x + drift, 1.0) * size.width
        let y = wrap(particle.y + time * fall, 1.0) * size.height
        let depth = 0.45 + particle.hue * 0.85
        let pulse = 0.72 + 0.28 * sin(time * (0.35 + particle.speed * 0.25) + particle.phase)
        let radius = CGFloat((1.1 + particle.radius * 3.9) * depth)
        let alpha = clamp((0.12 + config.brightness * 0.36) * pulse / depth, 0, 0.58)
        drawDot(
            in: &context,
            center: CGPoint(x: x, y: y),
            radius: radius,
            color: Color(red: 0.86, green: 0.95, blue: 1.0),
            alpha: alpha
        )
    }

    private func drawRain(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let fall = 0.18 + config.speed * 0.45 * particle.speed
        let x = wrap(particle.x + time * 0.03 * particle.drift, 1.0) * size.width
        let y = wrap(particle.y + time * fall, 1.0) * size.height
        let length = 18 + particle.radius * 44
        let color = Color(red: 0.66, green: 0.82, blue: 1.0)
        var path = Path()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x - length * 0.18, y: y + length))
        context.stroke(
            path,
            with: .color(color.opacity(0.10 + config.brightness * 0.28)),
            lineWidth: 0.7 + particle.radius * 1.3
        )
        if particle.radius > 0.74 {
            context.stroke(
                path,
                with: .color(color.opacity(0.035 + config.brightness * 0.080)),
                lineWidth: 3.0 + particle.radius * 3.0
            )
        }
    }

    private func drawFirefly(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let orbit = particle.x * Double.pi * 2 + time * (0.035 + config.speed * 0.090 * particle.speed)
        let pathRadius = Double(min(size.width, size.height)) * (0.12 + particle.y * 0.36)
        let centerX = Double(size.width) * (0.50 + sin(time * 0.10 + particle.phase) * 0.018)
        let centerY = Double(size.height) * (0.56 + cos(time * 0.08 + particle.phase) * 0.016)
        let x = centerX
            + cos(orbit) * pathRadius
            + sin(time * 0.16 + particle.phase) * 22 * particle.drift
        let y = centerY
            + sin(orbit * 0.72 + particle.phase) * pathRadius * 0.46
            + cos(time * 0.13 + particle.phase) * 20 * particle.drift
        let previous = CGPoint(
            x: centerX + cos(orbit - 0.12) * pathRadius,
            y: centerY + sin((orbit - 0.12) * 0.72 + particle.phase) * pathRadius * 0.46
        )
        let pulse = pow(0.5 + 0.5 * sin(time * (0.85 + particle.speed * 0.30) + particle.phase), 3)
        let radius = CGFloat(1.7 + particle.radius * 5.8)
        let color = particle.hue > 0.55
            ? Color(red: 0.62, green: 1.0, blue: 0.50)
            : Color(red: 1.0, green: 0.90, blue: 0.38)
        let alpha = clamp(0.12 + pulse * 0.46 * config.brightness, 0, 0.78)
        drawTrail(
            in: &context,
            from: previous,
            to: CGPoint(x: x, y: y),
            color: color,
            alpha: alpha * 0.24,
            lineWidth: max(0.7, radius * 0.42)
        )
        drawSoftGlow(
            in: &context,
            center: CGPoint(x: x, y: y),
            radius: radius * (5.0 + CGFloat(pulse) * 5.0),
            color: color,
            alpha: alpha * 0.34,
            steps: 5
        )
        drawDot(
            in: &context,
            center: CGPoint(x: x, y: y),
            radius: radius,
            color: color,
            alpha: alpha
        )
    }

    private func drawAuroraParticle(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        if particle.y > 0.82 {
            drawDepthSpark(particle, in: &context, size: size, time: time)
            return
        }

        let laneWarp = sin(particle.x * 4.1 + time * 0.035 + particle.phase) * 0.070
            + cos(particle.x * 7.2 - time * 0.020 + particle.phase) * 0.035
        let warpedLane = clamp(particle.y + laneWarp, 0, 0.82)
        let bandCoord = warpedLane / 0.82 * 5.65 + sin(particle.x * 5.0 + time * 0.045 + particle.phase) * 0.48
        let band = floor(bandCoord)
        let local = bandCoord - band
        let bandN = clamp((band + 0.5) / 5.65, 0, 1)
        let flow = wrap(
            particle.x + time * (0.0032 + bandN * 0.0039 + particle.speed * 0.0018) * config.speed + particle.hue * 0.53,
            1.0
        )
        let arc = (flow - 0.5) * Double.pi * (1.35 + bandN * 0.72 + particle.hue * 0.24)
        let centerX = Double(size.width) * 0.5
        let x = centerX
            + cos(arc * 0.72 + bandN * 0.92 + particle.phase * 0.18) * Double(size.width) * (0.10 + bandN * 0.12)
            + (flow - 0.5) * Double(size.width) * (0.38 + bandN * 0.18)
        let ribbonPhase = flow * Double.pi * 2 * (0.55 + bandN * 0.24 + particle.hue * 0.10)
            + time * (0.010 + bandN * 0.007)
            + particle.phase
        let broadWave = sin(ribbonPhase) * Double(size.height) * 0.048
        let fineWave = sin(ribbonPhase * (1.36 + particle.hue * 0.62) - time * 0.044 + particle.phase) * Double(size.height) * 0.010
        let yBase = Double(size.height) * (0.20 + bandN * 0.46)
            + sin(arc + bandN * 2.2 + particle.phase) * Double(size.height) * (0.030 + bandN * 0.018)
            + (particle.hue - 0.5) * Double(size.height) * 0.040
        let ridgeCenter = 0.43 + (particle.hue - 0.5) * 0.18
        let ridge = exp(-pow((local - ridgeCenter) / (0.25 + particle.hue * 0.04), 2))
        let softMask = smoothstep(0.020, 0.120, particle.y) * (1 - smoothstep(0.72, 0.82, particle.y))
        let pulse = 0.5 + 0.5 * sin(ribbonPhase * (1.7 + particle.hue * 0.9) - time * 0.32 + particle.phase)
        let radius = CGFloat(0.75 + particle.radius * 2.10 + ridge * 1.40)
        let alpha = clamp((0.030 + ridge * 0.18 + pulse * 0.050) * config.brightness * softMask, 0, 0.34)
        let color = Color(
            red: 0.46 + bandN * 0.26 + ridge * 0.14,
            green: 0.84 - bandN * 0.18 + ridge * 0.12,
            blue: 1.0 - bandN * 0.10
        )
        let point = CGPoint(x: x, y: yBase + broadWave + fineWave)
        if ridge > 0.42 {
            drawSoftGlow(
                in: &context,
                center: point,
                radius: radius * (6.0 + CGFloat(ridge) * 8.0),
                color: color,
                alpha: alpha * 0.22,
                steps: 5
            )
        }
        drawDot(in: &context, center: point, radius: radius, color: color, alpha: alpha)
    }

    private func drawDepthSpark(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let q = (particle.y - 0.82) / 0.18
        let drift = wrap(particle.x + time * (0.0014 + particle.speed * 0.0048) * config.speed + particle.hue * 0.63, 1.0)
        let x = (drift - 0.5) * Double(size.width) * (1.02 + particle.hue * 0.38) + Double(size.width) * 0.5
        let y = (0.12 + q * 0.74) * Double(size.height)
            + sin(time * (0.018 + particle.speed * 0.028) + particle.phase) * Double(size.height) * 0.018
        let twinkle = pow(0.5 + 0.5 * sin(time * (0.24 + particle.speed * 0.42) + particle.phase), 5)
        let dust = smoothstep(0.22, 0.98, particle.hue)
        let alpha = clamp(dust * (0.050 + twinkle * 0.20) * config.brightness * (1.0 - q * 0.06), 0, 0.28)
        let radius = CGFloat(0.65 + particle.radius * 1.70)
        drawDot(
            in: &context,
            center: CGPoint(x: x, y: y),
            radius: radius,
            color: Color(red: 0.90, green: 0.98, blue: 1.0),
            alpha: alpha
        )
    }

    private func drawSonicSilk(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let energy = audioEnergy(time: time)
        let minSide = Double(min(size.width, size.height))
        let center = CGPoint(x: size.width * 0.50, y: size.height * 0.54)
        let nx = (particle.x - 0.5) * 2.0
        let ny = (particle.y - 0.5) * 2.0
        let radial = sqrt(nx * nx + ny * ny)
        let falloff = 1.0 - smoothstep(0.72, 1.35, radial)
        guard falloff > 0.015 else { return }

        let threadPhase = nx * 5.4 + ny * 4.2 + time * (0.36 + config.speed * 0.42) + particle.phase
        let radialWave = sin(radial * 12.0 - time * (1.15 + config.speed * 1.10) + particle.phase)
        let crossWave = sin(threadPhase) * cos(ny * 6.0 - time * 0.44)
        let lift = (
            radialWave * (0.11 + energy.level * 0.26)
            + crossWave * (0.06 + energy.level * 0.18)
            + sin(threadPhase * 1.7) * energy.beat * 0.16
        ) * falloff
        let shear = sin(ny * 3.2 + time * 0.25 + particle.phase) * 28.0 * falloff
        let x = center.x + CGFloat(nx * minSide * 0.33 + lift * 50.0 + shear * 0.35)
        let y = center.y + CGFloat(ny * minSide * 0.23 - lift * 72.0 + cos(threadPhase) * 12.0 * falloff)
        let pulse = pow(0.5 + 0.5 * sin(time * (0.74 + particle.speed * 0.38) + particle.phase), 2.1)
        let radius = CGFloat(0.65 + particle.radius * 2.4 + energy.beat * 1.4) * CGFloat(0.72 + falloff * 0.60)
        let alpha = clamp((0.040 + falloff * 0.16 + pulse * 0.040 + energy.level * 0.075) * config.brightness, 0, 0.38)
        let color = Color(
            red: clamp(0.34 + particle.hue * 0.34 + energy.beat * 0.14, 0, 1),
            green: clamp(0.58 + falloff * 0.24, 0, 1),
            blue: 1.0
        )

        if particle.radius > 0.72 {
            drawTrail(
                in: &context,
                from: CGPoint(x: x - CGFloat(cos(threadPhase) * 14.0), y: y - CGFloat(sin(threadPhase) * 8.0)),
                to: CGPoint(x: x, y: y),
                color: color,
                alpha: alpha * 0.34,
                lineWidth: max(0.35, radius * 0.42)
            )
        }
        if particle.hue > 0.94 || energy.beat > 0.34 && particle.radius > 0.62 {
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: x, y: y),
                radius: radius * (4.0 + CGFloat(energy.beat) * 5.0),
                color: color,
                alpha: alpha * 0.16,
                steps: 3
            )
        }
        drawDot(in: &context, center: CGPoint(x: x, y: y), radius: radius, color: color, alpha: alpha)
    }

    private func drawSonicTunnel(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let energy = audioEnergy(time: time)
        let minSide = Double(min(size.width, size.height))
        let flow = wrap(particle.y - time * (0.030 + config.speed * 0.060) * (1.0 + energy.level * 0.45), 1.0)
        let spin = time * (0.11 + config.speed * 0.15)
        let angle = particle.x * Double.pi * 2.0 + spin + sin(flow * 10.0 + time * 0.50 + particle.phase) * 0.11
        let ripple = sin(angle * 5.0 + (flow - 0.5) * 8.0 + time * 2.2) * (0.012 + energy.level * 0.050)
        let depth = pow(flow, 1.18)
        let radius = minSide * (0.095 + depth * 0.42 + ripple)
        let center = CGPoint(
            x: size.width * 0.50 + CGFloat(sin(time * 0.10) * minSide * 0.012),
            y: size.height * 0.50 + CGFloat(cos(time * 0.08) * minSide * 0.010)
        )
        let x = center.x + CGFloat(cos(angle) * radius)
        let y = center.y + CGFloat(sin(angle) * radius * 0.58 + (flow - 0.5) * Double(size.height) * 0.10)
        guard x > -16, x < size.width + 16, y > -16, y < size.height + 16 else { return }

        let fade = smoothstep(0.04, 0.22, flow) * (1.0 - smoothstep(0.94, 1.0, flow))
        let twinkle = pow(0.5 + 0.5 * sin(time * (0.88 + particle.speed * 0.42) + particle.phase), 2.4)
        let radiusPoint = CGFloat(0.55 + particle.radius * 2.7 + depth * 1.35)
        let alpha = clamp((0.030 + depth * 0.17 + twinkle * 0.045 + energy.beat * 0.08) * fade * config.brightness, 0, 0.42)
        let color = Color(
            red: clamp(0.20 + particle.hue * 0.55 + energy.beat * 0.18, 0, 1),
            green: clamp(0.56 + depth * 0.28, 0, 1),
            blue: clamp(0.92 + twinkle * 0.08, 0, 1)
        )
        let previousAngle = angle - (0.050 + flow * 0.040)
        let previousRadius = minSide * (0.095 + max(0, depth - 0.018) * 0.42 + ripple)
        let previous = CGPoint(
            x: center.x + CGFloat(cos(previousAngle) * previousRadius),
            y: center.y + CGFloat(sin(previousAngle) * previousRadius * 0.58 + (flow - 0.5) * Double(size.height) * 0.10)
        )
        drawTrail(
            in: &context,
            from: previous,
            to: CGPoint(x: x, y: y),
            color: color,
            alpha: alpha * 0.48,
            lineWidth: max(0.35, radiusPoint * 0.42)
        )
        if particle.hue > 0.95 || energy.beat > 0.42 && particle.radius > 0.66 {
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: x, y: y),
                radius: radiusPoint * 5.2,
                color: color,
                alpha: alpha * 0.18,
                steps: 3
            )
        }
        drawDot(in: &context, center: CGPoint(x: x, y: y), radius: radiusPoint, color: color, alpha: alpha)
    }

    private func drawSonicOrbit(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let energy = audioEnergy(time: time)
        let minSide = Double(min(size.width, size.height))
        let theta = particle.x * Double.pi * 2.0 + time * (0.10 + config.speed * 0.18)
        let phi = (particle.y - 0.5) * Double.pi
        let noise = sin(theta * 3.0 + phi * 2.0 + time * 0.55 + particle.phase)
        let baseRadius = minSide * (0.22 + energy.level * 0.045 + noise * 0.012)
        let sx = cos(phi) * cos(theta)
        let sy = sin(phi)
        let sz = cos(phi) * sin(theta)
        let yaw = time * (0.13 + config.speed * 0.10)
        let rx = sx * cos(yaw) - sz * sin(yaw)
        let rz = sx * sin(yaw) + sz * cos(yaw)
        let scale = 0.72 + rz * 0.34
        guard scale > 0.42 else { return }

        let center = CGPoint(x: size.width * 0.50, y: size.height * 0.50)
        let x = center.x + CGFloat(rx * baseRadius * scale)
        let y = center.y + CGFloat(sy * baseRadius * 0.76 * scale + sin(theta + time * 0.34) * energy.beat * minSide * 0.016)
        let front = smoothstep(-0.42, 0.86, rz)
        let pulse = pow(0.5 + 0.5 * sin(time * (0.80 + particle.speed * 0.30) + particle.phase), 2.2)
        let radiusPoint = CGFloat((0.62 + particle.radius * 2.35 + front * 1.10) * (0.86 + energy.beat * 0.34))
        let alpha = clamp((0.040 + front * 0.22 + pulse * 0.035 + energy.level * 0.060) * config.brightness, 0, 0.44)
        let color = Color(
            red: clamp(0.35 + front * 0.32 + particle.hue * 0.20, 0, 1),
            green: clamp(0.48 + front * 0.24, 0, 1),
            blue: 1.0
        )
        if particle.radius > 0.78 || front > 0.78 && particle.hue > 0.72 {
            drawTrail(
                in: &context,
                from: CGPoint(x: x - CGFloat(sin(theta) * 13.0 * scale), y: y + CGFloat(cos(theta) * 7.0 * scale)),
                to: CGPoint(x: x, y: y),
                color: color,
                alpha: alpha * 0.30,
                lineWidth: max(0.3, radiusPoint * 0.34)
            )
        }
        if front > 0.78 && particle.hue > 0.90 {
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: x, y: y),
                radius: radiusPoint * 5.8,
                color: color,
                alpha: alpha * 0.16,
                steps: 3
            )
        }
        drawDot(in: &context, center: CGPoint(x: x, y: y), radius: radiusPoint, color: color, alpha: alpha)
    }

    private func drawVinylPulse(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let energy = audioEnergy(time: time)
        let minSide = Double(min(size.width, size.height))
        let center = CGPoint(x: size.width * 0.50, y: size.height * 0.53)
        let ring = 0.12 + pow(particle.y, 0.72) * 0.82
        let recordRadius = minSide * (0.30 + energy.beat * 0.020)
        let spin = time * (0.25 + config.speed * 0.30)
        let angle = particle.x * Double.pi * 2.0 + spin * (0.22 + ring * 0.90)
        let groove = pow(0.5 + 0.5 * sin(ring * 110.0 - time * 1.4 + particle.phase), 2.6)
        let wobble = sin(angle * 4.0 + time * 0.62 + particle.phase) * energy.level * 0.020
        let radius = recordRadius * (ring + wobble)
        let x = center.x + CGFloat(cos(angle) * radius)
        let y = center.y + CGFloat(sin(angle) * radius * 0.74)

        let centerLabel = smoothstep(0.26, 0.11, ring)
        let rim = smoothstep(0.78, 0.96, ring)
        let pulse = max(groove * 0.42, centerLabel * 0.72)
        let pointRadius = CGFloat(0.60 + particle.radius * 2.20 + centerLabel * 1.20 + rim * 0.70)
        let alpha = clamp((0.035 + pulse * 0.18 + rim * 0.10 + energy.beat * 0.080) * config.brightness, 0, 0.46)
        let color = centerLabel > 0.28
            ? Color(red: 1.0, green: 0.56 + centerLabel * 0.18, blue: 0.24)
            : Color(
                red: clamp(0.68 + rim * 0.28, 0, 1),
                green: clamp(0.72 + groove * 0.18, 0, 1),
                blue: clamp(0.82 + particle.hue * 0.16, 0, 1)
            )
        if particle.radius > 0.48 {
            let tangent = angle + Double.pi / 2
            drawTrail(
                in: &context,
                from: CGPoint(
                    x: x - CGFloat(cos(tangent) * (5.0 + ring * 14.0)),
                    y: y - CGFloat(sin(tangent) * (3.0 + ring * 8.0))
                ),
                to: CGPoint(x: x, y: y),
                color: color,
                alpha: alpha * (0.28 + rim * 0.20),
                lineWidth: max(0.28, pointRadius * 0.32)
            )
        }
        if centerLabel > 0.50 && particle.hue > 0.86 || rim > 0.70 && particle.hue > 0.94 {
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: x, y: y),
                radius: pointRadius * 5.4,
                color: color,
                alpha: alpha * 0.16,
                steps: 3
            )
        }
        drawDot(in: &context, center: CGPoint(x: x, y: y), radius: pointRadius, color: color, alpha: alpha)
    }

    private func drawWallpaperPulse(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        if particle.y > 0.86 {
            drawDepthSpark(particle, in: &context, size: size, time: time)
            return
        }

        let energy = audioEnergy(time: time)
        let laneWarp = sin(particle.x * 4.8 + time * 0.060 + particle.phase) * (0.055 + energy.level * 0.020)
            + cos(particle.x * 8.0 - time * 0.035 + particle.phase) * 0.030
        let warpedLane = clamp(particle.y + laneWarp, 0, 0.86)
        let bandCoord = warpedLane / 0.86 * 6.4 + sin(particle.x * 5.6 + time * 0.070 + particle.phase) * 0.42
        let band = floor(bandCoord)
        let local = bandCoord - band
        let bandN = clamp((band + 0.5) / 6.4, 0, 1)
        let flow = wrap(
            particle.x + time * (0.0042 + bandN * 0.0045 + particle.speed * 0.0022) * config.speed + particle.hue * 0.47 + energy.level * 0.020,
            1.0
        )
        let arc = (flow - 0.5) * Double.pi * (1.55 + bandN * 0.82)
        let centerX = Double(size.width) * 0.50
        let x = centerX
            + cos(arc * 0.64 + particle.phase * 0.10) * Double(size.width) * (0.12 + bandN * 0.13)
            + (flow - 0.5) * Double(size.width) * (0.30 + bandN * 0.18)
        let ribbonPhase = flow * Double.pi * 2.0 * (0.68 + bandN * 0.24)
            + time * (0.040 + config.speed * 0.030)
            + particle.phase
        let ridgeCenter = 0.42 + sin(time * 0.18 + bandN * 3.2) * 0.10
        let ridge = exp(-pow((local - ridgeCenter) / (0.23 + energy.level * 0.05), 2))
        let y = Double(size.height) * (0.16 + bandN * 0.54)
            + sin(ribbonPhase) * Double(size.height) * (0.035 + energy.level * 0.025)
            + sin(arc + bandN * 2.0) * Double(size.height) * 0.035
            + (particle.hue - 0.5) * Double(size.height) * 0.030
        let softMask = smoothstep(0.018, 0.120, particle.y) * (1.0 - smoothstep(0.78, 0.86, particle.y))
        let pulse = pow(0.5 + 0.5 * sin(ribbonPhase * 1.6 - time * 0.24 + particle.phase), 2.0)
        let radius = CGFloat(0.70 + particle.radius * 2.40 + ridge * 1.80 + energy.beat * 1.20)
        let alpha = clamp((0.032 + ridge * 0.18 + pulse * 0.046 + energy.level * 0.055) * config.brightness * softMask, 0, 0.42)
        let color = Color(
            red: clamp(0.34 + bandN * 0.36 + ridge * 0.14, 0, 1),
            green: clamp(0.72 - bandN * 0.16 + energy.beat * 0.12, 0, 1),
            blue: clamp(0.94 + ridge * 0.06, 0, 1)
        )
        let point = CGPoint(x: x, y: y)
        if ridge > 0.50 || particle.hue > 0.95 {
            drawTrail(
                in: &context,
                from: CGPoint(x: x - CGFloat(cos(arc) * 20.0), y: y - CGFloat(sin(ribbonPhase) * 10.0)),
                to: point,
                color: color,
                alpha: alpha * 0.26,
                lineWidth: max(0.35, radius * 0.36)
            )
        }
        if ridge > 0.72 && particle.hue > 0.80 {
            drawSoftGlow(
                in: &context,
                center: point,
                radius: radius * (5.0 + CGFloat(energy.beat) * 4.0),
                color: color,
                alpha: alpha * 0.15,
                steps: 3
            )
        }
        drawDot(in: &context, center: point, radius: radius, color: color, alpha: alpha)
    }

    private func audioTerrainStage(size: CGSize) -> (width: CGFloat, height: CGFloat, centerX: CGFloat, top: CGFloat, bottom: CGFloat) {
        let width = min(size.width * 0.88, size.height * 1.58)
        let height = width * 0.54
        let bottom = min(size.height * 0.94, size.height * 0.24 + height)
        return (
            width: width,
            height: bottom - size.height * 0.24,
            centerX: size.width * 0.5,
            top: size.height * 0.24,
            bottom: bottom
        )
    }

    private func drawAudioTerrain(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let stage = audioTerrainStage(size: size)
        let energy = audioEnergy(time: time)
        let halfExtent = 84.0
        let worldX = (particle.x - 0.5) * halfExtent * 2
        let worldZ = (particle.y - 0.5) * halfExtent * 2
        let centerDist = sqrt(worldX * worldX + worldZ * worldZ)
        let globalFalloff = smoothstep(halfExtent * 0.71, halfExtent * 0.36, centerDist)
        guard globalFalloff > 0.015 else { return }

        let depth = particle.y
        let u = particle.x * 2 - 1
        let perspective = pow(depth, 1.28)
        let rowWidth = Double(stage.width) * (0.32 + perspective * 0.78)
        let rowShear = (depth - 0.50) * Double(stage.width) * 0.16
        let groundY = Double(stage.top) + perspective * Double(stage.height)
        let x = Double(stage.centerX) + u * rowWidth * 0.50 + rowShear
        guard x > -12, x < Double(size.width) + 12, groundY > -12, groundY < Double(size.height) + 28 else { return }

        let subBass = clamp(max(energy.beat * 0.95, energy.level * 0.58), 0, 1)
        let bass = clamp(max(energy.level * 0.72, energy.beat * 0.48), 0, 1)
        let lowMid = clamp(energy.level * (0.42 + 0.18 * sin(time * 0.55)), 0, 1)
        let mid = clamp(energy.level * (0.30 + 0.28 * cos(time * 0.34 + particle.phase)), 0, 1)
        let highMid = clamp(max(energy.beat * 0.82, energy.level * 0.30) * (0.75 + particle.hue * 0.40), 0, 1)

        let baseNoise = 0.5 + 0.5 * sin(worldX * 0.045 + time * 0.12) * cos(worldZ * 0.040 - time * 0.08)
        let wave = 0.5 + 0.5 * sin(worldX * 0.15 + worldZ * 0.10 - time * 0.60)
        let idleElevation = (baseNoise * 0.52 + wave * 0.48) * 0.82 * globalFalloff

        let subRegion = smoothstep(halfExtent * 0.30, 0, centerDist)
        let subLift = easeAudioLift(subBass, maxHeight: 6.0) * subRegion

        let bassNoise = sin(worldX * 0.10 - time * 0.20) * cos(worldZ * 0.10 + particle.phase * 0.15)
        let bassRegion = smoothstep(halfExtent * 0.42, halfExtent * 0.06, centerDist + bassNoise * 5.0)
        let bassRnd = smoothstep(0, 1, particle.hue + config.density * 0.5)
        let bassLift = easeAudioLift(bass, maxHeight: 5.0) * bassRegion * bassRnd

        let lowMidNoise = 0.5 + 0.5 * sin(worldX * 0.052 + time * 0.18 + cos(worldZ * 0.035))
        let lowMidLift = flowAudioLift(lowMid, maxHeight: 3.0) * lowMidNoise

        let riverFlow = sin(worldX * 0.20 + worldZ * 0.20 + sin(worldX * 0.05 + worldZ * 0.05) * 2.0 - time * 2.0)
        let midLift = flowAudioLift(mid, maxHeight: 4.0) * max(0, riverFlow)

        let highMidRegion = smoothstep(halfExtent * 0.12, halfExtent * 0.54, centerDist)
        let highMidTarget = particle.hue > 0.80 || particle.radius > 0.92
        let highMidLift = highMidTarget
            ? easeAudioLift(highMid, maxHeight: 3.2) * highMidRegion * (0.35 + particle.radius * 0.65)
            : 0

        let ambientHillA = 0.5 + 0.5 * sin(worldX * 0.080 + time * 0.16) * cos(worldZ * 0.060 - time * 0.10)
        let ambientHillB = 0.5 + 0.5 * cos(worldX * 0.055 - time * 0.11 + sin(worldZ * 0.045))
        let texture = sin(worldX * 0.42 + worldZ * 0.36 + time * 0.30 + particle.phase) * 0.16
        let idleBlockWave = smoothstep(0.12, 0.88, ambientHillA * 0.48 + ambientHillB * 0.36 + texture + (particle.radius - 0.5) * 0.12)
            * 2.25
            * globalFalloff

        let pulseRadius = wrap(time * (0.24 + config.speed * 0.12), 1.12) * halfExtent * 0.92
        let pulseDelta = centerDist - pulseRadius
        let autoRipple = exp(-(pulseDelta * pulseDelta) / 48.0) * (0.10 + energy.beat * 0.80) * globalFalloff

        let screenPoint = CGPoint(x: x, y: groundY)
        let clickRipple = audioTerrainScreenRipple(at: screenPoint, size: size, time: time)
        let rippleLift = (autoRipple + clickRipple.normal * 1.25 + clickRipple.white * 1.80) * 3.0

        let energySpike = particle.hue > 0.992
            ? (1.0 - pow(1.0 - clamp(energy.beat + energy.level * 0.45, 0, 1), 1.5)) * 6.0
            : 0
        let elevation = max(
            0,
            idleElevation + idleBlockWave + (subLift + bassLift + lowMidLift + midLift + highMidLift + energySpike) * 0.88 + rippleLift
        )
        let heightScale = Double(stage.height) * (0.018 + depth * 0.018 + config.brightness * 0.010)
        let topY = groundY - min(Double(stage.height) * 0.42, elevation * heightScale)
        let heightRatio = clamp((groundY - topY) / max(1, Double(stage.height) * 0.30), 0, 1)
        let peakBlend = clamp(subLift / 6.0 * 0.72 + energySpike / 6.0 * 0.50, 0, 1)
        let rippleBlend = clamp(autoRipple + clickRipple.normal + clickRipple.white, 0, 1)
        let color = audioTerrainColumnColor(
            heightRatio: heightRatio,
            peakBlend: peakBlend,
            rippleBlend: rippleBlend,
            depth: depth,
            hue: particle.hue
        )
        let alpha = clamp(
            (0.18 + heightRatio * 0.72 + rippleBlend * 0.34) * config.brightness * (0.42 + depth * 0.78) * globalFalloff,
            0,
            1.0
        )
        let width = CGFloat(max(0.85, min(4.2, Double(stage.width) / 430.0 * (0.65 + depth * 1.45))))
        drawAudioTerrainColumn(
            in: &context,
            ground: CGPoint(x: x, y: groundY),
            top: CGPoint(x: x, y: topY),
            width: width,
            color: color,
            alpha: alpha,
            heightRatio: heightRatio
        )

        if rippleBlend > 0.74 || particle.hue > 0.993 {
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: x, y: topY),
                radius: width * (3.0 + CGFloat(heightRatio) * 4.0),
                color: color,
                alpha: alpha * 0.16,
                steps: 3
            )
        }

        if particle.hue > 0.992 && heightRatio > 0.16 {
            drawTrail(
                in: &context,
                from: CGPoint(x: x, y: topY - Double(stage.height) * (0.10 + heightRatio * 0.12)),
                to: CGPoint(x: x, y: topY),
                color: color,
                alpha: 0.050 * config.brightness * globalFalloff,
                lineWidth: max(0.25, width * 0.24)
            )
        }
    }

    private func drawAudioTerrainColumn(
        in context: inout GraphicsContext,
        ground: CGPoint,
        top: CGPoint,
        width: CGFloat,
        color: Color,
        alpha: Double,
        heightRatio: Double
    ) {
        guard alpha > 0.001 else { return }
        let bodyHeight = max(0.6, ground.y - top.y)
        let sideWidth = max(0.45, width * 0.56)
        context.fill(
            Path(CGRect(
                x: top.x - sideWidth * 0.5,
                y: top.y,
                width: sideWidth,
                height: bodyHeight
            )),
            with: .color(color.opacity(alpha * (0.14 + heightRatio * 0.24)))
        )

        let capHeight = max(0.65, width * 0.82)
        context.fill(
            Path(CGRect(
                x: top.x - width * 0.50,
                y: top.y - capHeight * 0.50,
                width: width,
                height: capHeight
            )),
            with: .color(color.opacity(alpha * (0.62 + heightRatio * 0.34)))
        )

        if heightRatio > 0.24 {
            drawTrail(
                in: &context,
                from: ground,
                to: top,
                color: color,
                alpha: alpha * (0.08 + heightRatio * 0.16),
                lineWidth: max(0.25, width * 0.18)
            )
        }
    }

    private func audioTerrainColumnColor(
        heightRatio: Double,
        peakBlend: Double,
        rippleBlend: Double,
        depth: Double,
        hue: Double
    ) -> Color {
        let glow = clamp(heightRatio * 0.92 + rippleBlend * 0.45, 0, 1)
        let coolR = mix(0.015, 0.42 + hue * 0.16, glow)
        let coolG = mix(0.025, 0.14 + depth * 0.16, glow)
        let coolB = mix(0.075, 0.92, glow)
        let purple = smoothstep(0.20, 0.95, heightRatio + rippleBlend * 0.40 + hue * 0.20)
        let peak = clamp(peakBlend * 0.72 + max(0, heightRatio - 0.72), 0, 1)
        let r = mix(mix(coolR, 0.72, purple), 1.00, peak)
        let g = mix(mix(coolG, 0.20, purple), 0.55, peak)
        let b = mix(mix(coolB, 1.00, purple), 0.08, peak)
        return Color(red: clamp(r, 0, 1), green: clamp(g, 0, 1), blue: clamp(b, 0, 1))
    }

    private func audioTerrainScreenRipple(at point: CGPoint, size: CGSize, time: TimeInterval) -> (normal: Double, white: Double) {
        var normal = 0.0
        var white = 0.0
        for ripple in interactions.ripples {
            let age = time - ripple.startTime
            guard age >= 0, age <= 1.45, screenFrame.contains(ripple.globalPoint) else { continue }
            let local = CGPoint(
                x: ripple.globalPoint.x - screenFrame.minX,
                y: screenFrame.maxY - ripple.globalPoint.y
            )
            let impact = min(size.width, size.height) * 0.26
            let radius = CGFloat(age / 1.45) * impact
            let width = max(12, impact * 0.075)
            let delta = hypot(local.x - point.x, local.y - point.y) - radius
            let wave = exp(-Double(delta * delta) / Double(width * width))
            let fade = pow(1 - age / 1.45, 1.55)
            normal += wave * fade
            if age < 0.52 {
                white += wave * fade * (1 - age / 0.52)
            }
        }
        return (clamp(normal, 0, 1), clamp(white, 0, 1))
    }

    private func easeAudioLift(_ raw: Double, maxHeight: Double) -> Double {
        let x = clamp(raw, 0, 1)
        let eased = 1 - pow(1 - x, 2.5)
        let overshoot = sin(x * Double.pi * 3.0) * exp(-x * 4.0) * 0.15
        return (eased + overshoot) * maxHeight
    }

    private func flowAudioLift(_ raw: Double, maxHeight: Double) -> Double {
        let x = clamp(raw, 0, 1)
        let eased = pow(x, 0.75)
        let breathe = sin(x * Double.pi) * 0.12
        return (eased + breathe) * maxHeight
    }

    private func mix(_ start: Double, _ end: Double, _ amount: Double) -> Double {
        start + (end - start) * clamp(amount, 0, 1)
    }

    private func drawEmber(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let rise = 0.030 + config.speed * 0.085 * particle.speed
        let progress = wrap(particle.y - time * rise, 1.0)
        let x = wrap(particle.x + sin(time * 0.42 + particle.phase) * 0.026 * particle.drift, 1.0) * size.width
        let y = progress * size.height
        let radius = CGFloat(1.1 + particle.radius * 4.8)
        let fade = softWindow(progress, low: 0.08, high: 0.95)
        let pulse = 0.68 + 0.32 * sin(time * (0.75 + particle.speed * 0.28) + particle.phase)
        let alpha = clamp((0.15 + config.brightness * 0.46) * fade * pulse, 0, 0.72)
        let color = Color(red: 1.0, green: 0.35 + particle.hue * 0.34, blue: 0.10)
        let point = CGPoint(x: x, y: y)
        let trailEnd = CGPoint(
            x: x + CGFloat(sin(time * 0.42 + particle.phase)) * 6,
            y: y + CGFloat(22 + particle.radius * 48)
        )
        drawTrail(
            in: &context,
            from: trailEnd,
            to: point,
            color: color,
            alpha: alpha * 0.26,
            lineWidth: max(0.7, radius * 0.46)
        )
        if particle.radius > 0.58 {
            drawSoftGlow(
                in: &context,
                center: point,
                radius: radius * 6.2,
                color: color,
                alpha: alpha * 0.24,
                steps: 5
            )
        }
        drawDot(
            in: &context,
            center: point,
            radius: radius,
            color: color,
            alpha: alpha
        )
    }

    private func drawRipples(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        ripples: [ParticleRipple]
    ) {
        if preset == .audioTerrain {
            drawAudioTerrainClickEffects(in: &context, size: size, time: time, ripples: ripples)
            return
        }

        for ripple in ripples {
            let age = time - ripple.startTime
            guard age >= 0, age <= 1.55 else { continue }
            guard screenFrame.contains(ripple.globalPoint) else { continue }
            let local = CGPoint(
                x: ripple.globalPoint.x - screenFrame.minX,
                y: screenFrame.maxY - ripple.globalPoint.y
            )
            let maxRadius = max(size.width, size.height) * 0.24
            let progress = clamp(age / 1.55, 0, 1)
            let radius = CGFloat(progress) * maxRadius
            let alpha = pow(1 - progress, 1.7) * (0.18 + config.brightness * 0.18)
            let color: Color = preset == .embers
                ? Color(red: 1.0, green: 0.42, blue: 0.16)
                : preset == .fireflies
                    ? Color(red: 0.90, green: 1.0, blue: 0.42)
                    : Color(red: 0.50, green: 0.88, blue: 1.0)
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: local.x - radius,
                    y: local.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(color.opacity(alpha)),
                lineWidth: max(1.0, 3.0 * (1 - CGFloat(progress)))
            )
            drawSoftGlow(
                in: &context,
                center: local,
                radius: max(1, radius * 0.72),
                color: color,
                alpha: alpha * 0.12,
                steps: 4
            )
        }
    }

    private func drawAudioTerrainClickEffects(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        ripples: [ParticleRipple]
    ) {
        let stage = audioTerrainStage(size: size)
        for ripple in ripples {
            let age = time - ripple.startTime
            guard age >= 0, age <= 1.45, screenFrame.contains(ripple.globalPoint) else { continue }
            let local = CGPoint(
                x: ripple.globalPoint.x - screenFrame.minX,
                y: screenFrame.maxY - ripple.globalPoint.y
            )
            guard local.y > stage.top - 120, local.y < stage.bottom + 120 else { continue }
            let progress = clamp(age / 1.45, 0, 1)
            let color = Color(red: 0.72, green: 0.25, blue: 1.0)

            if age < 0.50 {
                let fall = clamp(age / 0.50, 0, 1)
                let start = CGPoint(x: local.x + 180, y: local.y - 360)
                let current = CGPoint(
                    x: start.x + (local.x - start.x) * CGFloat(fall),
                    y: start.y + (local.y - start.y) * CGFloat(fall)
                )
                let tail = CGPoint(x: current.x + 48, y: current.y - 96)
                drawTrail(
                    in: &context,
                    from: tail,
                    to: current,
                    color: Color(red: 0.95, green: 0.92, blue: 1.0),
                    alpha: pow(1 - fall, 0.55) * 0.32 * config.brightness,
                    lineWidth: 1.2
                )
                drawSoftGlow(
                    in: &context,
                    center: current,
                    radius: 20 + CGFloat(fall) * 18,
                    color: color,
                    alpha: pow(1 - fall, 0.7) * 0.16 * config.brightness,
                    steps: 4
                )
            }

            let radius = CGFloat(progress) * min(size.width, size.height) * 0.26
            let alpha = pow(1 - progress, 1.55) * 0.18 * config.brightness
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: local.x - radius,
                    y: local.y - radius * 0.42,
                    width: radius * 2,
                    height: radius * 0.84
                )),
                with: .color(color.opacity(alpha)),
                lineWidth: max(0.7, 2.2 * (1 - CGFloat(progress)))
            )
            if age > 0.38, age < 0.92 {
                let burstProgress = clamp((age - 0.38) / 0.54, 0, 1)
                for index in 0..<9 {
                    let angle = Double(index) / 9.0 * Double.pi * 2 + Double(index).truncatingRemainder(dividingBy: 3) * 0.18
                    let distance = CGFloat(18 + burstProgress * 52) * (0.55 + CGFloat(index % 4) * 0.16)
                    let point = CGPoint(
                        x: local.x + cos(angle) * distance,
                        y: local.y + sin(angle) * distance * 0.46
                    )
                    drawDot(
                        in: &context,
                        center: point,
                        radius: 1.1 + CGFloat(index % 3) * 0.45,
                        color: index.isMultiple(of: 3)
                            ? Color(red: 1.0, green: 0.62, blue: 0.20)
                            : Color(red: 0.85, green: 0.75, blue: 1.0),
                        alpha: pow(1 - burstProgress, 1.2) * 0.22 * config.brightness
                    )
                }
            }
        }
    }

    private func audioEnergy(time: TimeInterval) -> (level: Double, beat: Double, live: Bool) {
        let idleLevel = 0.22 + 0.08 * sin(time * (0.42 + config.speed * 0.20))
        let idleBeat = pow(0.5 + 0.5 * sin(time * (0.72 + config.speed * 0.32)), 8) * 0.18
        if audio.hasRecentAudio {
            return (
                clamp(max(audio.level, idleLevel * 0.42), 0, 1),
                clamp(max(audio.beat, idleBeat * 0.35), 0, 1),
                true
            )
        }
        return (clamp(idleLevel, 0, 1), clamp(idleBeat, 0, 1), false)
    }

    private func drawSoftGlow(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        alpha: Double,
        steps: Int
    ) {
        guard radius > 0, alpha > 0 else { return }
        let count = max(1, steps * 3)
        for step in stride(from: count, through: 1, by: -1) {
            let scale = CGFloat(step) / CGFloat(count)
            let currentRadius = radius * scale
            let opacity = alpha * pow(1.0 - Double(scale) * 0.86, 2.2) / 2.2
            guard opacity > 0.001 else { continue }
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - currentRadius,
                    y: center.y - currentRadius,
                    width: currentRadius * 2,
                    height: currentRadius * 2
                )),
                with: .color(color.opacity(clamp(opacity, 0, 1)))
            )
        }
    }

    private func drawDot(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        alpha: Double
    ) {
        guard radius > 0, alpha > 0 else { return }
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )),
            with: .color(color.opacity(clamp(alpha, 0, 1)))
        )
    }

    private func drawTrail(
        in context: inout GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        alpha: Double,
        lineWidth: CGFloat
    ) {
        guard alpha > 0, lineWidth > 0 else { return }
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(
            path,
            with: .color(color.opacity(clamp(alpha, 0, 1))),
            lineWidth: lineWidth
        )
    }

    private func softWindow(_ value: Double, low: Double, high: Double) -> Double {
        smoothstep(0, low, value) * (1 - smoothstep(high, 1, value))
    }

    private func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        guard edge0 != edge1 else { return value < edge0 ? 0 : 1 }
        let x = clamp((value - edge0) / (edge1 - edge0), 0, 1)
        return x * x * (3 - 2 * x)
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
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
        if preset == .audioTerrain {
            let side = min(28, max(20, Int((18 + config.density * 10).rounded())))
            var random = SeededRandom(seed: seed == 0 ? 0x7f4a7c15 : seed)
            var seeds: [ParticleSeed] = []
            seeds.reserveCapacity(side * side)
            for row in 0..<side {
                for column in 0..<side {
                    let jitterX = (random.next() - 0.5) * 0.16
                    let jitterY = (random.next() - 0.5) * 0.10
                    seeds.append(ParticleSeed(
                        x: clampGridValue((Double(column) + 0.5 + jitterX) / Double(side)),
                        y: clampGridValue((Double(row) + 0.5 + jitterY) / Double(side)),
                        radius: random.next(),
                        speed: 0.45 + random.next() * 1.25,
                        phase: random.next() * .pi * 2,
                        drift: 0.35 + random.next() * 1.25,
                        hue: random.next()
                    ))
                }
            }
            return seeds.sorted {
                let leftDepth = pow($0.y, 1.28) + ($0.x - 0.5) * 0.025
                let rightDepth = pow($1.y, 1.28) + ($1.x - 0.5) * 0.025
                return leftDepth < rightDepth
            }
        }

        let cap: Int
        switch preset {
        case .audioTerrain:
            cap = 1_600
        case .sonicSilk, .vinylPulse:
            cap = 560
        case .sonicTunnel, .sonicOrbit, .wallpaperPulse:
            cap = 620
        case .starfield, .snow, .rain, .fireflies, .aurora, .embers:
            cap = 480
        }
        let count = min(cap, max(32, Int(Double(preset.baseCount) * (0.38 + config.density * 1.35))))
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

    private static func clampGridValue(_ value: Double) -> Double {
        min(max(value, 0.001), 0.999)
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
