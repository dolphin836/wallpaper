import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The Mac-only "Settings" tab inside AccountView. Folds the old
// SettingsView sections (appearance / wallpaper / storage / session)
// together with the account editing the web keeps in its profile
// header: nickname + bio, avatar upload, password change, and the
// likes/favorites/downloads visibility toggles.
struct AccountSettingsTab: View {
    @State private var auth = AuthService.shared
    @State private var manager = WallpaperManager.shared
    @AppStorage(AppearancePref.storageKey) private var appearanceRaw: String = AppearancePref.system.rawValue

    // Profile edit
    @State private var editingProfile = false
    @State private var editNickname = ""
    @State private var editBio = ""
    @State private var savingProfile = false

    // Password
    @State private var showPassword = false
    @State private var oldPw = ""
    @State private var newPw = ""
    @State private var savingPw = false
    @State private var pwError: String?

    // Privacy toggles (mirror the user's current settings; optimistic)
    @State private var likesPublic = false
    @State private var favoritesPublic = false
    @State private var downloadsPublic = false

    @State private var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            profileSection
            privacySection
            appearanceSection
            wallpaperSection
            storageSection
            sessionSection
            if let t = toast {
                Text(t).font(.system(size: 11)).foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .sheet(isPresented: $showPassword) { passwordSheet }
    }

