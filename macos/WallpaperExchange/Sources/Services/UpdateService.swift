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
        let panel = UpdateProgressPanel(version: release.currentVersion)
        panel.show()

        Task { @MainActor in
            await self.downloadAndInstall(release: release, panel: panel)
        }
    }

    private func downloadAndInstall(release: MacRelease, panel: UpdateProgressPanel) async {
        guard let url = URL(string: release.currentDmgURL) else {
            panel.close()
            showAlert(title: "Update failed", message: "Bad download URL.", style: .warning)
            return
        }
        let dmgPath = NSTemporaryDirectory() + "wxch-update-\(release.currentVersion).dmg"
        let dmgURL = URL(fileURLWithPath: dmgPath)

        // Real progress download. The custom delegate streams
        // didWriteData callbacks into the panel so the user can see
        // bytes flow in instead of staring at a static "Downloading…"
        // for what could be 5–30 seconds on a slow link.
        do {
            try await downloadWithProgress(from: url, to: dmgURL, panel: panel)
        } catch is CancellationError {
            panel.close()
            return
        } catch {
            panel.close()
            showAlert(title: "Update failed", message: "Download failed: \(error.localizedDescription)", style: .warning)
            return
        }

        // Switch the bar to indeterminate while we mount + stage. The
        // hdiutil + cp steps are fast (sub-second on a 1.3 MiB DMG) but
        // we still want a visible signal that something is happening.
        panel.setStage("Installing…")

        let mountPoint: String
        do {
            mountPoint = try attachDMG(at: dmgPath)
        } catch {
            panel.close()
            showAlert(title: "Update failed", message: "Couldn't mount the installer: \(error.localizedDescription)", style: .warning)
            return
        }

        guard let sourceAppPath = locateAppBundle(in: mountPoint) else {
            _ = try? detachDMG(mountPoint: mountPoint)
            panel.close()
            showAlert(title: "Update failed", message: "The installer didn't contain an app bundle.", style: .warning)
            return
        }

        let myBundlePath = Bundle.main.bundleURL.path

        spawnInstallHelper(
            ourPID: ProcessInfo.processInfo.processIdentifier,
            sourceApp: sourceAppPath,
            destApp: myBundlePath,
            mountPoint: mountPoint,
            dmgFile: dmgPath
        )

        panel.setStage("Restarting…")

        // Brief beat so the user reads the "Restarting…" status before
        // the window closes.
        try? await Task.sleep(nanoseconds: 600_000_000)
        panel.close()
        NSApp.terminate(nil)
    }

    /// Streams a URLSessionDownloadTask through a delegate so the panel
    /// can show real progress. Cancellation flows through the panel's
    /// onCancel callback — when the user clicks Cancel we throw a
    /// CancellationError out of the awaiter.
    private func downloadWithProgress(from url: URL, to dest: URL, panel: UpdateProgressPanel) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let delegate = DownloadProgressDelegate(destURL: dest)
            delegate.onProgress = { [weak panel] written, total in
                Task { @MainActor in panel?.update(written: written, total: total) }
            }
            delegate.onComplete = { result in
                switch result {
                case .success:                cont.resume()
                case .failure(let e):         cont.resume(throwing: e)
                }
            }
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 300
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: url)

            panel.onCancel = { [weak task] in
                task?.cancel()
            }
            task.resume()
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

// MARK: - Progress panel

/// A small floating panel showing download progress + bytes + a Cancel
/// button. NSPanel (not NSAlert) so it can update in real time without
/// blocking a modal run loop, and so .floating level keeps it on top
/// even for LSUIElement (no Dock icon) menu-bar apps.
@MainActor
private final class UpdateProgressPanel {
    private let panel: NSPanel
    private let titleLabel: NSTextField
    private let progressBar: NSProgressIndicator
    private let detailLabel: NSTextField
    private let cancelButton: NSButton

