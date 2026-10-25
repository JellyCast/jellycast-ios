import Foundation

/// What plays on the user's other devices, kept current while the app is in the foreground.
@Observable
final class RemoteSessions {
    private(set) var sessions: [RemoteSession] = []
    /// TV apps that take a "play" right now.
    private(set) var devices: [RemoteDevice] = []
    let names = DeviceNames()
    let paired = PairedTVs()
    private(set) var commandFailed = false
    /// The TV being woken and started right now, for a status on screen.
    private(set) var waking: String?
    /// The session the now playing screen shows; it stays open when that playback stops.
    var shownSessionID: String?
    /// The TV behind `shownSessionID`: its next episode can come back under another session.
    private var shownDeviceID: String?

    private let client: JellyfinClient
    private let userID: String
    private var failuresInARow = 0

    private static let pollInterval = Duration.seconds(5)
    /// The TV app reports straight after a command; the server needs a moment to have it.
    private static let reportDelay = Duration.milliseconds(800)
    private static let nextItemDelay = Duration.seconds(2)
    /// A few missed polls keep the bar: one slow answer from the server shouldn't hide it.
    private static let failuresBeforeClearing = 3
    private static let deviceActivityWindowSeconds = 150.0

    init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
    }

    /// The one the TV bar shows: the most recently reported.
    var current: RemoteSession? { sessions.first }

    func session(id: String) -> RemoteSession? {
        sessions.first { $0.id == id }
    }

    func show(_ session: RemoteSession) {
        shownSessionID = session.id
        shownDeviceID = session.deviceID
    }

    /// Shows the result right away and corrects it with the TV's own report shortly after.
    func send(_ command: RemoteCommand, to sessionID: String) async {
        apply(command, to: sessionID)
        do {
            try await client.send(command, toSession: sessionID)
        } catch is CancellationError {
            return
        } catch {
            commandFailed = true
        }
        try? await Task.sleep(for: Self.reportDelay)
        await refresh()
        // Between two items the TV has stopped one and not yet started the next.
        guard command.changesItem, session(id: sessionID) == nil else { return }
        try? await Task.sleep(for: Self.nextItemDelay)
        await refresh()
    }

    func dismissCommandFailure() {
        commandFailed = false
    }

    private func apply(_ command: RemoteCommand, to sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var session = sessions[index]
        let now = Date.now
        session.positionTicks = session.position(at: now)
        session.checkedInAt = now
        switch command {
        case .pause: session.isPaused = true
        case .unpause: session.isPaused = false
        case .stop, .nextEpisode, .play: break
        case .seek(let ticks): session.positionTicks = ticks
        case .audioStream(let index): session.audioStreamIndex = index
        case .subtitleStream(let index): session.subtitleStreamIndex = index
        }
        sessions[index] = session
    }

    /// Polls until cancelled; run it only while the app is in the foreground.
    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func refresh() async {
        do {
            let now = Date.now
            let snapshot = try await client.userSessions(userID: userID)
            sessions = snapshot.playing.filter { !$0.isSilent(at: now) }.map(named)
            followShownDevice()
            devices = snapshot.devices.filter { isRecent($0, at: now) }.map(named)
            for device in devices {
                if let address = device.address { paired.update(deviceID: device.deviceID, host: address) }
            }
            failuresInARow = 0
        } catch is CancellationError {
            return
        } catch {
            failuresInARow += 1
            if failuresInARow >= Self.failuresBeforeClearing {
                sessions = []
                devices = []
            }
        }
    }

    /// The now playing screen stays with its TV when that plays on under a new session.
    private func followShownDevice() {
        guard let shownSessionID, session(id: shownSessionID) == nil,
              let next = sessions.first(where: { $0.deviceID == shownDeviceID })
        else { return }
        self.shownSessionID = next.id
    }

    /// Paired TVs the iPhone can reach directly right now, checked when the sheet opens.
    private(set) var reachableTVs: Set<String> = []
    private(set) var hasCheckedReachability = false

    func checkReachability() async {
        var reachable: Set<String> = []
        await withTaskGroup(of: (String, Bool).self) { group in
            for tv in paired.all {
                group.addTask { (tv.deviceID, await AndroidTVRemote.isReachable(host: tv.host)) }
            }
            for await (deviceID, isReachable) in group where isReachable {
                reachable.insert(deviceID)
            }
        }
        reachableTVs = reachable
        hasCheckedReachability = true
    }

    var wakeableTVs: [PairedTV] {
        sleepingTVs.filter { reachableTVs.contains($0.deviceID) }
    }

    /// TVs to offer with JellyCast open. A paired one always goes through the remote route,
    /// which needs a direct connection, so it only shows once the probe reached it.
    var playableDevices: [RemoteDevice] {
        devices.filter { !paired.contains($0.deviceID) || reachableTVs.contains($0.deviceID) }
    }

    /// After the probe: a paired TV that can't be reached from this network.
    var hasUnreachablePairedTV: Bool {
        hasCheckedReachability && paired.all.contains { !reachableTVs.contains($0.deviceID) }
    }

    /// Paired TVs whose JellyCast isn't open: they can only be woken.
    var sleepingTVs: [PairedTV] {
        paired.all
            .filter { tv in !devices.contains { $0.deviceID == tv.deviceID } }
            .map { tv in
                var tv = tv
                tv.name = names.name(for: tv.deviceID, fallback: tv.name)
                return tv
            }
    }

    /// Android TVs with JellyCast open that aren't paired yet.
    var pairableTVs: [RemoteDevice] {
        devices.filter { $0.isAndroidTV && $0.address != nil && !paired.contains($0.deviceID) }
    }

    /// After "Continue on iPhone": stop the TV, and turn a paired Chromecast off when it can be
    /// reached; an LG only stops.
    func handBack(_ session: RemoteSession) async {
        await send(.stop, to: session.id)
        guard let tv = paired.all.first(where: { $0.deviceID == session.deviceID }) else { return }
        try? await AndroidTVRemote.turnOff(host: tv.host)
    }

    func wakeAndPlay(_ tv: PairedTV, itemID: String, startTicks: Int64, streams: StreamSelection? = nil) async {
        var link = "jellycast://play?item=\(itemID)&start=\(startTicks / (Ticks.perSecond / 1000))"
        if let audio = streams?.audio { link += "&audio=\(audio)" }
        if let subtitle = streams?.subtitle { link += "&subtitle=\(subtitle)" }
        waking = tv.name
        defer { waking = nil }
        do {
            try await AndroidTVRemote.wakeAndOpen(host: tv.host, link: link)
        } catch is CancellationError {
            return
        } catch {
            commandFailed = true
        }
    }

    func rename(deviceID: String, to name: String) {
        names.rename(deviceID, to: name)
        devices = devices.map(named)
        sessions = sessions.map(named)
    }

    /// The server keeps a closed app's session for minutes. An open TV app reports itself every
    /// minute (the WebSocket keep-alive doesn't count as activity), so two missed reports mean closed.
    private func isRecent(_ device: RemoteDevice, at date: Date) -> Bool {
        guard let lastActivity = device.lastActivity else { return false }
        return date.timeIntervalSince(lastActivity) < Self.deviceActivityWindowSeconds
    }

    private func named(_ session: RemoteSession) -> RemoteSession {
        var session = session
        session.deviceName = names.name(for: session.deviceID, fallback: session.deviceName)
        return session
    }

    private func named(_ device: RemoteDevice) -> RemoteDevice {
        var device = device
        device.name = names.name(for: device.deviceID, fallback: device.name)
        return device
    }
}
