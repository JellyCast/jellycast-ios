import UIKit

/// The JellyCast service (`../jellycast-api`): usage pings and the ads on each placement.
/// Not the user's Jellyfin server.
nonisolated struct JellyCastService: Sendable {
    /// The test server on the home LAN, then the same machine over the VPN, until the service
    /// has a public address. `-serviceAddress <url>` at launch points a test build elsewhere.
    static var addresses: [URL] {
        if let override = UserDefaults.standard.string(forKey: "serviceAddress").flatMap(URL.init(string:)) {
            return [override]
        }
        return ["http://192.168.1.4:8090", "http://10.8.0.1:8090"].compactMap(URL.init(string:))
    }

    private static let timeoutSeconds = 4.0

    let platform: String

    @MainActor static var current: JellyCastService {
        JellyCastService(platform: UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios")
    }

    @concurrent
    func ping(installID: UUID) async throws {
        let body = try JSONEncoder().encode(["id": installID.uuidString, "platform": platform])
        _ = try await firstAnswer(path: "v1/ping", method: "POST", body: body)
    }

    @concurrent
    func placements() async throws -> AdPlacementsResponse {
        let data = try await firstAnswer(path: "v1/placements", query: [URLQueryItem(name: "platform", value: platform)])
        return try JSONDecoder.service.decode(AdPlacementsResponse.self, from: data)
    }

    private func firstAnswer(
        path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil
    ) async throws -> Data {
        var lastError: Error = URLError(.cannotConnectToHost)
        for address in Self.addresses {
            var request = URLRequest(
                url: address.appending(path: path).appending(queryItems: query),
                timeoutInterval: Self.timeoutSeconds
            )
            request.httpMethod = method
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
                    throw URLError(.badServerResponse)
                }
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

nonisolated extension JSONDecoder {
    static var service: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
