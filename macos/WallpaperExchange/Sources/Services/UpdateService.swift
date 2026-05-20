import AppKit
import Foundation

// Self-update controller for the menu-bar app.
//
// Three entry points:
//   1. checkAtLaunch()    — quiet background check 5s after the app is
//                            ready; shows the upgrade alert at most once
//                            per discovered version (UserDefaults gate).
//   2. checkManually()    — invoked from the right-click status menu;
//                            always shows an alert ("up to date" or the
//                            full upgrade prompt).
//   3. installUpdate()    — used by the alert's Install button; downloads
//                            the .dmg, mounts it, spawns a helper that
//                            waits for this app to quit, copies the new
//                            .app over our bundle, and relaunches.
//
// The helper script is the only non-obvious bit: we can't safely replace
// our own running .app from within ourselves, so we hand the actual
// file move off to a tiny detached shell that watches our PID exit
// first. See spawnInstallHelper(...) below.
@MainActor
final class UpdateService {
    static let shared = UpdateService()
    private init() {}

    private let lastNotifiedKey = "WPE.LastNotifiedUpdateVersion"

    /// Quiet check fired 5s after launch. No UI unless there's a new
    /// version we haven't notified about before.
    func checkAtLaunch() {
        // Give the popover + status bar UI a moment to settle so the
        // alert (if we end up showing one) doesn't compete with first
        // paint for focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            Task { @MainActor in
                await self?.runCheck(manual: false)
            }
        }
    }

    /// Manual "Check for Updates…" entry — always shows an alert.
    func checkManually() {
        Task { @MainActor in
            await self.runCheck(manual: true)
        }
    }

    // MARK: - Core flow

    private func runCheck(manual: Bool) async {
        let release: MacRelease
        do {
            release = try await APIClient.shared.fetchMacRelease()
        } catch {
            if manual {
                showAlert(
                    title: "Couldn't check for updates",
                    message: "Network or server error: \(error.localizedDescription)",
                    style: .warning
                )
            }
            return
        }

        let current = currentVersionString()
        let latest = release.currentVersion

        if !isNewer(latest: latest, than: current) {
            if manual {
                showAlert(
                    title: "You're up to date",
                    message: "Wallpaper Exchange \(current) is the latest version.",
                    style: .informational
                )
            }
            return
        }

        // New version available. The launch-time check is gated by
        // UserDefaults so we don't pester someone who chose "Later"
        // yesterday. The manual menu always shows the alert.
        if !manual {
            let lastNotified = UserDefaults.standard.string(forKey: lastNotifiedKey)
            if lastNotified == latest {
                return
            }
        }
        UserDefaults.standard.set(latest, forKey: lastNotifiedKey)

        promptInstall(release: release, current: current)
    }

    private func promptInstall(release: MacRelease, current: String) {
        let entry = release.releases?.first { $0.version == release.currentVersion }
        let notes = entry?.notes?.prefix(5).joined(separator: "\n• ") ?? ""

        let alert = NSAlert()
        alert.messageText = "New version available — \(release.currentVersion)"
        alert.informativeText = """
            You're running \(current). The latest release is \(release.currentVersion).

            \(notes.isEmpty ? "" : "What's new:\n• \(notes)")
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Now")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            installUpdate(release: release)
        }
    }

    // MARK: - Install pipeline

    private func installUpdate(release: MacRelease) {
        // Spin up an indeterminate progress sheet by way of a third
        // alert. Not the prettiest but avoids pulling SwiftUI into the
        // updater path. The user will quickly see the helper take over.
        let progress = NSAlert()
        progress.messageText = "Downloading \(release.currentVersion)…"
        progress.informativeText = "The app will restart automatically when the update is ready."
        progress.alertStyle = .informational
        progress.addButton(withTitle: "Cancel")

        Task { @MainActor in
            await self.downloadAndInstall(release: release, progressAlert: progress)
        }
        progress.runModal()
    }

    private func downloadAndInstall(release: MacRelease, progressAlert: NSAlert) async {
        guard let url = URL(string: release.currentDmgURL) else {
            await dismissAndFail(alert: progressAlert, message: "Bad download URL.")
            return
        }
        let dmgPath = NSTemporaryDirectory() + "wxch-update-\(release.currentVersion).dmg"
        let dmgURL = URL(fileURLWithPath: dmgPath)

        do {
            let (downloadedTmp, _) = try await URLSession.shared.download(from: url)
            try? FileManager.default.removeItem(at: dmgURL)
            try FileManager.default.moveItem(at: downloadedTmp, to: dmgURL)
        } catch {
            await dismissAndFail(alert: progressAlert, message: "Download failed: \(error.localizedDescription)")
            return
        }

        // Mount the dmg headlessly so Finder doesn't pop up a window.
        let mountPoint: String
        do {
            mountPoint = try attachDMG(at: dmgPath)
        } catch {
            await dismissAndFail(alert: progressAlert, message: "Couldn't mount the installer: \(error.localizedDescription)")
            return
        }

        // Find the .app inside the mounted volume.
        guard let sourceAppPath = locateAppBundle(in: mountPoint) else {
            _ = try? detachDMG(mountPoint: mountPoint)
            await dismissAndFail(alert: progressAlert, message: "The installer didn't contain an app bundle.")
            return
        }

        let myBundlePath = Bundle.main.bundleURL.path

        // Hand off to a tiny shell helper — we can't safely replace our
        // own bundle while we're still running, so the helper waits for
        // our PID to die before doing the cp.
        spawnInstallHelper(
            ourPID: ProcessInfo.processInfo.processIdentifier,
            sourceApp: sourceAppPath,
            destApp: myBundlePath,
            mountPoint: mountPoint,
            dmgFile: dmgPath
        )

        // Close the progress alert and quit. The helper will mv the new
        // app into place and re-open us.
        await MainActor.run {
            NSApp.abortModal()
            NSApp.terminate(nil)
        }
    }

    private func dismissAndFail(alert: NSAlert, message: String) async {
        await MainActor.run {
            NSApp.abortModal()
            showAlert(title: "Update failed", message: message, style: .warning)
        }
    }

    // MARK: - DMG helpers

    private func attachDMG(at path: String) throws -> String {
        // hdiutil attach -nobrowse -plist writes a property list with the
        // mount point. We could parse the plist properly, but grepping
        // for /Volumes/... is sturdy enough for our single-volume DMGs.
        let proc = Process()
        proc.launchPath = "/usr/bin/hdiutil"
        proc.arguments = ["attach", "-nobrowse", "-noverify", "-noautoopen", path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "UpdateService", code: 1, userInfo: [NSLocalizedDescriptionKey: "hdiutil attach exited \(proc.terminationStatus)"])
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: data, encoding: .utf8) ?? ""
        // Last "/Volumes/..." token on the line containing it.
        for line in stdout.split(separator: "\n") {
            if let range = line.range(of: "/Volumes/") {
                return String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        throw NSError(domain: "UpdateService", code: 2, userInfo: [NSLocalizedDescriptionKey: "hdiutil didn't report a /Volumes/ mount point"])
    }

    private func detachDMG(mountPoint: String) throws {
        let proc = Process()
        proc.launchPath = "/usr/bin/hdiutil"
        proc.arguments = ["detach", "-force", mountPoint]
        try proc.run()
        proc.waitUntilExit()
    }

    private func locateAppBundle(in mountPoint: String) -> String? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: mountPoint) else {
            return nil
        }
        for name in contents where name.hasSuffix(".app") {
            return (mountPoint as NSString).appendingPathComponent(name)
        }
        return nil
    }

    private func spawnInstallHelper(ourPID: Int32, sourceApp: String, destApp: String, mountPoint: String, dmgFile: String) {
        // Helper is a self-deleting shell script. We can't keep it open
        // in the app because the app is about to quit; the trick is to
        // detach via `nohup` so the script outlives us.
        let scriptPath = NSTemporaryDirectory() + "wxch-update-helper.sh"
        // shell-escape paths just in case (spaces, etc.).
        let q = { (s: String) -> String in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let body = """
        #!/bin/bash
        # Self-deleting WallpaperExchange update helper.
        # Waits for the running app's PID to exit, replaces the app
        # bundle with the freshly downloaded one, cleans up the DMG,
        # then relaunches.
        set -e
        PID=\(ourPID)
        SRC=\(q(sourceApp))
        DEST=\(q(destApp))
        VOL=\(q(mountPoint))
        DMG=\(q(dmgFile))

        # Wait up to 30s for the old process to die.
        for _ in $(seq 1 30); do
          if ! /bin/ps -p $PID > /dev/null 2>&1; then break; fi
          sleep 1
        done

        # Replace the bundle. cp -R first, then mv-style rename so a
        # half-finished copy can never leave the user without an app.
        STAGE="$DEST.update-staging"
        /bin/rm -rf "$STAGE"
        /bin/cp -R "$SRC" "$STAGE"
        /bin/rm -rf "$DEST"
        /bin/mv "$STAGE" "$DEST"

        /usr/bin/hdiutil detach "$VOL" -force >/dev/null 2>&1 || true
        /bin/rm -f "$DMG"

        # Strip Gatekeeper quarantine so the freshly-copied bundle isn't
        # treated as "from the internet" on the next open.
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" >/dev/null 2>&1 || true

        /usr/bin/open "$DEST"

        /bin/rm -f "$0"
        """
        do {
            try body.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            // chmod +x via FileManager — no Process needed.
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        } catch {
            NSLog("update: write helper failed: \(error)")
            return
        }

        // Detach with nohup so the script survives us terminating. Pipe
        // stdout/stderr to /dev/null and run in background.
        let proc = Process()
        proc.launchPath = "/bin/bash"
        proc.arguments = ["-c", "/usr/bin/nohup \(scriptPath) >/dev/null 2>&1 &"]
        try? proc.run()
    }

    // MARK: - Helpers

    private func currentVersionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Naïve semver compare — splits on dot, compares numerically,
    /// pads shorter strings with zeros ("1.2" < "1.2.0" → false). Good
    /// enough for our 1.2.3 release scheme.
    private func isNewer(latest: String, than current: String) -> Bool {
        let a = latest.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
