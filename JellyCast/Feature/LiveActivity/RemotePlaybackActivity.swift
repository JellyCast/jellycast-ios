import ActivityKit
import Foundation

/// Keeps one Live Activity in step with the TV the TV bar shows. Without a push server it can
/// only be updated while the app runs; the timers and the stale date cover the time in between.
final class RemotePlaybackActivity {
    static let shared = RemotePlaybackActivity()

    private weak var remote: RemoteSessions?
    private let artwork = RemotePlaybackArtwork()
    private var updating: Task<Void, Never>?

    private typealias State = RemotePlaybackAttributes.ContentState

    /// A playing item counts as ended a little after its runtime, so a late report isn't stale.
    private static let endGraceSeconds = 60.0
    /// A pause can end on the TV's own remote, which the activity can't see while the app sleeps.
    private static let pausedStaleSeconds = 30.0 * 60
    private static let unknownRuntimeStaleSeconds = 30.0 * 60
    /// Polls land a little apart; smaller drifts are not worth an update.
    private static let driftToleranceSeconds = 2.0

    /// Sets up the buttons; call at launch, also when the system launches the app for a button.
    static func install() {
        RemotePlaybackActions.perform = { await shared.perform($0) }
    }

    func attach(_ remote: RemoteSessions) {
        self.remote = remote
    }

    /// Call with the TV bar's session after every sessions answer; nil ends the activity.
    /// Updates run one after another, so two answers close together can't start two activities.
    func show(_ session: RemoteSession?, client: JellyfinClient) {
        let previous = updating
        updating = Task {
            await previous?.value
            await apply(session, client: client)
        }
    }

    private func apply(_ session: RemoteSession?, client: JellyfinClient) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let session else {
            await endAll()
            return
        }
        let artworkID = await artwork.prepare(session.item, client: client)
        let state = Self.state(for: session, artworkID: artworkID, at: .now)
        var hasActivity = false
        for activity in Activity<RemotePlaybackAttributes>.activities {
            guard activity.attributes.deviceID == session.deviceID, !hasActivity else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            hasActivity = true
            let isCurrent = activity.activityState != .stale && Self.isSame(activity.content.state, state)
            if !isCurrent { await activity.update(Self.content(state)) }
        }
        guard !hasActivity else { return }
        let attributes = RemotePlaybackAttributes(deviceID: session.deviceID)
        _ = try? Activity.request(attributes: attributes, content: Self.content(state), pushType: nil)
    }

    func endAll() async {
        for activity in Activity<RemotePlaybackAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        artwork.clear()
    }

    private func perform(_ action: RemotePlaybackAction) async {
        guard let activity = Activity<RemotePlaybackAttributes>.activities.first else { return }
        let state = activity.content.state
        let now = Date.now
        let next: State
        let command: RemoteCommand
        switch action {
        case .playPause:
            next = state.toggled(at: now)
            command = state.isPaused ? .unpause : .pause
        case .skip(let seconds):
            next = state.seeked(by: seconds, at: now)
            command = .seek(positionTicks: Int64(next.positionSeconds * Double(Ticks.perSecond)))
        }
        await activity.update(Self.content(next))
        if let remote {
            await remote.send(command, to: state.sessionID)
        } else if let session = SessionStorage.load() {
            try? await session.client.send(command, toSession: state.sessionID)
        }
    }

    private static func content(_ state: State) -> ActivityContent<State> {
        ActivityContent(state: state, staleDate: staleDate(state))
    }

    private static func staleDate(_ state: State) -> Date {
        if state.isPaused { return state.positionDate.addingTimeInterval(pausedStaleSeconds) }
        guard let end = state.endDate else {
            return state.positionDate.addingTimeInterval(unknownRuntimeStaleSeconds)
        }
        return end.addingTimeInterval(endGraceSeconds)
    }

    private static func isSame(_ old: State, _ new: State) -> Bool {
        var aligned = new
        aligned.positionSeconds = old.positionSeconds
        aligned.positionDate = old.positionDate
        guard aligned == old else { return false }
        let drift = new.isPaused
            ? abs(new.positionSeconds - old.positionSeconds)
            : abs(new.startDate.timeIntervalSince(old.startDate))
        return drift < driftToleranceSeconds
    }

    private static func state(for session: RemoteSession, artworkID: String?, at date: Date) -> State {
        let item = session.item
        return State(
            title: item.seriesName ?? item.name,
            episodeLine: item.seriesName == nil ? nil : Format.joined([episodeCode(item), item.name]),
            deviceName: session.deviceName,
            isPaused: session.isPaused,
            positionSeconds: Ticks.seconds(session.position(at: date)),
            positionDate: date,
            runtimeSeconds: item.runtimeTicks.map(Ticks.seconds),
            sessionID: session.id,
            canControl: session.canControl,
            artworkID: artworkID
        )
    }

    /// "S1 · E7".
    private static func episodeCode(_ item: RemoteItem) -> String? {
        switch (item.seasonNumber, item.episodeNumber) {
        case let (season?, episode?) where season > 0: "S\(season) · E\(episode)"
        case let (season?, nil) where season > 0: "S\(season)"
        case let (_, episode?): "E\(episode)"
        default: nil
        }
    }
}

#if DEBUG
extension RemotePlaybackActivity {
    static let previewArgument = "-liveActivityPreview"

    /// Sample data for a screenshot: the simulator account has no TV playing.
    func showPreview() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await endAll()
        let state = State(
            title: "The Leftovers",
            episodeLine: "S1 · E7 · Solace for Tired Feet",
            deviceName: "chromecast",
            isPaused: false,
            positionSeconds: 23 * 60 + 41,
            positionDate: .now,
            runtimeSeconds: 56 * 60,
            sessionID: "preview",
            canControl: true,
            artworkID: nil
        )
        _ = try? Activity.request(
            attributes: RemotePlaybackAttributes(deviceID: "preview"),
            content: Self.content(state),
            pushType: nil
        )
    }
}
#endif
