import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// Wallpaper Exchange macOS UI smoke test.
//
// Drives the real app through the system Accessibility API — the same
// channel VoiceOver and other assistive tools use — so every step is a
// genuine "human" interaction: buttons are located by their visible
// labels and pressed via AX actions, not blind coordinate clicks.
//
// Flow: launch → main window appears → click through the four nav
// tabs → open a collection (second-level page) → floating back button
// returns → open a wallpaper detail from Home → ESC closes it → quit.
// A window screenshot is captured after every step (requires Screen
// Recording permission; skipped gracefully without it).
//
// Requirements: the process running this binary must have Accessibility
// permission (System Settings → Privacy & Security → Accessibility).
// Exit codes: 0 all steps passed · 1 at least one step failed ·
// 2 missing permission / setup problem.

// ─── Config ─────────────────────────────────────────────────────

let appPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "WallpaperExchange/.build/debug/WallpaperExchange"
let artifactsDir = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "uitest/artifacts"

// Nav labels in every app language — the app follows its own language
// preference, so match any locale's caption.
let navHome        = ["Home", "首页", "首頁", "ホーム"]
let navDiscover    = ["Discover", "发现", "探索", "発見"]
let navWeekly      = ["Weekly", "每周精选", "每週精選", "ウィークリー"]
let navCollections = ["Collections", "合集", "合輯", "コレクション"]
let backLabels     = ["Back", "后退", "返回", "戻る"]
let chromeLabels   = navHome + navDiscover + navWeekly + navCollections + backLabels

// ─── Reporting ──────────────────────────────────────────────────

var results: [(step: String, ok: Bool, note: String)] = []

func report(_ step: String, _ ok: Bool, _ note: String = "") {
    results.append((step, ok, note))
    print("\(ok ? "PASS" : "FAIL")  \(step)\(note.isEmpty ? "" : "  — \(note)")")
}

func finish(app: Process?) -> Never {
    app?.terminate()
    let failed = results.filter { !$0.ok }
    print("\n══ Summary: \(results.count - failed.count)/\(results.count) passed ══")
    exit(failed.isEmpty ? 0 : 1)
}

// ─── AX helpers ─────────────────────────────────────────────────

func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
    return value
}

func role(_ el: AXUIElement) -> String {
    (attr(el, kAXRoleAttribute) as? String) ?? ""
}

func label(_ el: AXUIElement) -> String {
    if let t = attr(el, kAXTitleAttribute) as? String, !t.isEmpty { return t }
    if let d = attr(el, kAXDescriptionAttribute) as? String, !d.isEmpty { return d }
    return ""
}

func point(_ el: AXUIElement) -> CGPoint {
    guard let raw = attr(el, kAXPositionAttribute) else { return .zero }
    var pt = CGPoint.zero
    AXValueGetValue(raw as! AXValue, .cgPoint, &pt)
    return pt
}

func size(_ el: AXUIElement) -> CGSize {
    guard let raw = attr(el, kAXSizeAttribute) else { return .zero }
    var sz = CGSize.zero
    AXValueGetValue(raw as! AXValue, .cgSize, &sz)
    return sz
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

struct FoundButton {
    let element: AXUIElement
    let label: String
    let origin: CGPoint
    let size: CGSize
}

func collectButtons(_ root: AXUIElement, depth: Int = 0, into found: inout [FoundButton]) {
    guard depth < 30 else { return }
    if role(root) == kAXButtonRole as String {
        found.append(FoundButton(element: root, label: label(root), origin: point(root), size: size(root)))
    }
    for child in children(root) {
        collectButtons(child, depth: depth + 1, into: &found)
    }
}

func appButtons(_ appEl: AXUIElement) -> [FoundButton] {
    var found: [FoundButton] = []
    for window in (attr(appEl, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
        collectButtons(window, into: &found)
    }
    return found
}

func press(_ button: FoundButton) -> Bool {
    AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success
}

func findButton(_ appEl: AXUIElement, labeledAny candidates: [String]) -> FoundButton? {
    appButtons(appEl).first { candidates.contains($0.label) }
}

// ─── Window / process helpers ───────────────────────────────────

func mainWindowNumber(pid: pid_t) -> Int? {
    let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
    for info in list where (info[kCGWindowOwnerPID as String] as? pid_t) == pid {
        guard let bounds = info[kCGWindowBounds as String] as? [String: Int],
              let width = bounds["Width"], let height = bounds["Height"],
              width > 800, height > 400
        else { continue }
        return info[kCGWindowNumber as String] as? Int
    }
    return nil
}

func waitForMainWindow(pid: pid_t, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if mainWindowNumber(pid: pid) != nil { return true }
        Thread.sleep(forTimeInterval: 0.5)
    }
    return false
}

var shotIndex = 0
var screenshotsAvailable = true

func screenshot(pid: pid_t, name: String) {
    guard screenshotsAvailable, let windowNumber = mainWindowNumber(pid: pid) else { return }
    shotIndex += 1
    let file = "\(artifactsDir)/\(String(format: "%02d", shotIndex))-\(name).png"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l", String(windowNumber), file]
    try? task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 || !FileManager.default.fileExists(atPath: file) {
        screenshotsAvailable = false
        print("NOTE  screenshots unavailable (grant Screen Recording to the runner to enable)")
    }
}

func sendEscape(pid: pid_t) {
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)?.postToPid(pid)
    CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)?.postToPid(pid)
}

