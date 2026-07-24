import SwiftUI

// Ant Design's web detail/card icons, redrawn as native SwiftUI vector
// shapes so every Mac surface uses the same silhouette without bundling a
// raster asset or introducing an icon dependency.
struct WebDownloadIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x / 1024 * side, y: origin.y + y / 1024 * side)
        }

        var path = Path()
        // Down arrow: the shaft and broad arrowhead match AiOutlineDownload.
        path.move(to: point(474, 160))
        path.addLine(to: point(550, 160))
        path.addLine(to: point(550, 506))
        path.addLine(to: point(624, 506))
        path.addLine(to: point(512, 669))
        path.addLine(to: point(393, 519))
        path.addLine(to: point(474, 519))
        path.closeSubpath()

        // Open-top download baseline used by the web icon (not a tray).
        path.move(to: point(138, 626))
        path.addLine(to: point(214, 626))
        path.addLine(to: point(214, 788))
        path.addLine(to: point(810, 788))
        path.addLine(to: point(810, 626))
        path.addLine(to: point(886, 626))
        path.addLine(to: point(886, 832))
        path.addLine(to: point(854, 864))
        path.addLine(to: point(170, 864))
        path.addLine(to: point(138, 832))
        path.closeSubpath()
        return path
    }
}

struct WebFullscreenIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
        let base: [(CGFloat, CGFloat)] = [
            (423.7, 370.1), (290, 236.4), (333.9, 192.5),
            (160, 160), (179, 329.1), (236.3, 290.1), (370, 423.7),
        ]

        func rotated(_ point: (CGFloat, CGFloat), quarterTurns: Int) -> (CGFloat, CGFloat) {
            switch quarterTurns {
            case 1: (1024 - point.1, point.0)
            case 2: (1024 - point.0, 1024 - point.1)
            case 3: (point.1, 1024 - point.0)
            default: point
            }
        }
        func scaled(_ point: (CGFloat, CGFloat)) -> CGPoint {
            CGPoint(
                x: origin.x + point.0 / 1024 * side,
                y: origin.y + point.1 / 1024 * side
            )
        }

        var path = Path()
        for quarterTurns in 0..<4 {
            let points = base.map { scaled(rotated($0, quarterTurns: quarterTurns)) }
            guard let first = points.first else { continue }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }
}
