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
}
