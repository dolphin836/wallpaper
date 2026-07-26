import AppKit
import Observation

@MainActor
@Observable
final class GenerativeWallpaperController {
    static let shared = GenerativeWallpaperController()

    enum GenerativeError: LocalizedError {
        case metalUnavailable
        case displayUnavailable

        var errorDescription: String? {
            switch self {
            case .metalUnavailable: "Metal is unavailable on this Mac."
            case .displayUnavailable: "The selected display is unavailable."
            }
        }
    }

    private struct ActiveConfiguration: Codable, Equatable {
        let preset: GenerativePreset
        let settings: GenerativeWallpaperSettings
    }

    private struct PersistedState: Codable {
        let allDisplays: ActiveConfiguration?
        let displays: [String: ActiveConfiguration]
    }

    private static let stateKey = "wpe_generative_wallpaper_state_v1"

    private(set) var activePresetIDs: Set<String> = []
    private var allDisplaysConfiguration: ActiveConfiguration?
    private var configurationsByScreen: [String: ActiveConfiguration] = [:]
    private var sessionsByScreen: [String: GenerativeDesktopSession] = [:]
    private var observers: [NSObjectProtocol] = []
    private var restored = false

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartActive() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartActive() }
        })
    }

    func restoreActiveIfNeeded() {
        guard !restored else { return }
        restored = true
        guard let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        allDisplaysConfiguration = state.allDisplays
        configurationsByScreen = state.displays
        restartActive()
    }

    func isActive(_ preset: GenerativePreset) -> Bool {
        activePresetIDs.contains(preset.id)
    }

    func apply(
        preset: GenerativePreset,
        settings: GenerativeWallpaperSettings,
        target: WallpaperDisplayTarget
    ) throws {
        let screens = screens(for: target)
        guard !screens.isEmpty else { throw GenerativeError.displayUnavailable }
        guard GenerativeMetalView(
            frame: .zero,
            preset: preset,
            settings: settings,
            framesPerSecond: 1,
            interactive: false
        ) != nil else { throw GenerativeError.metalUnavailable }

        WallpaperManager.shared.clearCurrentWallpaperSelection()
        VideoWallpaperController.shared.stop(screens: screens)

        let configuration = ActiveConfiguration(preset: preset, settings: settings)
        if target.isAll {
            closeAllSessions()
            allDisplaysConfiguration = configuration
            configurationsByScreen.removeAll()
            for screen in screens {
                startSession(on: screen, configuration: configuration)
            }
        } else {
            if allDisplaysConfiguration != nil {
                closeAllSessions()
                configurationsByScreen.removeAll()
            }
            allDisplaysConfiguration = nil
            for screen in screens {
                guard let key = Self.screenKey(screen) else { continue }
                sessionsByScreen[key]?.close()
                configurationsByScreen[key] = configuration
                startSession(on: screen, configuration: configuration)
            }
        }
        publishState()
    }

    func stop(screens requestedScreens: [NSScreen]? = nil) {
        guard let requestedScreens else {
            closeAllSessions()
            allDisplaysConfiguration = nil
            configurationsByScreen.removeAll()
            publishState()
            return
        }

        let keys = Set(requestedScreens.compactMap(Self.screenKey))
        let connected = Set(Self.connectedScreens().compactMap(Self.screenKey))
        if !connected.isEmpty, keys == connected {
            stop()
            return
        }

        if let allDisplaysConfiguration {
            for screen in Self.connectedScreens() {
                guard let key = Self.screenKey(screen), !keys.contains(key) else { continue }
                configurationsByScreen[key] = allDisplaysConfiguration
            }
        }
        allDisplaysConfiguration = nil
        for key in keys {
            sessionsByScreen[key]?.close()
            sessionsByScreen.removeValue(forKey: key)
            configurationsByScreen.removeValue(forKey: key)
        }
        publishState()
    }

    func restartActive() {
        closeAllSessions()
        let screens = Self.connectedScreens()
        if let allDisplaysConfiguration {
            for screen in screens {
                startSession(on: screen, configuration: allDisplaysConfiguration)
            }
        } else {
            for screen in screens {
                guard let key = Self.screenKey(screen), let configuration = configurationsByScreen[key] else { continue }
                startSession(on: screen, configuration: configuration)
            }
        }
        updateActivePresetIDs()
    }

    private func startSession(on screen: NSScreen, configuration: ActiveConfiguration) {
        guard let key = Self.screenKey(screen),
              let session = GenerativeDesktopSession(
                screen: screen,
                preset: configuration.preset,
                settings: configuration.settings
              ) else { return }
        sessionsByScreen[key] = session
    }

    private func closeAllSessions() {
        sessionsByScreen.values.forEach { $0.close() }
        sessionsByScreen.removeAll()
    }

    private func publishState() {
        let state = PersistedState(
            allDisplays: allDisplaysConfiguration,
            displays: configurationsByScreen
        )
        if allDisplaysConfiguration == nil, configurationsByScreen.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.stateKey)
        } else if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.stateKey)
        }
        updateActivePresetIDs()
    }

    private func updateActivePresetIDs() {
        var ids = Set(configurationsByScreen.values.map(\.preset.id))
        if let allDisplaysConfiguration { ids.insert(allDisplaysConfiguration.preset.id) }
        activePresetIDs = ids
    }

    private func screens(for target: WallpaperDisplayTarget) -> [NSScreen] {
        let screens = Self.connectedScreens()
        guard let key = target.screenKey else { return screens }
        let matches = screens.filter { Self.screenKey($0) == key }
        return matches.isEmpty ? screens.filter { $0.localizedName == target.name } : matches
    }

    private static func connectedScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        if !screens.isEmpty { return screens }
        if let main = NSScreen.main { return [main] }
        return []
    }

    private static func screenKey(_ screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }
}

@MainActor
private final class GenerativeDesktopSession {
    private let window: GenerativeDesktopWindow
    private let metalView: GenerativeMetalView

    init?(
        screen: NSScreen,
        preset: GenerativePreset,
        settings: GenerativeWallpaperSettings
    ) {
        guard let metalView = GenerativeMetalView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            preset: preset,
            settings: settings,
            framesPerSecond: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 30,
            interactive: false
        ) else { return nil }
        self.metalView = metalView
        window = GenerativeDesktopWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        metalView.autoresizingMask = [.width, .height]
        window.contentView = metalView
        window.orderFrontRegardless()
    }

    func close() {
        metalView.isPaused = true
        metalView.delegate = nil
        metalView.releaseDrawables()
        window.orderOut(nil)
        window.close()
    }
}

private final class GenerativeDesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool,
        screen: NSScreen
    ) {
        self.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        setFrame(screen.frame, display: true)
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
        canHide = false
    }
}
