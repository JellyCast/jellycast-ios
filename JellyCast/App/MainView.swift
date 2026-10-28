import SwiftUI

/// The signed-in app: Home and Library (with search).
struct MainView: View {
    let store: LibraryStore
    let onSignOut: () -> Void

    @State private var navigation = AppNavigation()
    @State private var search = SearchModel()
    @State private var nowPlaying = NowPlaying()
    @State private var remote: RemoteSessions
    @State private var lists: ListsStore
    @State private var screenShortSide: CGFloat = 0
    @State private var hasCheckedServer = false
    @State private var hasBeenActive = false
    /// Set while this open still waits to decide on the now playing screen of a TV.
    @State private var openedAt: ContinuousClock.Instant?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layout) private var layout
    @Environment(\.isSplashShowing) private var isSplashShowing

    private static let miniPlayerBottomInset: CGFloat = 72
    /// The iPad draws the tab bar at the top, so only the margin is left at the bottom.
    private static let miniPlayerBottomInsetRegular: CGFloat = 16
    private static let tvBarHeight: CGFloat = 56
    /// On the iPad the TV bar floats higher above the bottom edge than above the iPhone's tab bar.
    private static let tvBarHeightRegular: CGFloat = 88
    private static let miniPlayerMargin: CGFloat = 16
    private static let miniPlayerWidthsRegular: (small: CGFloat, large: CGFloat) = (320, 480)

    init(store: LibraryStore, onSignOut: @escaping () -> Void) {
        self.store = store
        self.onSignOut = onSignOut
        _remote = State(initialValue: RemoteSessions(client: store.session.client, userID: store.session.userID))
        _lists = State(initialValue: ListsStore(session: store.session))
    }

    var body: some View {
        @Bindable var navigation = navigation
        @Bindable var nowPlaying = nowPlaying
        TabView(selection: $navigation.tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: $navigation.homePath) {
                    HomeScreen(store: store).routes(store: store)
                }
            }
            Tab("Library", systemImage: "square.stack", value: AppTab.library) {
                NavigationStack(path: $navigation.libraryPath) {
                    LibraryScreen(store: store, search: search).routes(store: store)
                }
            }
            Tab("Downloads", systemImage: "arrow.down.circle", value: AppTab.downloads) {
                NavigationStack(path: $navigation.downloadsPath) {
                    DownloadsScreen(store: store).routes(store: store)
                }
            }
        }
        .bottomBar(remote.current, download: navigation.tab == .downloads ? nil : DownloadStore.shared.current) {
            remote.show($0)
        } onOpenDownloads: {
            navigation.tab = .downloads
        }
        .tint(JellyCastColors.accent)
        .environment(navigation)
        .environment(remote)
        .environment(store)
        .environment(lists)
        .environment(\.jellyfinClient, store.session.client)
        .environment(\.isOffline, isOffline)
        .sheet(item: $navigation.addToListRequest) { request in
            AddToListSheet(request: request)
                .environment(lists)
                .environment(\.jellyfinClient, store.session.client)
        }
        .alert(
            "The list wasn't changed",
            isPresented: Binding(
                get: { lists.changeError != nil },
                set: { if !$0 { lists.changeError = nil } }
            )
        ) {} message: {
            Text(lists.changeError ?? "")
        }
        .remotePlaybackActivity(remote, client: store.session.client)
        .task { await store.start() }
        .task { await checkServerAtStart() }
        .task(id: store.index == nil) {
            guard store.index != nil else { return }
            await DownloadStore.shared.start(library: store)
        }
        .task(id: store.snapshot?.syncedAt) {
            guard let index = store.index, DownloadStore.shared.isStarted else { return }
            await DownloadStore.shared.tidy(index: index)
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else {
                openedAt = nil
                return
            }
            openedAt = .now
            async let check: Void = recheckServer()
            await remote.poll()
            await check
        }
        .overlay(alignment: .bottomTrailing) { miniPlayer }
        .overlay(alignment: .bottom) { wakingStatus }
        .alert(
            "The TV didn't get that",
            isPresented: Binding(
                get: { remote.commandFailed && remote.shownSessionID == nil },
                set: { if !$0 { remote.dismissCommandFailure() } }
            )
        ) {}
        .onGeometryChange(for: CGFloat.self) { min($0.size.width, $0.size.height) } action: { screenShortSide = $0 }
        .fullScreenCover(isPresented: $nowPlaying.isExpanded) {
            if let session = nowPlaying.session {
                PlayerScreen(nowPlaying: nowPlaying, session: session, engine: session.engine, store: store)
                    .environment(remote)
            }
        }
        .onChange(of: navigation.playRequest) { _, playable in
            guard let playable else { return }
            navigation.playRequest = nil
            nowPlaying.play(playable, store: store, streams: navigation.playStreams, queue: navigation.playQueue)
            navigation.playStreams = nil
            navigation.playQueue = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { nowPlaying.pip.stopIfActive() }
        }
        .onChange(of: remote.answeredAt) { showTVNowPlayingAtOpen() }
        .onChange(of: isSplashShowing) { showTVNowPlayingAtOpen() }
        .alert(
            nowPlaying.startError ?? "",
            isPresented: Binding(
                get: { nowPlaying.startError != nil },
                set: { if !$0 { nowPlaying.dismissStartError() } }
            )
        ) {}
        .alert(
            store.serverProblem == .offline
                ? LocalizedStringKey("You're offline.") : "Can't reach \(store.session.serverName)",
            isPresented: Binding(
                get: { store.serverProblem != nil && !nowPlaying.isExpanded },
                set: { if !$0 { store.dismissServerProblem() } }
            )
        ) {
            Button("Try again") {
                Task {
                    await store.checkServer()
                    if store.serverProblem == nil { await store.refresh() }
                }
            }
            Button("Connect to another server") { onSignOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if DownloadStore.shared.finished.isEmpty {
                Text("What you see is from your last visit; nothing plays until the server answers.")
            } else {
                Text("What you see is from your last visit; only your downloads play until the server answers.")
            }
        }
        .onChange(of: NetworkMonitor.shared.isOnline) { _, online in
            Task {
                await store.checkServer(reportsProblem: false)
                if online, store.syncFailure != nil { await store.refresh() }
            }
        }
        .sheet(isPresented: $navigation.showsSettings) {
            SettingsScreen(store: store, onSignOut: onSignOut)
                .environment(navigation)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { remote.shownSessionID != nil },
                set: { if !$0 { remote.shownSessionID = nil } }
            )
        ) {
            if let sessionID = remote.shownSessionID {
                RemoteNowPlayingScreen(
                    remote: remote, sessionID: sessionID, store: store,
                    onOpen: { navigation.open($0) },
                    onPlayHere: { navigation.play($0, streams: $1) }
                )
            }
        }
    }
}

