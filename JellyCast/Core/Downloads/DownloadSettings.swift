import Foundation

/// How downloads look after themselves, kept on this device.
@Observable
final class DownloadSettings {
    static let shared = DownloadSettings()

    /// How many episodes "Download next" fetches, and how many a kept series stays ahead.
    static let seriesBatch = 5
    /// How long a watched download stays before it is removed.
    static let watchedGraceSeconds: TimeInterval = 24 * 60 * 60

    var removesWatched: Bool {
        didSet { defaults.set(removesWatched, forKey: Self.removesWatchedKey) }
    }

    var keepsSeriesAhead: Bool {
        didSet { defaults.set(keepsSeriesAhead, forKey: Self.keepsSeriesAheadKey) }
    }

    /// Series downloaded with "Download next"; these stay ahead while `keepsSeriesAhead` is on.
    private(set) var keptSeriesIDs: Set<String> {
        didSet { defaults.set(Array(keptSeriesIDs), forKey: Self.keptSeriesKey) }
    }

    private let defaults: UserDefaults

    private static let removesWatchedKey = "downloads.removesWatched"
    private static let keepsSeriesAheadKey = "downloads.keepsSeriesAhead"
    private static let keptSeriesKey = "downloads.keptSeries"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        removesWatched = defaults.object(forKey: Self.removesWatchedKey) as? Bool ?? true
        keepsSeriesAhead = defaults.bool(forKey: Self.keepsSeriesAheadKey)
        keptSeriesIDs = Set(defaults.stringArray(forKey: Self.keptSeriesKey) ?? [])
    }

    func keep(seriesID: String) {
        keptSeriesIDs.insert(seriesID)
    }

    func stopKeeping(seriesID: String) {
        keptSeriesIDs.remove(seriesID)
    }
}
