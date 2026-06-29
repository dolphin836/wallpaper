import SwiftUI
import AppKit

// MARK: - Header

struct PopoverHeaderView: View {
    let auth: AuthService

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // ─── Identity cluster (left) ───
            HStack(spacing: 12) {
                avatar
                if auth.isLoggedIn, let user = auth.user {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.nickname.isEmpty ? user.username : user.nickname)
                            .font(.displayMd)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Text("@\(user.username)")
                            .font(.monoCaps)
                            .tracking(0.6)
                            .foregroundStyle(Color.muted)
                    }
                } else {
                    Text(L10n.shell.notSignedIn)
                        .font(.sans12)
                        .foregroundStyle(Color.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // ─── Coin pill (center) — only when logged in ───
            if auth.isLoggedIn, let user = auth.user {
                coinPill(coins: user.coins)
            } else {
                Button(L10n.shell.signIn) { auth.login() }
                    .controlSize(.small)
            }

            // ─── Logout (right) ───
            if auth.isLoggedIn {
                Button(action: { auth.logout() }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.ink2)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().stroke(Color.hair, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(L10n.settings.signOut)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder private var avatar: some View {
        if auth.isLoggedIn, let user = auth.user, !user.avatarURL.isEmpty,
           let url = URL(string: user.avatarURL) {
            CachedAsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                avatarFallback
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.hair, lineWidth: 1))
        } else {
            avatarFallback
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(Color.hair, lineWidth: 1))
                .clipShape(Circle())
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Color.paper2
            Text(initial)
                .font(.displayMd)
                .foregroundStyle(Color.ink)
        }
    }

    private var initial: String {
        let name = auth.user?.nickname.isEmpty == false
            ? auth.user!.nickname
            : (auth.user?.username ?? "?")
        return String(name.prefix(1)).uppercased()
    }

    // The only place accent-orange appears at rest in the popover — signals
    // that this is the value/currency moment. Ink pill background with a
    // minted-coin glyph to the left and a mono digit count.
    private func coinPill(coins: Int) -> some View {
        MiniCoinPill(coins: coins)
    }
}

// MARK: - Footer

struct PopoverFooterView: View {
    let onOpenWeb: () -> Void
    // Total bytes occupied by the local downloads folder. Rendered as
    // mono caps next to the version. 0 means a fresh install with no
    // downloads yet — surface as "—" so the user sees the slot exists
    // rather than being puzzled by "0 B".
    let localStorageBytes: Int64

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v \(short)"
    }

    private var storageString: String {
        if localStorageBytes <= 0 { return "—" }
        return Self.bytesFormatter.string(fromByteCount: localStorageBytes)
    }

    private static let bytesFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label {
                    Text(L10n.shell.quitApp).font(.sans12)
                } icon: {
                    Image(systemName: "power").font(.system(size: 13))
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.ink2)
            }
            .buttonStyle(.plain)

            Button(action: onOpenWeb) {
                Label {
                    Text(L10n.manager.openInBrowser).font(.sans12)
                } icon: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 13))
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.ink2)
            }
            .buttonStyle(.plain)

            Spacer()

            // Storage indicator + version, separated by a vertical hairline
            // so they read as two distinct facts rather than one long string.
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.muted)
                    Text(storageString)
                        .font(.monoCaps)
                        .tracking(0.6)
                        .foregroundStyle(Color.muted)
                        .help(L10n.manager.localDiskUsedHelp)
                }
                Rectangle().fill(Color.hair).frame(width: 1, height: 12)
                Text(versionString)
                    .font(.monoCaps)
                    .tracking(1.0)
                    .foregroundStyle(Color.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.45))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.hair).frame(height: 1)
        }
    }
}

// MARK: - Filter toggle pill (icon only)

// 24px circular icon-only button used for column-heading filters and
// quick actions. Active state is accent-orange; resting state shows a
// thin hairline ring. Hover state darkens the icon and fills the
// background paper-2, so the user gets immediate visual feedback that
// the icon is interactive in addition to the .help() tooltip.
struct FilterTogglePill: View {
    let icon: String
    let help: String
    let isOn: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(backgroundFill))
                .overlay(Circle().stroke(borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(help)
    }

    private var foregroundColor: Color {
        if isOn { return .white }
        return isHovering ? Color.ink : Color.muted
    }
    private var backgroundFill: Color {
        if isOn { return Color.accent }
        return isHovering ? Color.paper2 : .clear
    }
    private var borderColor: Color {
        if isOn { return .clear }
        return isHovering ? Color.ink2 : Color.hair
    }
}

// MARK: - Shuffle status banner

struct ShuffleStatusBanner: View {
    // nil → never scheduled (shouldn't normally happen while the banner is
    // visible, but defensive). Otherwise the absolute moment of the next
    // rotation tick; the banner derives the H/M countdown from it.
    let nextAt: Date?
    let intervalText: String

    // Re-render once a minute so the countdown stays roughly accurate
    // without burning CPU. The underlying timer fires for the lifetime of
    // the banner, which only exists while shuffle is on.
    @State private var now: Date = Date()
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.accent)
                Image(systemName: "shuffle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)

            Text(message)
                .font(.sans12)
                .foregroundStyle(Color.accentInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Text(countdown)
                .font(.monoCaps)
                .tracking(0.6)
                .foregroundStyle(Color.accentInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color.accentSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.804, green: 0.671, blue: 0.388), lineWidth: 1)
        )
        .onReceive(tick) { now = $0 }
    }

    private var message: AttributedString {
        var bold = AttributedString(L10n.manager.autoShuffleBannerTitle)
        bold.font = .system(size: 12, weight: .semibold)
        var rest = AttributedString(L10n.manager.autoShuffleBannerMessage(intervalText))
        rest.font = .sans12
        return bold + rest
    }

    private var countdown: String {
        guard let nextAt else { return L10n.manager.autoShuffleNextUnknown }
        let secs = max(0, Int(nextAt.timeIntervalSince(now)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return L10n.manager.autoShuffleNext(h, m)
    }
}
