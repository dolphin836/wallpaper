import SwiftUI

// Native email/password login + registration against /auth/login and
// /auth/register — same endpoints the Mac client's AuthView uses.
struct AuthView: View {
    enum Mode {
        case login
        case register
    }

    @Environment(AuthService.self) private var auth
    @Environment(UIPrefs.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptedLegal = false
    @State private var working = false
    @State private var errorMessage: String?

    init(mode: Mode = .login) {
        _mode = State(initialValue: mode)
    }

    var body: some View {
        let s = L10n.strings(for: prefs.language)

        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Kicker(text: mode == .login ? s.authSignInTitle : s.authRegisterTitle)
                        Text(mode == .login ? s.authSignInTitle : s.authRegisterTitle)
                            .font(.display22)
                            .foregroundStyle(Color.ink)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if mode == .register {
                        TextField(s.authUsername, text: $username, prompt: Text(s.authUsernamePlaceholder))
                            .textContentType(.username)
                            .usernameFieldTraits()
                        Text(s.authUsernameHelp)
                            .font(.caption)
                            .foregroundStyle(Color.muted)
                    }
                    TextField(s.authEmail, text: $email, prompt: Text(s.authEmailPlaceholder))
                        .textContentType(.emailAddress)
                        .emailFieldTraits()
                    SecureField(s.authPassword, text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                    Text(s.authPasswordHelp)
                        .font(.caption)
                        .foregroundStyle(Color.muted)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                if mode == .register {
                    Section {
                        Toggle(isOn: $acceptedLegal) {
                            Text(s.authAcceptLegal)
                                .font(.footnote)
                        }
                        Text(s.authLegalIntro)
                            .font(.caption)
                            .foregroundStyle(Color.muted)

                        NavigationLink {
                            LegalDocumentView(kind: .terms)
                        } label: {
                            Label(s.termsTitle, systemImage: LegalDocumentKind.terms.iconName())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        NavigationLink {
                            LegalDocumentView(kind: .privacy)
                        } label: {
                            Label(s.privacyTitle, systemImage: LegalDocumentKind.privacy.iconName())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        NavigationLink {
                            LegalDocumentView(kind: .dmca)
                        } label: {
                            Label(s.dmcaTitle, systemImage: LegalDocumentKind.dmca.iconName())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if working {
                                ProgressView()
                                Text(mode == .login ? s.authSigningIn : s.authCreating)
                                    .fontWeight(.semibold)
                            } else {
                                Text(mode == .login ? s.authSignInSubmit : s.authCreateAccountSubmit)
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(working || !formValid)
                }

                Section {
                    Button(mode == .login ? s.authSwitchToRegister : s.authSwitchToLogin) {
                        errorMessage = nil
                        mode = mode == .login ? .register : .login
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle(mode == .login ? s.authSignInTitle : s.authRegisterTitle)
            .inlineNavTitle()
            .scrollContentBackgroundCompat()
            .background(Color.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(s.cancel) {
                        auth.dismissAuth()
                        dismiss()
                    }
                }
            }
        }
    }

    private var formValid: Bool {
        let emailOK = email.contains("@") && email.count >= 5
        let passwordOK = password.count >= 6
        if mode == .register {
            return emailOK
                && passwordOK
                && username.trimmingCharacters(in: .whitespaces).count >= 2
                && acceptedLegal
        }
        return emailOK && passwordOK
    }

    private func submit() {
        working = true
        errorMessage = nil
        Task {
            defer { working = false }
            do {
                if mode == .login {
                    try await auth.signIn(email: email, password: password)
                } else {
                    try await auth.signUp(
                        username: username.trimmingCharacters(in: .whitespaces),
                        email: email,
                        password: password
                    )
                }
                dismiss()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
