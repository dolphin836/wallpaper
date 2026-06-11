import Foundation

enum AuthFlow: String, Identifiable {
    case login
    case register

    var id: String { rawValue }
}

@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    private(set) var token: String?
    private(set) var user: User?
    var authFlow: AuthFlow?
    var isLoggedIn: Bool { token != nil }

    // JWT lives in the Keychain (see KeychainTokenStore for the prompt
    // trade-off). This key only remains for the one-time migration of
    // tokens persisted by pre-Keychain builds.
    private let legacyTokenDefaultsKey = "auth.jwt_token"

    private init() {
        if let legacy = UserDefaults.standard.string(forKey: legacyTokenDefaultsKey) {
            // One-time migration off the old plain-text defaults storage.
            KeychainTokenStore.save(legacy)
            UserDefaults.standard.removeObject(forKey: legacyTokenDefaultsKey)
            token = legacy
        } else {
            token = KeychainTokenStore.load()
        }
    }

    func login() {
        authFlow = .login
    }

    func register() {
        authFlow = .register
    }

    func dismissAuth() {
        authFlow = nil
    }

    func signIn(email: String, password: String) async throws {
        let response = try await APIClient.shared.login(email: email, password: password)
        applyAuth(response)
    }

    func signUp(username: String, email: String, password: String) async throws {
        let response = try await APIClient.shared.register(username: username, email: email, password: password)
        applyAuth(response)
    }

    private func applyAuth(_ response: AuthResponse) {
        token = response.token
        user = response.user
        authFlow = nil
        KeychainTokenStore.save(response.token)
        Task {
            await refreshProfile()
        }
    }

    func logout() {
        token = nil
        user = nil
        authFlow = nil
        KeychainTokenStore.delete()
    }

    func refreshProfile() async {
        guard token != nil else { return }
        do {
            // Fetch the whole user payload via /users/me. Previous version only refreshed
            // `coins` on an already-populated user — so after a fresh login (user == nil)
            // it did nothing, leaving the menubar showing "Not signed in" forever despite
            // a valid token.
            let u = try await APIClient.shared.fetchProfile()
            self.user = u
        } catch let error as APIError {
            if case .unauthorized = error {
                logout()
            }
        } catch {}
    }

    @discardableResult
    func refreshCoins() async -> Int? {
        guard token != nil else { return nil }
        do {
            let coins = try await APIClient.shared.fetchCoins()
            if let u = user {
                user = User(
                    id: u.id,
                    username: u.username,
                    email: u.email,
                    nickname: u.nickname,
                    avatarURL: u.avatarURL,
                    bio: u.bio,
                    coins: coins,
                    status: u.status,
                    createdAt: u.createdAt,
                    likesPublic: u.likesPublic,
                    favoritesPublic: u.favoritesPublic,
                    downloadsPublic: u.downloadsPublic
                )
            } else {
                await refreshProfile()
            }
            return user?.coins ?? coins
        } catch let error as APIError {
            if case .unauthorized = error {
                logout()
            }
            return nil
        } catch {
            return nil
        }
    }

}
