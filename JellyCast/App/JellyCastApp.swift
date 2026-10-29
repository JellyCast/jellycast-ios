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
    @State private var usage = UsageStatistics.shared
    @Environment(\.scenePhase) private var scenePhase

    private static let splashFadeOut = 0.2

    var body: some View {
        ZStack {
            // Asked before the app itself appears, so nothing it presents can cover the question.
            if usage.needsChoice {
                UsageConsentScreen { choice in
                    withAnimation(.easeOut(duration: Self.splashFadeOut)) { usage.choose(choice) }
                }
                .transition(.opacity)
            } else if let library = app.library {
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
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            async let ping: Void = usage.appOpened()
            async let ads: Void = AdPlacements.shared.refresh()
            _ = await (ping, ads)
        }
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