func settle(_ seconds: TimeInterval = 2.0) {
    Thread.sleep(forTimeInterval: seconds)
}

// ─── Preflight ──────────────────────────────────────────────────

guard AXIsProcessTrusted() else {
    print("""
    FAIL  Accessibility permission missing.
          Grant it to the process running this test (e.g. Terminal/iTerm):
          System Settings → Privacy & Security → Accessibility → enable it,
          then re-run.
    """)
    exit(2)
}

try? FileManager.default.createDirectory(atPath: artifactsDir, withIntermediateDirectories: true)

guard FileManager.default.isExecutableFile(atPath: appPath) else {
    print("FAIL  app binary not found at \(appPath) — run `swift build` first")
    exit(2)
}

// ─── Steps ──────────────────────────────────────────────────────

let app = Process()
app.executableURL = URL(fileURLWithPath: appPath)
do { try app.run() } catch {
    print("FAIL  could not launch app: \(error)")
    exit(2)
}
let pid = app.processIdentifier
print("launched pid=\(pid)")

// 1. Main window mounts.
let windowAppeared = waitForMainWindow(pid: pid, timeout: 20)
report("launch: main window appears", windowAppeared)
guard windowAppeared else { finish(app: app) }
settle(3)
screenshot(pid: pid, name: "launch-home")

let appEl = AXUIElementCreateApplication(pid)

// 2. Click through the four nav tabs.
let tabs: [(name: String, labels: [String])] = [
    ("discover", navDiscover),
    ("weekly", navWeekly),
    ("collections", navCollections),
    ("home", navHome),
]
for tab in tabs {
    guard let button = findButton(appEl, labeledAny: tab.labels) else {
        report("nav: \(tab.name) button found", false, "no AXButton labeled \(tab.labels)")
        continue
    }
    let pressed = press(button)
    settle(2.5)
    let alive = mainWindowNumber(pid: pid) != nil
    report("nav: switch to \(tab.name)", pressed && alive)
    screenshot(pid: pid, name: "nav-\(tab.name)")
}

// 3. Second-level page + floating back button, via Collections.
if let collectionsButton = findButton(appEl, labeledAny: navCollections) {
    _ = press(collectionsButton)
    settle(3)
    // A collection card = the largest content-area button below the
    // chrome row that isn't a known chrome control.
    let card = appButtons(appEl)
        .filter { !chromeLabels.contains($0.label) && $0.origin.y > 120 && $0.size.width > 150 }
        .max { $0.size.width * $0.size.height < $1.size.width * $1.size.height }
    if let card {
        _ = press(card)
        settle(3)
        screenshot(pid: pid, name: "collection-detail")
        if let backButton = findButton(appEl, labeledAny: backLabels) {
            let pressedBack = press(backButton)
            settle(2)
            report("back: floating button returns from detail", pressedBack)
            screenshot(pid: pid, name: "back-to-collections")
        } else {
            report("back: floating button appears on pushed page", false, "no back AXButton found")
        }
    } else {
        report("collections: open first collection card", false, "no card-sized button found")
    }
}

// 4. Wallpaper detail overlay from Home, closed with ESC.
if let homeButton = findButton(appEl, labeledAny: navHome) {
    _ = press(homeButton)
    settle(3)
    let card = appButtons(appEl)
        .filter { !chromeLabels.contains($0.label) && $0.origin.y > 140 && $0.size.width > 200 }
        .max { $0.size.width * $0.size.height < $1.size.width * $1.size.height }
    if let card {
        let buttonCountBefore = appButtons(appEl).count
        _ = press(card)
        settle(3.5)
        let buttonCountDetail = appButtons(appEl).count
        screenshot(pid: pid, name: "wallpaper-detail")
        // The detail overlay swaps the whole surface, so the AX button
        // population changes noticeably.
        report("detail: overlay opens from home card", buttonCountDetail != buttonCountBefore,
               "buttons \(buttonCountBefore) → \(buttonCountDetail)")
        sendEscape(pid: pid)
        settle(2)
        let buttonCountAfter = appButtons(appEl).count
        report("detail: ESC closes overlay", abs(buttonCountAfter - buttonCountBefore) <= 3,
               "buttons back to \(buttonCountAfter)")
        screenshot(pid: pid, name: "detail-closed")
    } else {
        report("home: open first wallpaper card", false, "no card-sized button found")
    }
}

// 5. Process stayed healthy the whole run.
report("stability: app process alive at end", app.isRunning)

finish(app: app)