private extension MainView {
    /// No network on the device counts at once, before the server check answers.
    var isOffline: Bool {
        store.isServerUnreachable || !NetworkMonitor.shared.isOnline
    }

    /// Opened without the server and with something downloaded: start on Downloads instead of
    /// an alert over a library that won't play. Runs once, apart from the scene phase, so a
    /// system prompt at launch can't cancel it.
    func checkServerAtStart() async {
        let problem = await store.checkServer(reportsProblem: false)
        guard !Task.isCancelled else { return }
        hasCheckedServer = true
        guard let problem else { return }
        let isAtStart = navigation.tab == .home && navigation.homePath.isEmpty
        if isAtStart, !DownloadStore.shared.finished.isEmpty {
            navigation.tab = .downloads
        } else {
            store.report(problem)
        }
    }

    /// Each return to the app; the launch itself is `checkServerAtStart`.
    func recheckServer() async {
        guard hasBeenActive else {
            hasBeenActive = true
            return
        }
        await store.checkServer()
    }

    /// Waits for the first answer after opening and for the splash, then decides once.
    func showTVNowPlayingAtOpen() {
        guard let openedAt, !isSplashShowing,
              let answeredAt = remote.answeredAt, answeredAt >= openedAt
        else { return }
        self.openedAt = nil
        let session = NowPlayingAtOpen.session(
            remote.current,
            answeredAfter: answeredAt - openedAt,
            isPlayingHere: nowPlaying.session != nil,
            isPresenting: remote.shownSessionID != nil || UIApplication.shared.isPresentingOverRoot
        )
        if let session { remote.show(session) }
    }

