import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var openMainWindowHandler: (() -> Void)?
    private var configuredWindowIDs = Set<ObjectIdentifier>()
    private let resourceSampler = ProcessResourceSampler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force Dock-visible regular app. LSUIElement was removed from
        // Info.plist when v2 promoted us from menu-bar helper, but the
        // ServiceManagement / launch-helper flow can still flip the
        // policy to .accessory on first run — set it explicitly so the
        // Dock icon shows up reliably.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Dock icon: a dev build runs the bare executable with no bundle
        // AppIcon.icns, so set it programmatically from the embedded
        // brand mark. The packaged .app ships the .icns (which already
        // applies), so only override when it's missing.
        if Bundle.main.url(forResource: "AppIcon", withExtension: "icns") == nil,
           let icon = BrandAsset.dockIcon {
            NSApp.applicationIconImage = icon
        }
        setupStatusItem()
        configureMainWindow()
        UpdateService.shared.checkAtLaunch()
    }

    // Make the window:
    //   • Behave as a real full-screen primary window (green-+ button
    //     toggles full-screen instead of falling back to "maximize").
    //   • Let content extend up under the traffic-light buttons —
    //     titleBar is hidden by SwiftUI's .windowStyle(.hiddenTitleBar)
    //     but we also need titlebarAppearsTransparent + the
    //     .fullSizeContentView mask so the empty strip above the
    //     content disappears entirely.
    //
    // Configuration applies on every window-becomes-main event because
    // SwiftUI may not have mounted the window during
    // applicationDidFinishLaunching (a one-shot DispatchQueue.async
    // before would silently skip applying fullScreenPrimary and the
    // green-+ button would fall back to "zoom").
    private func configureMainWindow() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            self.applyWindowChrome(window)
        }

        // Also try once now in case the main window has already been
        // mounted (e.g. relaunch with restored window state).
        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeMain {
                self.applyWindowChrome(window)
            }
        }
    }

    // Measure the native traffic-light buttons in the content view's
    // coordinate space and publish them so the SwiftUI sidebar toggle
    // can align exactly (same row, same size).

    private func applyWindowChrome(_ window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        let firstConfiguration = configuredWindowIDs.insert(windowID).inserted

        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenPrimary)

        guard firstConfiguration else { return }

        window.styleMask.insert([.resizable, .miniaturizable, .closable, .fullSizeContentView])
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window.isMovableByWindowBackground = false
        // Hide the titlebar separator (the hairline under the title
        // bar area). Without this macOS still draws a faint line
        // even when titlebarAppearsTransparent is true, which would
        // cut across our paper top bar.
        window.titlebarSeparatorStyle = .none
        // No NSToolbar: the layout paints its own paper top bar and
        // the native traffic lights float on it at their natural
        // position. A unified toolbar would add a competing strip.
        if window.toolbar != nil {
            window.toolbar = nil
        }
        clearWindowBackdrop(window)
    }

    private func clearWindowBackdrop(_ window: NSWindow) {
        guard let root = window.contentView?.superview else { return }

        func clear(_ view: NSView) {
            let className = String(describing: type(of: view))
            let isWindowChrome =
                className.contains("NSThemeFrame") ||
                className.contains("NSTitlebar") ||
                className.contains("AppKitWindowHostingView")
            let isDecorativeTitlebarLayer =
                className.contains("TitlebarBackground") ||
                className.contains("TitlebarDecoration")

            if isWindowChrome || isDecorativeTitlebarLayer {
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.clear.cgColor
            }

            if isDecorativeTitlebarLayer {
                view.isHidden = true
            }

            if let effect = view as? NSVisualEffectView, isWindowChrome {
                effect.material = .windowBackground
                effect.blendingMode = .behindWindow
                effect.state = .inactive
            }

            for subview in view.subviews {
                clear(subview)
            }
        }

        clear(root)
    }

    // v2: app stays alive when the main window is closed so the
    // status-bar quick action keeps working. Reopening from the Dock
    // (or ⇧⌘0) brings the window back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    // Bridge so the SwiftUI command menu can open the main window
    // without owning the NSStatusItem reference itself.
    func openMainWindowExternally() {
        openMainWindow()
    }

    func setOpenMainWindowHandler(_ handler: @escaping () -> Void) {
        openMainWindowHandler = handler
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // Brand logo, mirrored from frontend/public/logo-192.png so web + desktop share
            // one asset. In the menu bar it must render as a template icon so AppKit
            // adapts it to the current light/dark menu-bar appearance.
            if let img = BrandAsset.logo?.copy() as? NSImage {
                img.isTemplate = true
                img.size = NSSize(width: 17, height: 17)
                button.image = img
            } else {
                let fallback = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Wallpaper Exchange")
                fallback?.isTemplate = true
                button.image = fallback
            }
            button.imagePosition = .imageOnly
            button.action = #selector(handleStatusItemClick)
            button.target = self
            // Receive both kinds of clicks; either one opens the utility menu.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // Status menu: surfaces the main-window launcher, launch-at-login,
    // updates, and Quit. Built lazily on each invocation so the
    // version label always shows the running app's current version, not
    // a stale cache.
    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "Wallpaper Exchange \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        resourceSampler.sample()
        let resource = resourceSampler.snapshot
        let resourceTitle = NSMenuItem(
            title: "\(L10n.shell.resourceUsage) · \(L10n.shell.currentProcess)",
            action: nil,
            keyEquivalent: ""
        )
        resourceTitle.isEnabled = false
        menu.addItem(resourceTitle)

        let cpuItem = NSMenuItem(
            title: "\(L10n.shell.cpuUsage): \(formatCPU(resource.cpuPercent))",
            action: nil,
            keyEquivalent: ""
        )
        cpuItem.isEnabled = false
        menu.addItem(cpuItem)

        let memoryItem = NSMenuItem(
            title: "\(L10n.shell.memoryUsage): \(formatMemory(resource.memoryBytes))",
            action: nil,
            keyEquivalent: ""
        )
        memoryItem.isEnabled = false
        menu.addItem(memoryItem)

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: L10n.shell.openApp, action: #selector(menuOpenMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        // Launch-at-login toggle. SMAppService.mainApp reports the live
        // state directly — no UserDefaults gymnastics needed; macOS owns
        // the registration. .requiresApproval lands in System Settings →
        // Login Items waiting for the user, so we render it as "on" with
        // a hint so they don't think the toggle silently failed.
        let launchStatus = SMAppService.mainApp.status
        let launchItem = NSMenuItem(
            title: launchStatus == .requiresApproval
                ? L10n.shell.launchAtLoginNeedsApproval
                : L10n.shell.launchAtLogin,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = (launchStatus == .enabled || launchStatus == .requiresApproval) ? .on : .off
        menu.addItem(launchItem)

        let checkItem = NSMenuItem(title: L10n.shell.checkForUpdates, action: #selector(menuCheckForUpdates), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.shell.quitApp, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    private func formatCPU(_ value: Double) -> String {
        if value < 10 {
            return String(format: "%.1f%%", value)
        }
        return String(format: "%.0f%%", value)
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    @objc private func menuOpenMainWindow() {
        openMainWindow()
    }

    @objc private func menuCheckForUpdates() {
        // UpdateService is @MainActor; AppDelegate's @objc selectors run
        // outside the actor-isolated context, so hop on explicitly.
        Task { @MainActor in
            UpdateService.shared.checkManually()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        // SMAppService is the modern API (macOS 13+). It tracks the
        // registration in the system database keyed off our bundle id,
        // so no plist or LaunchAgent file to manage. Register fails if
        // the app lives somewhere the system considers transient (e.g.
        // ~/Downloads) — surface the error so the user knows to move
        // the bundle to /Applications.
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.shell.launchErrorTitle
            alert.informativeText = """
                \(error.localizedDescription)

                \(L10n.shell.launchErrorHint)
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.shell.ok)
            alert.runModal()
        }
    }

    @objc private func handleStatusItemClick() {
        showStatusMenu()
    }

    private func showStatusMenu() {
        // Temporarily attach the menu so AppKit pops it from the correct
        // anchor (right below the status item). Detach immediately after
        // so single left clicks keep firing the action and not the menu.
        statusItem.menu = buildStatusMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func openMainWindow(requestNewWindowIfNeeded: Bool = true) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            applyWindowChrome(window)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else if requestNewWindowIfNeeded, let openMainWindowHandler {
            openMainWindowHandler()
            DispatchQueue.main.async {
                self.openMainWindow(requestNewWindowIfNeeded: false)
            }
        }
    }
}
