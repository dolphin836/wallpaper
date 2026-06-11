import SwiftUI

@main
struct WallpaperExchangeApp: App {
    @State private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(auth)
                .task {
                    // Hydrate the profile behind a persisted token so the
                    // Account tab doesn't show "Not signed in" while a
                    // valid session exists.
                    await auth.refreshProfile()
                }
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles.rectangle.stack") }
            WeeklyView()
                .tabItem { Label("Weekly", systemImage: "calendar") }
            CollectionsView()
                .tabItem { Label("Collections", systemImage: "rectangle.stack") }
            UploadView()
                .tabItem { Label("Upload", systemImage: "plus.circle") }
            AccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}