    @ViewBuilder
    var wakingStatus: some View {
        if let name = remote.waking {
            HStack(spacing: 10) {
                ProgressView().tint(JellyCastColors.text)
                Text("Turning on \(name)…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JellyCastColors.text)
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, baseBottomInset + tvBarInset)
            .transition(.opacity)
        }
    }

    var baseBottomInset: CGFloat {
        layout.isRegular ? Self.miniPlayerBottomInsetRegular : Self.miniPlayerBottomInset
    }

    var tvBarInset: CGFloat {
        layout.isRegular ? Self.tvBarHeightRegular : Self.tvBarHeight
    }

    /// Above the tab bar and, while it shows, the TV bar.
    var bottomInset: CGFloat {
        baseBottomInset + (remote.current == nil ? 0 : tvBarInset)
    }

    var miniPlayerWidth: CGFloat {
        if layout.isRegular {
            return nowPlaying.isMiniPlayerLarge ? Self.miniPlayerWidthsRegular.large : Self.miniPlayerWidthsRegular.small
        }
        return nowPlaying.isMiniPlayerLarge ? screenShortSide - 2 * Self.miniPlayerMargin : MiniPlayer.smallWidth
    }

    @ViewBuilder
    var miniPlayer: some View {
        if let session = nowPlaying.session {
            ZStack {
                NowPlayingObserver(nowPlaying: nowPlaying, session: session, engine: session.engine)
                if !nowPlaying.isExpanded {
                    MiniPlayer(
                        nowPlaying: nowPlaying, session: session, engine: session.engine,
                        width: miniPlayerWidth
                    )
                        .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .padding(.trailing, Self.miniPlayerMargin)
            .padding(.bottom, bottomInset)
            .animation(.easeOut(duration: 0.2), value: nowPlaying.isExpanded)
        }
    }
}

private extension UIApplication {
    /// A sheet, cover or alert anywhere in the app, also those presented by a child view.
    var isPresentingOverRoot: Bool {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.rootViewController?.presentedViewController != nil }
    }
}

private extension View {
    /// What plays on a TV, else the running download. `isEnabled` came with iOS 26.1; on 26.0
    /// the bar stays off.
    @ViewBuilder
    func bottomBar(
        _ session: RemoteSession?, download: Download?,
        onOpen: @escaping (RemoteSession) -> Void, onOpenDownloads: @escaping () -> Void
    ) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: session != nil || download != nil) {
                if let session {
                    TVBar(session: session) { onOpen(session) }
                } else if let download {
                    DownloadAccessory(
                        download: download, secondsLeft: DownloadStore.shared.secondsLeft(download),
                        onOpen: onOpenDownloads
                    )
                }
            }
        } else {
            self
        }
    }

    func routes(store: LibraryStore) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .series(let id): SeriesScreen(store: store, seriesID: id)
            case .movie(let id): MovieScreen(store: store, movieID: id)
            case .person(let person): PersonScreen(store: store, person: person)
            case .downloadedSeries(let id): DownloadedSeriesScreen(store: store, seriesID: id)
            case .lists: ListsScreen(store: store)
            case .list(let id): ListScreen(store: store, listID: id)
            }
        }
    }
}
