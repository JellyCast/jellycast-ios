import Foundation

/// When this build stops launching: the free developer team's profile lasts 7 days, and an
/// expired build can't be reinstalled away from the Mac.
nonisolated enum BuildExpiry {
    /// Nil in the simulator, which has no profile.
    static let date: Date? = {
        #if DEBUG
        // `-buildExpiresInDays <n>` shows the note in the simulator.
        let days = UserDefaults.standard.double(forKey: "buildExpiresInDays")
        if days > 0 { return .now.addingTimeInterval(days * 24 * 60 * 60) }
        #endif
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expirationDate(inProfile: data)
    }()

    /// Warn this long before, so a trip of a few days is covered.
    static let warningInterval: TimeInterval = 3 * 24 * 60 * 60

    static func isSoon(_ date: Date, now: Date = .now) -> Bool {
        date.timeIntervalSince(now) < warningInterval
    }

    /// The profile is a signed CMS envelope around a plain XML property list.
    static func expirationDate(inProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = data[start.lowerBound..<end.upperBound]
        let object = try? PropertyListSerialization.propertyList(from: plist, format: nil)
        return (object as? [String: Any])?["ExpirationDate"] as? Date
    }
}
