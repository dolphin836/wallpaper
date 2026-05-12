// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WallpaperExchange",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WallpaperExchange",
            path: "Sources",
            resources: [
                // Ship the web brand logo as `StatusBarIcon` (in Sources/Resources/).
                // Accessed via `Bundle.module` from AppDelegate at startup.
                .process("Resources"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist",
                ]),
            ]
        ),
    ]
)
