import SwiftUI

struct UserBarView: View {
    let auth: AuthService

    var body: some View {
        HStack(spacing: 10) {
            if auth.isLoggedIn, let user = auth.user {
                AsyncImage(url: URL(string: user.avatarURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                Text(user.nickname.isEmpty ? user.username : user.nickname)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 13))
                    Text("\(user.coins)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }

                Button {
                    auth.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Sign Out")

            } else {
                Image(systemName: "person.circle")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)

                Text("Not signed in")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Sign In") {
                    auth.login()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