    // ─── Profile (nickname / bio / avatar) ───────────────────────
    private var profileSection: some View {
        sectionCard(title: "Profile") {
            if let u = auth.user {
                HStack(alignment: .top, spacing: 16) {
                    avatarView(u).frame(width: 72, height: 72).clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.hair, lineWidth: 1))
                        .overlay(alignment: .bottomTrailing) {
                            Button(action: pickAvatar) {
                                Image(systemName: "camera.fill").font(.system(size: 10))
                                    .foregroundStyle(Color.paper).frame(width: 26, height: 26)
                                    .background(Circle().fill(Color.ink))
                                    .overlay(Circle().strokeBorder(Color.paper, lineWidth: 2))
                            }
                            .buttonStyle(.plain).pointerCursor()
                        }

                    if editingProfile {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Nickname", text: $editNickname)
                                .textFieldStyle(.roundedBorder).font(.system(size: 15))
                            TextField("Bio", text: $editBio, axis: .vertical)
                                .textFieldStyle(.roundedBorder).font(.system(size: 13)).lineLimit(3, reservesSpace: true)
                            HStack(spacing: 8) {
                                Button(action: { Task { await saveProfile() } }) {
                                    Text(savingProfile ? "Saving…" : "Save").font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.paper).padding(.horizontal, 16).padding(.vertical, 7)
                                        .background(Capsule().fill(Color.ink))
                                }.buttonStyle(.plain).disabled(savingProfile).pointerCursor()
                                Button(action: { editingProfile = false }) {
                                    Text("Cancel").font(.system(size: 12)).foregroundStyle(Color.ink2)
                                        .padding(.horizontal, 16).padding(.vertical, 7)
                                        .background(Capsule().strokeBorder(Color.hair, lineWidth: 1))
                                }.buttonStyle(.plain).pointerCursor()
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(u.nickname.isEmpty ? u.username : u.nickname)
                                .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.ink)
                            Text("@\(u.username)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted)
                            if !u.bio.isEmpty {
                                Text(u.bio).font(.system(size: 12)).foregroundStyle(Color.ink2).padding(.top, 2)
                            }
                        }
                        Spacer()
                        VStack(spacing: 6) {
                            Button("Edit profile") {
                                editNickname = u.nickname; editBio = u.bio; editingProfile = true
                            }.controlSize(.small)
                            Button("Password") { showPassword = true }.controlSize(.small)
                        }
                    }
                }
            } else {
                HStack {
                    Text("Not signed in.").font(.system(size: 13)).foregroundStyle(Color.muted)
                    Spacer()
                    Button("Sign in") { auth.login() }.buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // ─── Privacy (likes / favorites / downloads visibility) ──────
    private var privacySection: some View {
        sectionCard(title: "List visibility") {
            VStack(alignment: .leading, spacing: 10) {
                privacyToggle("Public likes", isOn: $likesPublic) { v in Task { try? await APIClient.shared.updatePrivacy(likesPublic: v) } }
                privacyToggle("Public favorites", isOn: $favoritesPublic) { v in Task { try? await APIClient.shared.updatePrivacy(favoritesPublic: v) } }
                privacyToggle("Public downloads", isOn: $downloadsPublic) { v in Task { try? await APIClient.shared.updatePrivacy(downloadsPublic: v) } }
                Text("When off, only you can see these lists on your profile.")
                    .font(.system(size: 11)).foregroundStyle(Color.muted)
            }
        }
    }
    private func privacyToggle(_ label: String, isOn: Binding<Bool>, onChange: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn.wrappedValue }, set: { v in isOn.wrappedValue = v; onChange(v) })) {
            Text(label).font(.system(size: 13)).foregroundStyle(Color.ink)
        }
        .toggleStyle(.switch).tint(Color.accent)
    }

    // ─── Appearance ──────────────────────────────────────────────
    private var appearanceSection: some View {
        sectionCard(title: "Appearance") {
            HStack(spacing: 8) {
                ForEach(AppearancePref.allCases, id: \.self) { pref in
                    let isOn = appearanceRaw == pref.rawValue
                    Button(action: { appearanceRaw = pref.rawValue }) {
                        HStack(spacing: 6) {
                            Image(systemName: pref.icon).font(.system(size: 11, weight: .medium))
                            Text(pref.label).font(.system(size: 12, weight: isOn ? .semibold : .regular))
                        }
                        .foregroundStyle(isOn ? Color.accent : Color.ink2)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? Color.accent.opacity(0.12) : Color.paper2))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isOn ? Color.accent.opacity(0.35) : Color.hair, lineWidth: 1))
                    }.buttonStyle(.plain).pointerCursor()
                }
            }
        }
    }

    private var wallpaperSection: some View {
        sectionCard(title: "Wallpaper") {
            Toggle(isOn: Binding(get: { manager.autoRotate }, set: { manager.setAutoRotate($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-shuffle").font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text("Switch to a random downloaded wallpaper every 4 hours")
                        .font(.system(size: 11)).foregroundStyle(Color.muted)
                }
            }.toggleStyle(.switch).tint(Color.accent)
        }
    }

    private var storageSection: some View {
        sectionCard(title: "Storage") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloads folder").font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text(manager.storageDir.path).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Reveal in Finder") {
                    try? FileManager.default.createDirectory(at: manager.storageDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(manager.storageDir)
                }
            }
        }
    }

    private var sessionSection: some View {
        sectionCard(title: "Session") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign out").font(.system(size: 13)).foregroundStyle(Color.ink)
                    Text("Clear local session and return to the sign-in screen")
                        .font(.system(size: 11)).foregroundStyle(Color.muted)
                }
                Spacer()
                Button("Sign out", role: .destructive) { auth.logout() }
            }
        }
    }

    // ─── Password sheet ──────────────────────────────────────────
    private var passwordSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CHANGE PASSWORD").font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(Color.muted)
            SecureField("Current password", text: $oldPw).textFieldStyle(.roundedBorder)
            SecureField("New password (min 8 chars)", text: $newPw).textFieldStyle(.roundedBorder)
            if let e = pwError { Text(e).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { showPassword = false; oldPw = ""; newPw = ""; pwError = nil }
                Button(savingPw ? "Saving…" : "Confirm") { Task { await changePassword() } }
                    .buttonStyle(.borderedProminent).disabled(savingPw || newPw.count < 8)
            }
        }
        .padding(24).frame(width: 360)
    }

    // ─── Actions ─────────────────────────────────────────────────
    private func saveProfile() async {
        savingProfile = true; defer { savingProfile = false }
        do {
            _ = try await APIClient.shared.updateProfile(nickname: editNickname, bio: editBio)
            await auth.refreshProfile()
            editingProfile = false
            toast = "Profile updated."
        } catch { toast = error.localizedDescription }
    }

    private func changePassword() async {
        guard newPw.count >= 8 else { pwError = "New password must be at least 8 characters."; return }
        savingPw = true; defer { savingPw = false }
        do {
            try await APIClient.shared.changePassword(old: oldPw, new: newPw)
            showPassword = false; oldPw = ""; newPw = ""; pwError = nil
            toast = "Password changed."
        } catch { pwError = error.localizedDescription }
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        let mime = url.pathExtension.lowercased() == "png" ? "image/png" : (url.pathExtension.lowercased() == "webp" ? "image/webp" : "image/jpeg")
        Task {
            do {
                _ = try await APIClient.shared.uploadAvatar(imageData: data, filename: url.lastPathComponent, mime: mime)
                await auth.refreshProfile()
                toast = "Avatar updated."
            } catch { toast = error.localizedDescription }
        }
    }

    @ViewBuilder private func avatarView(_ user: User) -> some View {
        let initial = String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)).uppercased()
        if !user.avatarURL.isEmpty, let url = URL(string: user.avatarURL) {
            CachedAsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fill) }
            placeholder: { ZStack { Color.paper2; Text(initial).font(.displayMd).foregroundStyle(Color.ink) } }
        } else {
            ZStack { Color.paper2; Text(initial).font(.displayMd).foregroundStyle(Color.ink) }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.5).foregroundStyle(Color.muted).padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.paper.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.hair, lineWidth: 1))
        }
    }
}
