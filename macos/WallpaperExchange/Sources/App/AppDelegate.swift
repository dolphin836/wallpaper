import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        registerURLScheme()
        UpdateService.shared.checkAtLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // Brand logo, mirrored from frontend/public/logo-192.png so web + desktop share
            // one asset. Copied into Contents/Resources/ by build-app.sh — loaded via
            // Bundle.main (NOT Bundle.module: SwiftPM's resource accessor expects the bundle
            // at the .app root, which violates the macOS bundle layout and breaks codesign).
            // Rendered in full color — isTemplate=false — because the web logo is colour-loaded.
            if let url = Bundle.main.url(forResource: "StatusBarIcon", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                img.isTemplate = false
                img.size = NSSize(width: 18, height: 18)
                button.image = img
            } else {
                button.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Wallpaper Exchange")
            }
            button.action = #selector(handleStatusItemClick)
            button.target = self
            // Receive both kinds of clicks so we can show the popover on
            // primary click and the right-click menu on secondary click.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // Right-click menu: surfaces "Check for Updates…" and Quit alongside
    // the popover. Built lazily on each invocation so the version label
    // always shows the running app's current version, not a stale cache.
    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "Wallpaper Exchange \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(NSMenuItem.separator())

        let checkItem = NSMenuItem(title: "Check for Updates…", action: #selector(menuCheckForUpdates), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Wallpaper Exchange", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    @objc private func menuCheckForUpdates() {
        // UpdateService is @MainActor; AppDelegate's @objc selectors run
        // outside the actor-isolated context, so hop on explicitly.
        Task { @MainActor in
            UpdateService.shared.checkManually()
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 720, height: 700)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverContentView())
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    private func registerURLScheme() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        if url.scheme == "wallxch", url.host == "auth" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let token = components?.queryItems?.first(where: { $0.name == "token" })?.value {
                Task { @MainActor in
                    AuthService.shared.handleAuthCallback(token: token)
                }
            }
        }
    }

    @objc private func handleStatusItemClick() {
        // Right click (or Ctrl-left-click) → menu. Anything else → popover.
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isSecondary {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        // Temporarily attach the menu so AppKit pops it from the correct
        // anchor (right below the status item). Detach immediately after
        // so single left clicks keep firing the action and not the menu.
        statusItem.menu = buildStatusMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
