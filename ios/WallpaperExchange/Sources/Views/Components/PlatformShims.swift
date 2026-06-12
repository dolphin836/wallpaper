import SwiftUI

// Bridges the small UIKit/AppKit surface this app touches so the same
// sources build as the real iOS app (Xcode, project.yml) and as a macOS
// dev-preview window (`swift run`, Package.swift).

#if canImport(UIKit)
import UIKit

typealias PlatformImage = UIImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

#else
import AppKit

typealias PlatformImage = NSImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

#endif

// The aspect ratio every wallpaper tile is previewed at: this device's
// own screen ratio, i.e. exactly the crop the system applies when the
// image becomes the wallpaper. Width varies per surface; ratio never.
enum DeviceScreenRatio {
    @MainActor static var value: CGFloat {
        #if canImport(UIKit)
        let bounds = UIScreen.main.nativeBounds
        guard bounds.height > 0 else { return 9.0 / 19.5 }
        return bounds.width / bounds.height
        #else
        // iPhone-like canvas for the macOS dev preview.
        return 9.0 / 19.5
        #endif
    }
}

extension PlatformImage {
    // Pixel dimensions regardless of platform scale semantics.
    var pixelSize: CGSize {
        #if canImport(UIKit)
        return CGSize(width: size.width * scale, height: size.height * scale)
        #else
        guard let rep = representations.first else { return size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        #endif
    }
}

// iOS-only view modifiers, no-ops on macOS.
extension View {
    @ViewBuilder
    func inlineNavTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func emailFieldTraits() -> some View {
        #if os(iOS)
        self
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }

    @ViewBuilder
    func usernameFieldTraits() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }

    @ViewBuilder
    func mediumSheetDetents() -> some View {
        #if os(iOS)
        self.presentationDetents([.medium, .large])
        #else
        self.frame(minWidth: 420, minHeight: 480)
        #endif
    }

    // ToolbarPlacement.navigationBar is iOS-only; macOS keeps its window
    // toolbar untouched.
    @ViewBuilder
    func hideNavBarCompat() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    // Pushed pages must opt back IN: the root tabs hide the nav bar for
    // the custom ArchiveTopBar, and that hidden state otherwise carries
    // into pushed children — leaving them with no back button and no
    // edge-swipe.
    @ViewBuilder
    func showNavBarCompat() -> some View {
        #if os(iOS)
        self.toolbar(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    // fullScreenCover is iOS-only; the macOS dev-preview falls back to a
    // large sheet.
    @ViewBuilder
    func fullScreenCoverCompat<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented) {
            content().frame(minWidth: 440, minHeight: 720)
        }
        #endif
    }
}
