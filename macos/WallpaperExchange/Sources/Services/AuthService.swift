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

    private var didLoadPersistedToken = false

    // Keychain access is deliberately kept OUT of init and off the main
    // thread. Reading the JWT with SecItemCopyMatching blocks until the
    // keychain consent prompt is answered, and because the app is ad-hoc
    // signed that prompt reappears after every re-sign (every update /
    // dev rebuild — see KeychainTokenStore). The consent dialog is a
    // system-modal window: if it comes up during launch, before the app
    // has activated, it prevents the SwiftUI `Window` scene from ever
    // presenting its initial window — the app looks frozen with no main
    // window ("主界面出不来"). So the singleton starts logged-out and the
    // main window drives loadPersistedToken() from its .task, once it is
    // on screen. The consent prompt (if any) then floats over a visible
    // window and answering it flips the UI to signed-in.
    private init() {}

    // Called from the main window's .task after it appears. Idempotent.
    func loadPersistedToken() async {
        guard !didLoadPersistedToken else { return }
        didLoadPersistedToken = true

        let legacyKey = legacyTokenDefaultsKey
        let loaded = await Task.detached(priority: .userInitiated) { () -> String? in
            if let legacy = UserDefaults.standard.string(forKey: legacyKey) {
                // One-time migration off the old plain-text defaults storage.
                KeychainTokenStore.save(legacy)
                UserDefaults.standard.removeObject(forKey: legacyKey)
                return legacy
            }
            return KeychainTokenStore.load()
        }.value

        // A sign-in that completed while the Keychain load was pending
        // owns the newer token; don't clobber it. The caller refreshes
        // the profile after this returns.
        guard let loaded, token == nil else { return }
        token = loaded
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
