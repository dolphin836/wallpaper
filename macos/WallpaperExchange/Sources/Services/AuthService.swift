import Foundation
import AuthenticationServices
import AppKit

@MainActor
@Observable
final class AuthService: NSObject {
    static let shared = AuthService()

    private(set) var token: String?
    private(set) var user: User?
    var isLoggedIn: Bool { token != nil }

    private let keychainService = "com.wallpaperexchange.mac"
    private let keychainAccount = "jwt_token"

    private let loginURL = "https://wallpaperexchange.com/login?desktop=1"

    private override init() {
        super.init()
        token = loadTokenFromKeychain()
    }

    func login() {
        guard let url = URL(string: loginURL) else { return }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "wallxch"
        ) { [weak self] callbackURL, error in
            guard let self, let callbackURL, error == nil else { return }
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            if let t = components?.queryItems?.first(where: { $0.name == "token" })?.value {
                Task { @MainActor in
                    self.handleAuthCallback(token: t)
                }
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    func handleAuthCallback(token: String) {
        self.token = token
        saveTokenToKeychain(token)
        Task {
            await refreshProfile()
        }
    }

    func logout() {
        token = nil
        user = nil
        deleteTokenFromKeychain()
    }

    func refreshProfile() async {
        guard token != nil else { return }
        do {
            let coins = try await APIClient.shared.fetchCoins()
            if let u = user {
                self.user = User(
                    id: u.id, username: u.username, email: u.email,
                    nickname: u.nickname, avatarURL: u.avatarURL,
                    bio: u.bio, coins: coins, status: u.status,
                    createdAt: u.createdAt
                )
            }
        } catch let error as APIError {
            if case .unauthorized = error {
                logout()
            }
        } catch {}
    }

    // MARK: - Keychain

    private func saveTokenToKeychain(_ token: String) {
        deleteTokenFromKeychain()
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first ?? NSWindow()
    }
}
