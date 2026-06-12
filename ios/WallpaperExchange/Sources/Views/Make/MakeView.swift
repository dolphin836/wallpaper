import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins

// Make — the mobile-only wallpaper workshop. Pick a photo, restyle it
// with one of the archive's looks, judge it behind the lock-screen
// mock, then save the full-resolution result to Photos.
struct MakeView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var sourceData: Data?
    @State private var styledImage: PlatformImage?
    @State private var style: WallpaperStyle = .original
    @State private var rendering = false
    @State private var saving = false
    @State private var savedTick = false
    @State private var errorMessage: String?
    @State private var lockMock = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ArchiveTopBar(title: "Make")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(kicker: "The mobile workshop", title: "Make a wallpaper")
                        if sourceData == nil {
                            emptyPicker
                        } else {
                            preview
                            styleStrip
                            saveSection
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Text("Start over with a different photo")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.accentInk)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(Color.paper)
            }
            .background(Color.paper)
            .navigationTitle("")
            .inlineNavTitle()
            .hideNavBarCompat()
            .hideTabBarCompat()
            .safeAreaInset(edge: .bottom) { FloatingTabBar() }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        sourceData = data
                        style = .original
                        savedTick = false
                        errorMessage = nil
                        await render()
                    }
                }
            }
            .onChange(of: style) { _, _ in
                savedTick = false
                Task { await render() }
            }
        }
    }

    private var emptyPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accent)
                Text("Choose a photo to restyle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ink)
                Text("MONO · FILM · DUSK · INK WASH · MORE")
                    .font(.kicker)
                    .tracking(1.5)
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 64)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(Color.accent.opacity(0.5))
            )
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let styledImage {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Image(platformImage: styledImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 430)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    if lockMock {
                        LockScreenOverlay(compact: false)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                    if rendering {
                        Color.black.opacity(0.25)
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(height: 430)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Color.hair, lineWidth: 1)
                )

                Toggle(isOn: $lockMock) {
                    Text("LOCK SCREEN MOCK")
                        .font(.kicker)
                        .tracking(1.0)
                        .foregroundStyle(Color.muted)
                }
                .toggleStyle(.switch)
                .tint(Color.accent)
            }
        }
    }

    private var styleStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(text: "Pick a look")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WallpaperStyle.allCases) { s in
                        Button {
                            style = s
                        } label: {
                            Text(s.label)
                                .font(.caption.weight(style == s ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(style == s ? Color.ink : Color.paper2, in: Capsule())
                                .overlay(
                                    Capsule().strokeBorder(
                                        style == s ? Color.clear : Color.hair, lineWidth: 1)
                                )
                                .foregroundStyle(style == s ? Color.paper : Color.ink2)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                save()
            } label: {
                HStack(spacing: 6) {
                    if saving {
                        ProgressView().controlSize(.small).tint(Color.lightText)
                    } else {
                        Image(systemName: savedTick ? "checkmark.circle.fill" : "square.and.arrow.down")
                            .font(.system(size: 14))
                    }
                    Text(savedTick ? "Saved to Photos" : "Save wallpaper")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.lightText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(savedTick ? Color.accent.opacity(0.6) : Color.accent, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(saving || rendering || savedTick)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.warn)
            }
        }
    }

    // ─── rendering ───────────────────────────────────────────────

    private func render() async {
        guard let sourceData else { return }
        rendering = true
        defer { rendering = false }
        let currentStyle = style
        let rendered = await Task.detached(priority: .userInitiated) {
            WallpaperStyler.apply(currentStyle, to: sourceData)
        }.value
        guard style == currentStyle else { return }
        styledImage = rendered
        if rendered == nil {
            errorMessage = "Could not process that image."
        }
    }

    private func save() {
        guard let sourceData else { return }
        saving = true
        errorMessage = nil
        let currentStyle = style
        Task {
            defer { saving = false }
            // Re-render at full resolution off the preview path so the
            // saved file keeps every pixel of the source.
            let data = await Task.detached(priority: .userInitiated) {
                WallpaperStyler.renderData(currentStyle, from: sourceData)
            }.value
            guard let data else {
                errorMessage = "Could not render the wallpaper."
                return
            }
            do {
                try await PhotoSaver.save(imageData: data)
                savedTick = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// The archive's looks. Chains of CoreImage filters tuned for wallpaper
// use: strong enough to read as a style, restrained enough to keep the
// photo's structure.
enum WallpaperStyle: String, CaseIterable, Identifiable {
    case original
    case mono
    case film
    case dusk
    case inkWash
    case vivid
    case frost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .mono: return "Mono"
        case .film: return "Film"
        case .dusk: return "Dusk"
        case .inkWash: return "Ink Wash"
        case .vivid: return "Vivid"
        case .frost: return "Frost"
        }
    }
}

enum WallpaperStyler {
    private static let context = CIContext()

    static func apply(_ style: WallpaperStyle, to data: Data) -> PlatformImage? {
        guard let output = styledCIImage(style, from: data, maxDimension: 1400),
              let cg = context.createCGImage(output, from: output.extent)
        else { return nil }
        #if canImport(UIKit)
        return PlatformImage(cgImage: cg)
        #else
        return PlatformImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #endif
    }

    static func renderData(_ style: WallpaperStyle, from data: Data) -> Data? {
        guard let output = styledCIImage(style, from: data, maxDimension: nil) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        return context.jpegRepresentation(
            of: output, colorSpace: space,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.92]
        )
    }

    private static func styledCIImage(_ style: WallpaperStyle, from data: Data, maxDimension: CGFloat?) -> CIImage? {
        guard var image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }

        if let maxDimension {
            let largest = max(image.extent.width, image.extent.height)
            if largest > maxDimension {
                let scale = maxDimension / largest
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        switch style {
        case .original:
            return image

        case .mono:
            let f = CIFilter.photoEffectNoir()
            f.inputImage = image
            return f.outputImage

        case .film:
            let tone = CIFilter.photoEffectChrome()
            tone.inputImage = image
            let grain = CIFilter.colorControls()
            grain.inputImage = tone.outputImage
            grain.saturation = 0.88
            grain.contrast = 1.04
            let vignette = CIFilter.vignette()
            vignette.inputImage = grain.outputImage
            vignette.intensity = 0.7
            vignette.radius = 1.6
            return vignette.outputImage

        case .dusk:
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage = image
            temp.neutral = CIVector(x: 5200, y: 0)
            temp.targetNeutral = CIVector(x: 4200, y: 8)
            let controls = CIFilter.colorControls()
            controls.inputImage = temp.outputImage
            controls.brightness = -0.05
            controls.saturation = 1.06
            return controls.outputImage

        case .inkWash:
            let mono = CIFilter.photoEffectTonal()
            mono.inputImage = image
            let controls = CIFilter.colorControls()
            controls.inputImage = mono.outputImage
            controls.contrast = 0.92
            controls.brightness = 0.06
            // Tint the paper-white end toward the archive's warm paper.
            let tint = CIFilter.colorMonochrome()
            tint.inputImage = controls.outputImage
            tint.color = CIColor(red: 0.94, green: 0.92, blue: 0.88)
            tint.intensity = 0.25
            return tint.outputImage

        case .vivid:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.saturation = 1.35
            controls.contrast = 1.06
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = controls.outputImage
            vibrance.amount = 0.5
            return vibrance.outputImage

        case .frost:
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = image.clampedToExtent()
            blur.radius = 24
            let controls = CIFilter.colorControls()
            controls.inputImage = blur.outputImage?.cropped(to: image.extent)
            controls.brightness = 0.04
            controls.saturation = 1.1
            return controls.outputImage
        }
    }
}
