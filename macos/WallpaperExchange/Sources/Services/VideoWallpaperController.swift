import AppKit
import AVFoundation

@MainActor
final class VideoWallpaperController {
    static let shared = VideoWallpaperController()

    private struct ActiveVideo {
        let videoURL: URL
        let wallpaperID: Int
    }

    private var activeVideosByScreen: [String: ActiveVideo] = [:]
    private var sessionsByScreen: [String: VideoWallpaperSession] = [:]

    private init() {}

    func start(videoURL: URL, wallpaperID: Int, screens requestedScreens: [NSScreen]? = nil) {
        let targetScreens = targetScreens(from: requestedScreens)
        let targetKeys = Set(targetScreens.compactMap(Self.screenKey))
        if coversAllConnectedScreens(targetKeys) {
            stopScreens(excluding: targetKeys)
        }

        for screen in targetScreens {
            guard let key = Self.screenKey(screen) else { continue }
            sessionsByScreen[key]?.close()
            sessionsByScreen[key] = VideoWallpaperSession(screen: screen, videoURL: videoURL)
            activeVideosByScreen[key] = ActiveVideo(videoURL: videoURL, wallpaperID: wallpaperID)
        }
    }

    func restartActive() {
        closeSessions()
        for screen in Self.connectedScreens() {
            guard let key = Self.screenKey(screen), let active = activeVideosByScreen[key] else { continue }
            sessionsByScreen[key] = VideoWallpaperSession(screen: screen, videoURL: active.videoURL)
        }
    }

    func stop(screens requestedScreens: [NSScreen]? = nil) {
        guard let requestedScreens else {
            activeVideosByScreen.removeAll()
            closeSessions()
            return
        }

        let requestedKeys = Set(requestedScreens.compactMap(Self.screenKey))
        if coversAllConnectedScreens(requestedKeys) {
            stop()
            return
        }
        stopScreens(matching: requestedKeys)
    }

    func stopIfActive(wallpaperID: Int) {
        let keys = activeVideosByScreen.compactMap { key, active in
            active.wallpaperID == wallpaperID ? key : nil
        }
        for key in keys {
            sessionsByScreen[key]?.close()
            sessionsByScreen.removeValue(forKey: key)
            activeVideosByScreen.removeValue(forKey: key)
        }
    }

    private func closeSessions() {
        sessionsByScreen.values.forEach { $0.close() }
        sessionsByScreen.removeAll()
    }

    private func targetScreens(from requestedScreens: [NSScreen]?) -> [NSScreen] {
        let allScreens = Self.connectedScreens()
        guard let requestedScreens, !requestedScreens.isEmpty else { return allScreens }
        let requestedKeys = Set(requestedScreens.compactMap(Self.screenKey))
        let screens = allScreens.filter { screen in
            guard let key = Self.screenKey(screen) else { return false }
            return requestedKeys.contains(key)
        }
        return screens.isEmpty ? requestedScreens : screens
    }

    private func coversAllConnectedScreens(_ keys: Set<String>) -> Bool {
        let connectedKeys = Set(Self.connectedScreens().compactMap(Self.screenKey))
        return !connectedKeys.isEmpty && keys == connectedKeys
    }

    private func stopScreens(matching keys: Set<String>) {
        for key in keys {
            sessionsByScreen[key]?.close()
            sessionsByScreen.removeValue(forKey: key)
            activeVideosByScreen.removeValue(forKey: key)
        }
    }

    private func stopScreens(excluding keys: Set<String>) {
        let staleKeys = Set(activeVideosByScreen.keys).subtracting(keys)
        stopScreens(matching: staleKeys)
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
private final class VideoWallpaperSession {
    private let window: DesktopVideoWindow
    private let player: AVPlayer
    private var loopObserver: NSObjectProtocol?

    init(screen: NSScreen, videoURL: URL) {
        let item = AVPlayerItem(url: videoURL)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        player.isMuted = true

        let view = VideoWallpaperPlayerView(frame: NSRect(origin: .zero, size: screen.frame.size), player: player)
        window = DesktopVideoWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = view
        window.orderFrontRegardless()

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        player.play()
    }

    func close() {
        player.pause()
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        window.orderOut(nil)
        window.close()
    }
}

private final class DesktopVideoWindow: NSWindow {
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

private final class VideoWallpaperPlayerView: NSView {
    private let playerLayer: AVPlayerLayer

    init(frame frameRect: NSRect, player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: frameRect)
        wantsLayer = true
        layer = playerLayer
        autoresizingMask = [.width, .height]
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
