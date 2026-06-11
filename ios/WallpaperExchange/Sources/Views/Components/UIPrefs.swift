import SwiftUI

// Session-wide presentation switches driven from the top toolbar.
@MainActor
@Observable
final class UIPrefs {
    static let shared = UIPrefs()

    // When on, every wallpaper tile renders the lock-screen mock overlay
    // (clock + flashlight/camera pills) so users can judge how a
    // wallpaper actually reads behind iOS lock chrome.
    var lockPreview = false

    private init() {}
}
