import Foundation

/// One ad as the service sends it. Chosen by country only.
nonisolated struct AdCampaign: Codable, Sendable, Hashable, Identifiable {
    let id: Int
    let position: Int?
    let image: URL
    let title: String?
    let advertiser: String
    let url: URL?
    let seconds: Int?
    let until: Date
}

nonisolated struct AdPlacementsResponse: Codable, Sendable {
    let version: Int
    let country: String?
    let home: AdCampaign?
    let splash: AdCampaign?
}

/// What the service wants on each placement, kept between launches so Home doesn't wait for it.
/// Nothing is shown when the service has never answered or the campaign has ended.
@Observable
final class AdPlacements {
    static let shared = AdPlacements()

    private(set) var response: AdPlacementsResponse?

    private let defaults: UserDefaults
    private var refreshedAt: ContinuousClock.Instant?

    private static let responseKey = "ads.placements"
    private static let refreshInterval = Duration.seconds(15 * 60)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        response = defaults.data(forKey: Self.responseKey)
            .flatMap { try? JSONDecoder.service.decode(AdPlacementsResponse.self, from: $0) }
    }

    var home: AdCampaign? { running(response?.home) }

    var country: String? { response?.country }

    /// At launch and when the app comes back; at most once per refresh interval.
    func refresh() async {
        if let refreshedAt, ContinuousClock.now - refreshedAt < Self.refreshInterval { return }
        refreshedAt = .now
        guard let fresh = try? await JellyCastService.current.placements() else {
            refreshedAt = nil
            return
        }
        response = fresh
        if let data = try? JSONEncoder.service.encode(fresh) { defaults.set(data, forKey: Self.responseKey) }
    }

    private func running(_ campaign: AdCampaign?) -> AdCampaign? {
        guard let campaign, campaign.until > .now else { return nil }
        return campaign
    }
}

nonisolated extension JSONEncoder {
    static var service: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
