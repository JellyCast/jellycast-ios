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
    let device: DeviceDetails

    @MainActor static var current: JellyCastService {
        JellyCastService(
            platform: UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios",
            device: .current
        )
    }

    @concurrent
    func ping(installID: UUID) async throws {
        let body = try JSONEncoder().encode([
            "id": installID.uuidString,
            "platform": platform,
            "brand": device.brand,
            "model": device.model,
            "os": device.os,
            "osVersion": device.osVersion,
            "appVersion": device.appVersion,
        ])
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

/// The kind of device and the app version, for support. Never the device's own name, which on
/// iOS is the owner's ("iPhone van …").
nonisolated struct DeviceDetails: Sendable {
    let brand = "Apple"
    let model: String
    let os: String
    let osVersion: String
    let appVersion: String

    @MainActor static var current: DeviceDetails {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return DeviceDetails(
            model: modelIdentifier,
            os: UIDevice.current.systemName,
            osVersion: UIDevice.current.systemVersion,
            appVersion: "\(version) (\(build))"
        )
    }

    /// "iPhone19,7"; the simulator reports the Mac's architecture, so it names what it simulates.
    private static var modelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

nonisolated extension JSONDecoder {
    static var service: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
