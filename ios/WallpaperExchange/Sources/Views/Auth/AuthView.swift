import SwiftUI

// Native email/password login + registration against /auth/login and
// /auth/register — same endpoints the Mac client's AuthView uses.
struct AuthView: View {
    enum Mode {
        case login
        case register
    }

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var errorMessage: String?

    init(mode: Mode = .login) {
        _mode = State(initialValue: mode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if mode == .register {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
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
                            } else {
                                Text(mode == .login ? "Sign In" : "Create Account")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(working || !formValid)
                }

                Section {
                    Button(mode == .login ? "New here? Create an account" : "Already have an account? Sign in") {
                        errorMessage = nil
                        mode = mode == .login ? .register : .login
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle(mode == .login ? "Sign In" : "Register")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var formValid: Bool {
        let emailOK = email.contains("@") && email.count >= 5
        let passwordOK = password.count >= 6
        if mode == .register {
            return emailOK && passwordOK && username.trimmingCharacters(in: .whitespaces).count >= 2
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
