import Foundation
import Security

// Generic-password Keychain storage for the auth JWT.
//
// Trade-off, decided 2026-06-10: the app is ad-hoc signed, so the Keychain
// ACL can't pin a stable code identity — after every app update the first
// Keychain access shows a system authorization prompt ("Always Allow"
// silences it until the next update). That prompt is why 1.1.0 moved the
// token OUT of Keychain; we're accepting it again in exchange for not
// persisting the token as plain text on disk. Shipping a Developer ID
// signed build would make the prompt disappear for good.
enum KeychainTokenStore {
    // iOS bundle id, NOT the Mac client's — sharing the Mac service name
    // makes the macOS dev-preview build trip a cross-app Keychain
    // authorization prompt against the real Mac client's token item.
    private static let service = "com.wallpaperexchange.ios"
    private static let account = "auth.jwt_token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        let data = Data(token.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
