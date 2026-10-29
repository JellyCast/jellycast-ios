import SwiftUI

@main
struct JellyCastApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        _ = AppLaunch.startedAt
        DownloadStore.shared.attach()
        RemotePlaybackActivity.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

enum AppLaunch {
    static let startedAt = ContinuousClock.now
}

struct RootView: View {
    @State private var app = AppModel()
    @State private var showsSplash = true

    private static let splashFadeOut = 0.2

    var body: some View {
        ZStack {
            if let library = app.library {
                MainView(store: library) { app.signOut() }
                    .id(library.session.accessToken)
                    .environment(\.isSplashShowing, showsSplash)
                    .onChange(of: library.isSessionExpired) { _, expired in
                        if expired { app.signOut() }
                    }
            } else {
                SignInScreen(model: SignInModel { app.signIn($0) })
            }
            if showsSplash {
                BrandSplash {
                    withAnimation(.easeOut(duration: Self.splashFadeOut)) { showsSplash = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background(JellyCastColors.background)
    }
}

extension EnvironmentValues {
    @Entry var isSplashShowing = false
}

@Observable
final class AppModel {
    private(set) var library: LibraryStore?

    init() {
        library = SessionStorage.load().map { LibraryStore(session: $0) }
    }

    func signIn(_ session: Session) {
        library = LibraryStore(session: session)
    }

    func signOut() {
        guard let session = library?.session else { return }
        library = nil
        Task { await RemotePlaybackActivity.shared.endAll() }
        SessionStorage.delete()
        ActiveServerAddress.set(nil)
        LibraryCache.delete()
        Task { await session.client.signOut() }
    }
}
