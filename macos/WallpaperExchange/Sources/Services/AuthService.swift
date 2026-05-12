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

    // JWT lives in UserDefaults rather than Keychain on purpose: Keychain access
    // triggers a system authorization prompt for every binary that isn't covered
    // by a stable code-signing ACL (i.e. every dev/local build), which was noisy.
    // The token's authority is limited to the wallpaper app (download/upload/coin
    // flows) and auto-expires in 24h, so plain-text persistence in this app's
    // sandboxed defaults plist is an acceptable trade for UX.
    private let tokenDefaultsKey = "auth.jwt_token"

    private let loginURL = "https://wallpaperexchange.com/login?desktop=1"

    private override init() {
        super.init()
        token = UserDefaults.standard.string(forKey: tokenDefaultsKey)
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
        UserDefaults.standard.set(token, forKey: tokenDefaultsKey)
        Task {
            await refreshProfile()
        }
    }

    func logout() {
        token = nil
        user = nil
        UserDefaults.standard.removeObject(forKey: tokenDefaultsKey)
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

}

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first ?? NSWindow()
    }
}
