import Foundation

// Debug-only launch arguments so screenshot automation (simctl launch
// ... -tab make -lockPreview) can land on any screen without UI
// scripting. Harmless in production: nothing passes the flags.
enum LaunchOptions {
    private static let args = ProcessInfo.processInfo.arguments

    static var tab: Int {
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return 0 }
        switch args[i + 1] {
        case "discover": return 1
        case "make": return 2
        case "me": return 3
        default: return 0
        }
    }

    static var lockPreview: Bool { args.contains("-lockPreview") }

    static var detailSlug: String? {
        guard let i = args.firstIndex(of: "-detail"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var showCollections: Bool { args.contains("-collections") }

    static var showWeekly: Bool { args.contains("-weekly") }
}
