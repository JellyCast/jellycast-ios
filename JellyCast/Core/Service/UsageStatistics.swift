import Foundation

/// The user's choice about usage statistics, and the ping it allows. The install ID exists
/// only while the user allows it; declining deletes it.
@Observable
final class UsageStatistics {
    static let shared = UsageStatistics()

    enum Choice: String, Codable {
        case allowed, declined
    }

    /// Raise when what is sent or why changes, so everyone is asked again.
    static let consentVersion = 1

    private(set) var choice: Choice?

    private let defaults: UserDefaults
    private var lastPingAt: ContinuousClock.Instant?

    private static let choiceKey = "usage.choice"
    private static let versionKey = "usage.consentVersion"
    private static let decidedAtKey = "usage.decidedAt"
    private static let installIDKey = "usage.installID"
    private static let pingInterval = Duration.seconds(60 * 60)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.integer(forKey: Self.versionKey) == Self.consentVersion {
            choice = defaults.string(forKey: Self.choiceKey).flatMap(Choice.init(rawValue:))
        }
    }

    var needsChoice: Bool { choice == nil }

    var isAllowed: Bool {
        get { choice == .allowed }
        set { choose(newValue ? .allowed : .declined) }
    }

    func choose(_ choice: Choice) {
        self.choice = choice
        defaults.set(choice.rawValue, forKey: Self.choiceKey)
        defaults.set(Self.consentVersion, forKey: Self.versionKey)
        defaults.set(Date.now, forKey: Self.decidedAtKey)
        switch choice {
        case .allowed:
            if installID == nil { defaults.set(UUID().uuidString, forKey: Self.installIDKey) }
            Task { await appOpened() }
        case .declined:
            defaults.removeObject(forKey: Self.installIDKey)
            lastPingAt = nil
        }
    }

    /// At launch and when the app comes back to the foreground; at most once an hour.
    func appOpened() async {
        guard choice == .allowed, let installID else { return }
        if let lastPingAt, ContinuousClock.now - lastPingAt < Self.pingInterval { return }
        lastPingAt = .now
        do {
            try await JellyCastService.current.ping(installID: installID)
        } catch {
            lastPingAt = nil
        }
    }

    private var installID: UUID? {
        defaults.string(forKey: Self.installIDKey).flatMap(UUID.init(uuidString:))
    }
}
