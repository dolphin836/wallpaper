import SwiftUI

struct AuthModalOverlay: View {
    let mode: AuthFlow
    @State private var auth = AuthService.shared
    @State private var activeMode: AuthFlow

    init(mode: AuthFlow) {
        self.mode = mode
        _activeMode = State(initialValue: mode)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.48))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { auth.dismissAuth() }

            AuthPanel(mode: $activeMode)
                .frame(width: 430)
                .padding(22)
                .transition(.scale(scale: 0.98).combined(with: .opacity))
        }
        .animation(.easeOut(duration: 0.18), value: activeMode)
    }
}

private struct AuthPanel: View {
    @Binding var mode: AuthFlow
    @State private var auth = AuthService.shared
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case username, email, password
    }

    private var isRegistering: Bool { mode == .register }

    private var kicker: String {
        isRegistering ? L10n.auth.createAccount : L10n.auth.signIn
    }

    private var title: String {
        isRegistering ? L10n.auth.registerTitle : L10n.auth.loginTitle
    }

    private var subtitle: String {
        isRegistering ? L10n.auth.registerSubtitle : L10n.auth.loginSubtitle
    }

    private var submitTitle: String {
        if isSubmitting { return isRegistering ? L10n.auth.creatingAccount : L10n.auth.signingIn }
        return isRegistering ? L10n.auth.createAccount : L10n.auth.signIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                brand
                Spacer()
                Button(action: { auth.dismissAuth() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.muted)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.paper2.opacity(0.72)))
                        .overlay(Circle().strokeBorder(Color.hair, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(L10n.auth.close)
                .pointerCursor()
            }

            VStack(alignment: .leading, spacing: 7) {
                Kicker(text: kicker)
                Text(title)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(Color.ink)
                Text(subtitle)
                    .font(.sans13)
                    .foregroundStyle(Color.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                if isRegistering {
                    AuthInputField(
                        icon: "person",
                        label: L10n.auth.usernameLabel,
                        placeholder: "archivist",
                        text: $username
                    )
                    .focused($focusedField, equals: .username)
                }

                AuthInputField(
                    icon: "envelope",
                    label: L10n.auth.emailLabel,
                    placeholder: "you@example.com",
                    text: $email
                )
                .focused($focusedField, equals: .email)

                AuthInputField(
                    icon: "lock",
                    label: L10n.auth.passwordLabel,
                    placeholder: isRegistering ? L10n.auth.passwordHintNew : L10n.auth.passwordLabel,
                    text: $password,
                    isSecure: true
                )
                .focused($focusedField, equals: .password)
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.warn)
                    Text(errorMessage)
                        .font(.sans12)
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.warn.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.warn.opacity(0.24), lineWidth: 1)
                )
            }

            VStack(spacing: 12) {
                Button(action: { Task { await submit() } }) {
                    HStack(spacing: 9) {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.62)
                                .frame(width: 14, height: 14)
                        }
                        Text(submitTitle)
                        if !isSubmitting {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.lightText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.accent, Color.accent.blended(with: Color.ink, fraction: 0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .opacity(isSubmitting ? 0.74 : 1)
                .pointerCursor()

                HStack(spacing: 6) {
                    Text(isRegistering ? L10n.auth.haveAccount : L10n.auth.newHere)
                        .font(.sans12)
                        .foregroundStyle(Color.muted)
                    Button(isRegistering ? L10n.auth.signIn : L10n.auth.createOne) {
                        switchMode()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentInk)
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .pointerCursor()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.paper.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.hair, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.26), radius: 32, x: 0, y: 18)
        .onAppear {
            focusedField = isRegistering ? .username : .email
        }
        .onChange(of: mode) { _, newValue in
            focusedField = newValue == .register ? .username : .email
        }
        .onSubmit {
            Task { await submit() }
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            if let logo = BrandAsset.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentSoft)
                    .frame(width: 24, height: 24)
                    .overlay(Image(systemName: "photo.on.rectangle").font(.system(size: 11)))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Wallpaper")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.ink)
                Text("EXCHANGE")
                    .font(.kicker)
                    .tracking(2.3)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private func switchMode() {
        errorMessage = nil
        withAnimation(.easeOut(duration: 0.18)) {
            mode = isRegistering ? .login : .register
        }
    }

    private func submit() async {
        guard !isSubmitting else { return }
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if isRegistering, cleanUsername.count < 3 || cleanUsername.count > 32 {
            errorMessage = L10n.auth.usernameLength
            focusedField = .username
            return
        }
        if !cleanEmail.contains("@") {
            errorMessage = L10n.auth.invalidEmail
            focusedField = .email
            return
        }
        if password.count < 8 {
            errorMessage = L10n.auth.passwordTooShort
            focusedField = .password
            return
        }

        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            if isRegistering {
                try await auth.signUp(username: cleanUsername, email: cleanEmail, password: password)
            } else {
                try await auth.signIn(email: cleanEmail, password: password)
            }
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        guard let apiError = error as? APIError else {
            return error.localizedDescription
        }
        switch apiError {
        case .serverError(let code, let message):
            if code == 40103 || code == 40400 {
                return L10n.auth.wrongCredentials
            }
            if code == 40901 {
                return L10n.auth.alreadyTaken
            }
            if code == 40001 {
                return L10n.auth.checkFields
            }
            return message
        case .networkError:
            return L10n.auth.networkError
        case .decodingError:
            return L10n.auth.badResponse
        default:
            return apiError.localizedDescription
        }
    }
}

private struct AuthInputField: View {
    let icon: String
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.mono10)
                .tracking(1.4)
                .foregroundStyle(Color.muted)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.muted)
                    .frame(width: 16)
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.ink)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.paper2.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.hair, lineWidth: 1)
            )
        }
    }
}
