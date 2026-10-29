import Foundation

enum JellyfinError: LocalizedError {
    case invalidAddress
    case notJellyfin
    case unauthorized
    case badStatus(Int)
    case unreachable(URLError)

    var errorDescription: String? {
        switch self {
        case .invalidAddress: String(localized: "This is not a valid address.")
        case .notJellyfin: String(localized: "No Jellyfin server answers at this address.")
        case .unauthorized: String(localized: "The server no longer accepts this sign-in.")
        case .badStatus(let status): String(localized: "The server answered with status \(status).")
        case .unreachable(let error) where error.code == .notConnectedToInternet:
            String(localized: "You're offline.")
        case .unreachable: String(localized: "The server can't be reached right now.")
        }
    }
}

struct JellyfinServerInfo: Sendable {
    let id: String
    let name: String
    let version: String
}

struct QuickConnectRequest: Sendable {
    let code: String
    let secret: String
}

/// Talks to one Jellyfin server; holds no state besides the address and the sign-in.
nonisolated struct JellyfinClient: Sendable {
    let serverURL: URL
    let deviceID: String
    var accessToken: String?

    private static let clientName = "JellyCast"
    private static let requestTimeoutSeconds = 15.0
    private static let libraryTimeoutSeconds = 60.0

    private static var clientVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Accepts "192.168.1.4:8096" or a full URL; plain HTTP is the default on the home LAN.
    static func serverURL(from address: String) -> URL? {
        var trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "http://" + trimmed }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil
        else { return nil }
        return url
    }

    var authorizationHeader: String {
        var fields = [
            "Client=\"\(Self.clientName)\"",
            "Device=\"\(SessionStorage.deviceName)\"",
            "DeviceId=\"\(deviceID)\"",
            "Version=\"\(Self.clientVersion)\"",
        ]
        if let accessToken { fields.append("Token=\"\(accessToken)\"") }
        return "MediaBrowser " + fields.joined(separator: ", ")
    }

    func publicInfo(timeout: Double = requestTimeoutSeconds) async throws -> JellyfinServerInfo {
        struct Response: Decodable {
            let Id: String
            let ServerName: String
            let Version: String
            let ProductName: String?
        }
        let response: Response
        do {
            response = try await send("System/Info/Public", timeout: timeout)
        } catch is DecodingError {
            throw JellyfinError.notJellyfin
        }
        if let product = response.ProductName, !product.contains("Jellyfin") {
            throw JellyfinError.notJellyfin
        }
        return JellyfinServerInfo(id: response.Id, name: response.ServerName, version: response.Version)
    }

    func initiateQuickConnect() async throws -> QuickConnectRequest {
        struct Response: Decodable { let Code: String; let Secret: String }
        let response: Response = try await send("QuickConnect/Initiate", method: "POST")
        return QuickConnectRequest(code: response.Code, secret: response.Secret)
    }

    func isQuickConnectApproved(secret: String) async throws -> Bool {
        struct Response: Decodable { let Authenticated: Bool }
        let response: Response = try await send(
            "QuickConnect/Connect", query: [URLQueryItem(name: "secret", value: secret)]
        )
        return response.Authenticated
    }

    func authenticate(quickConnectSecret secret: String) async throws -> (
        userID: String, userName: String, accessToken: String
    ) {
        struct User: Decodable { let Id: String; let Name: String }
        struct Response: Decodable { let AccessToken: String; let User: User }
        let body = try JSONEncoder().encode(["Secret": secret])
        let response: Response = try await send(
            "Users/AuthenticateWithQuickConnect", method: "POST", body: body
        )
        return (response.User.Id, response.User.Name, response.AccessToken)
    }

    /// The user's subtitle language first, then the audio language, as set on the server.
    func preferredLanguages() async throws -> [String] {
        struct Configuration: Decodable {
            let SubtitleLanguagePreference: String?
            let AudioLanguagePreference: String?
        }
        struct User: Decodable { let Configuration: Configuration? }
        let user: User = try await send("Users/Me")
        let codes = [user.Configuration?.SubtitleLanguagePreference, user.Configuration?.AudioLanguagePreference]
        var seen = Set<String>()
        return codes.compactMap { $0 }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func signOut() async {
        _ = try? await data("Sessions/Logout", method: "POST")
    }

    /// Every item of one type over all libraries, with user data, sorted by sort name.
    func items(type: String, userID: String) async throws -> [JellyfinItem] {
        struct Response: Decodable { let Items: [JellyfinItem] }
        let response: Response = try await send(
            "Items",
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "recursive", value: "true"),
                URLQueryItem(name: "includeItemTypes", value: type),
                URLQueryItem(name: "fields", value: "Overview,DateCreated,Genres,ProviderIds"),
                URLQueryItem(name: "enableUserData", value: "true"),
                URLQueryItem(name: "enableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
                URLQueryItem(name: "imageTypeLimit", value: "1"),
                URLQueryItem(name: "sortBy", value: "SortName"),
            ],
            timeout: Self.libraryTimeoutSeconds
        )
        return response.Items
    }

    func send<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        timeout: Double = requestTimeoutSeconds
    ) async throws -> Response {
        let data = try await data(path, method: method, query: query, body: body, timeout: timeout)
        return try JSONDecoder.jellyfin.decode(Response.self, from: data)
    }

    func data(
        _ path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        timeout: Double = requestTimeoutSeconds
    ) async throws -> Data {
        var components = URLComponents(
            url: serverURL.appending(path: path), resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw JellyfinError.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw JellyfinError.unreachable(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw JellyfinError.unauthorized }
        guard (200..<300).contains(status) else { throw JellyfinError.badStatus(status) }
        return data
    }
}

extension JSONDecoder {
    nonisolated static var jellyfin: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = JellyfinDate.parse(text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown date \(text)")
            )
        }
        return decoder
    }
}

/// Jellyfin writes seven fractional digits, which the ISO 8601 parser rejects; three are kept.
nonisolated enum JellyfinDate {
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle()

    static func parse(_ text: String) -> Date? {
        var normalized = text
        if let dot = text.firstIndex(of: ".") {
            let fraction = text[text.index(after: dot)...]
            let digits = fraction.prefix { $0.isNumber }
            normalized = text[..<dot] + "." + digits.prefix(3) + fraction.dropFirst(digits.count)
        }
        return (try? withFraction.parse(normalized)) ?? (try? withoutFraction.parse(normalized))
    }
}
