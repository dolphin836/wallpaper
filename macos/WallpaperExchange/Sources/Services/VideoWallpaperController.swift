import AppKit
import AVFoundation

@MainActor
final class VideoWallpaperController {
    static let shared = VideoWallpaperController()

    private var activeVideoURL: URL?
    private var activeWallpaperID: Int?
    private var sessions: [VideoWallpaperSession] = []

    private init() {}

    func start(videoURL: URL, wallpaperID: Int) {
        activeVideoURL = videoURL
        activeWallpaperID = wallpaperID
        closeSessions()

        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        sessions = screens.map { VideoWallpaperSession(screen: $0, videoURL: videoURL) }
    }

    func restartActive() {
        guard let activeVideoURL, let activeWallpaperID else { return }
        start(videoURL: activeVideoURL, wallpaperID: activeWallpaperID)
    }

    func stop() {
        activeVideoURL = nil
        activeWallpaperID = nil
        closeSessions()
    }

    func stopIfActive(wallpaperID: Int) {
        guard activeWallpaperID == wallpaperID else { return }
        stop()
    }

    private func closeSessions() {
        sessions.forEach { $0.close() }
        sessions.removeAll()
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