    /// Invoked when the user clicks Cancel. UpdateService wires this to
    /// task.cancel() so the in-flight download gets torn down.
    var onCancel: (() -> Void)?

    init(version: String) {
        // 460×140 keeps the panel small enough to live alongside the
        // status bar popover but wide enough to read the progress text
        // without truncation.
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 140),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Wallpaper Exchange Update"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel = NSTextField(labelWithString: "Downloading version \(version)…")
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = true
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.startAnimation(nil)

        detailLabel = NSTextField(labelWithString: "Connecting…")
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.distribution = .equalSpacing
        footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        footer.addArrangedSubview(spacer)
        footer.addArrangedSubview(cancelButton)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(progressBar)
        stack.addArrangedSubview(detailLabel)
        stack.addArrangedSubview(footer)

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 20),
            progressBar.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -20),
            progressBar.heightAnchor.constraint(equalToConstant: 10),
            footer.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -20),
        ])
        panel.contentView = content

        cancelButton.target = self
        cancelButton.action = #selector(handleCancel)
    }

    func show() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        progressBar.stopAnimation(nil)
        panel.orderOut(nil)
    }

    /// Update progress mid-download. Flips the bar from indeterminate
    /// to determinate on the first call so the user gets a real % as
    /// soon as the server reports a Content-Length.
    func update(written: Int64, total: Int64) {
        if total > 0 {
            if progressBar.isIndeterminate {
                progressBar.stopAnimation(nil)
                progressBar.isIndeterminate = false
            }
            let pct = Double(written) / Double(total) * 100.0
            progressBar.doubleValue = pct
            detailLabel.stringValue = String(
                format: "%.1f MB / %.1f MB · %.0f%%",
                Double(written) / 1024 / 1024,
                Double(total) / 1024 / 1024,
                pct
            )
        } else {
            // Server didn't send Content-Length — keep the bar
            // indeterminate but at least show the running total.
            detailLabel.stringValue = String(format: "%.1f MB downloaded", Double(written) / 1024 / 1024)
        }
    }

    /// Switch from download mode to a generic "doing the install" mode.
    /// Bar goes back to indeterminate; title + cancel button hide so
    /// the user understands the operation is past the point of no
    /// return.
    func setStage(_ text: String) {
        titleLabel.stringValue = text
        detailLabel.stringValue = ""
        progressBar.isIndeterminate = true
        progressBar.startAnimation(nil)
        cancelButton.isEnabled = false
    }

    @objc private func handleCancel() {
        onCancel?()
    }
}

// MARK: - Download delegate

/// URLSessionDownloadDelegate adapter that bridges the URLSession
/// callback queue into the @MainActor world. Keeps UpdateService's
/// awaiter alive via the onComplete closure until the move succeeds
/// (or any error has bubbled up).
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destURL: URL

    var onProgress: ((_ written: Int64, _ total: Int64) -> Void)?
    var onComplete: ((Result<Void, Error>) -> Void)?

    private var completed = false

    init(destURL: URL) {
        self.destURL = destURL
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // didFinishDownloadingTo fires on the URLSession's delegate
        // queue. Whatever we do here must happen before the function
        // returns — the system deletes `location` immediately after.
        do {
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.moveItem(at: location, to: destURL)
            completed = true
            onComplete?(.success(()))
        } catch {
            completed = true
            onComplete?(.failure(error))
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // didFinishDownloadingTo already fired for the success path; only
        // signal here if we ended up with an error (e.g. cancellation
        // before the move ran).
        guard !completed else { return }
        if let error = error {
            // URLSession surfaces a user cancel as code .cancelled — map
            // it to Swift's CancellationError so the UpdateService can
            // distinguish from a genuine failure and skip the alert.
            if (error as NSError).code == NSURLErrorCancelled {
                onComplete?(.failure(CancellationError()))
            } else {
                onComplete?(.failure(error))
            }
        }
        session.finishTasksAndInvalidate()
    }
}
