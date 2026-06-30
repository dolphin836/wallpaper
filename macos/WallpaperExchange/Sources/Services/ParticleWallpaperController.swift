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

    var id: String { rawValue }

    var baseCount: Int {
        switch self {
        case .starfield: 260
        case .snow: 150
        case .rain: 190
        case .fireflies: 150
        case .aurora: 260
        case .embers: 180
        case .audioTerrain: 420
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
        if activeByScreen.values.contains(where: { $0.preset == .audioTerrain }) {
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
        TimelineView(.animation(minimumInterval: 1 / config.frameRate, paused: false)) { timeline in
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
                    Color(red: 0.004, green: 0.006, blue: 0.014),
                    Color(red: 0.010, green: 0.020, blue: 0.050),
                    Color(red: 0.002, green: 0.003, blue: 0.008),
                ]),
                startPoint: CGPoint(x: size.width * 0.28, y: 0),
                endPoint: CGPoint(x: size.width * 0.72, y: size.height)
            ))
            let energy = audioEnergy(time: time)
            let center = CGPoint(x: size.width * 0.50, y: size.height * 0.52)
            drawSoftGlow(
                in: &context,
                center: center,
                radius: minSide * (0.35 + CGFloat(energy.level) * 0.18),
                color: Color(red: 0.35, green: 0.88, blue: 1.0),
                alpha: (0.10 + energy.level * 0.16) * config.brightness,
                steps: 10
            )
            drawSoftGlow(
                in: &context,
                center: CGPoint(x: size.width * 0.50, y: size.height * 0.66),
                radius: minSide * (0.45 + CGFloat(energy.beat) * 0.10),
                color: Color(red: 0.70, green: 0.18, blue: 1.0),
                alpha: (0.080 + energy.beat * 0.13) * config.brightness,
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

    private func drawAudioTerrain(_ particle: ParticleSeed, in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let energy = audioEnergy(time: time)
        let depth = particle.y
        let worldX = (particle.x - 0.5) * (1.45 + depth * 1.35)
        let centerDistance = sqrt(worldX * worldX + pow(depth - 0.28, 2))
        let pulseTravel = wrap(centerDistance * 2.2 - time * (0.20 + config.speed * 0.34), 1.0)
        let ring = pow(1.0 - abs(pulseTravel - 0.50) * 2.0, 5.0)
        let centerPeak = exp(-pow(worldX / (0.18 + energy.level * 0.10), 2) - pow((depth - 0.28) / (0.16 + energy.beat * 0.08), 2))
        let sideWave = 0.5 + 0.5 * sin((worldX * 6.0 + depth * 8.5) - time * (0.70 + config.speed * 0.75) + particle.phase)
        let fineNoise = 0.5 + 0.5 * sin(particle.phase + time * (1.1 + particle.speed * 0.4))
        let baseLift = 0.10 + energy.level * 0.86 + energy.beat * 0.38
        let terrainHeight = (
            centerPeak * (0.42 + baseLift * 0.70)
            + ring * (0.08 + energy.level * 0.28)
            + sideWave * fineNoise * 0.035
        ) * softWindow(depth, low: 0.02, high: 0.98)

        let horizon = Double(size.height) * 0.28
        let perspective = pow(depth, 1.55)
        let groundY = horizon + perspective * Double(size.height) * 0.78
        let stageWidth = Double(size.width) * (0.14 + depth * 0.74)
        let x = Double(size.width) * 0.5 + worldX * stageWidth
        let y = groundY - terrainHeight * Double(size.height) * (0.28 + depth * 0.30)
        let point = CGPoint(x: x, y: y)
        let ground = CGPoint(x: x, y: groundY)
        let heightRatio = clamp((groundY - y) / max(1, Double(size.height) * 0.22), 0, 1)
        let cyan = Color(red: 0.10 + heightRatio * 0.46, green: 0.55 + heightRatio * 0.42, blue: 1.0)
        let violet = Color(red: 0.58 + heightRatio * 0.28, green: 0.18 + heightRatio * 0.24, blue: 1.0)
        let color = particle.hue > 0.48 ? violet : cyan
        let alpha = clamp(
            (0.050 + heightRatio * 0.42 + energy.level * 0.15) * config.brightness * (0.55 + depth * 0.70),
            0,
            0.82
        )
        let radius = CGFloat((0.55 + particle.radius * 1.50) * (0.45 + depth * 1.10) * (1.0 + heightRatio * 0.85))

        if heightRatio > 0.10 || particle.radius > 0.82 {
            drawTrail(
                in: &context,
                from: ground,
                to: point,
                color: color,
                alpha: alpha * (0.20 + heightRatio * 0.30),
                lineWidth: max(0.35, radius * 0.28)
            )
        }
        if heightRatio > 0.42 || centerPeak > 0.64 {
            drawSoftGlow(
                in: &context,
                center: point,
                radius: radius * (4.0 + CGFloat(heightRatio) * 8.0),
                color: color,
                alpha: alpha * 0.18,
                steps: 5
            )
        }
        drawDot(in: &context, center: point, radius: radius, color: color, alpha: alpha)
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
        let count = max(1, steps)
        for step in stride(from: count, through: 1, by: -1) {
            let scale = CGFloat(step) / CGFloat(count)
            let currentRadius = radius * scale
            let opacity = alpha * pow(1.0 - Double(scale) * 0.72, 1.7)
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
