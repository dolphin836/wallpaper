import Foundation

// File-based storage for the auth JWT.
//
// Trade-off, decided 2026-07-05 (supersedes the 2026-06-10 Keychain
// decision): the app is ad-hoc signed, so its code identity changes on
// every rebuild/update and the Keychain consent prompt reappeared each
// time — unacceptable friction for a wallpaper session token. The JWT
// now lives in a user-only-readable file (directory 0700, file 0600)
// under Application Support. That protects it from other users on the
// machine; processes running as the same user could read it, which is
// the accepted risk for this credential class. Tokens expire server-
// side and logout deletes the file.
enum FileTokenStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("WallpaperExchange", isDirectory: true)
            .appendingPathComponent("auth.token", isDirectory: false)
    }

    static func load() -> String? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func save(_ token: String) {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? Data(token.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
