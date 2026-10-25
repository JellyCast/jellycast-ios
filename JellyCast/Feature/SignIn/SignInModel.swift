import Foundation

@Observable
final class SignInModel {
    enum Phase: Equatable {
        case enterAddress
        case checkingServer
        case waitingForApproval(serverName: String, code: String)
        case failed(String)
    }

    enum DiscoveryStatus: Equatable {
        case searching
        case done
    }

    enum ServerCheck: Equatable {
        case checking
        case ready(version: String)
        case unreachable
    }

    struct FoundServer: Identifiable, Equatable {
        let server: DiscoveredServer
        var check: ServerCheck = .checking
        let isCurrent: Bool

        var id: String { server.id }
    }

    var address: String
    private(set) var phase: Phase = .enterAddress
    private(set) var discovery: DiscoveryStatus = .searching
    private(set) var foundServers: [FoundServer] = []

    private let onSignedIn: (Session) -> Void

    private static let approvalPollInterval = Duration.seconds(2)
    private static let quickConnectLifetime = Duration.seconds(10 * 60)

    init(address: String = SessionStorage.lastServerAddress ?? "", onSignedIn: @escaping (Session) -> Void) {
        self.address = address
        self.onSignedIn = onSignedIn
    }

    var canConnect: Bool { JellyfinClient.serverURL(from: address) != nil }

    func discover() async {
        discovery = .searching
        foundServers = []
        let currentURL = SessionStorage.lastServerAddress.flatMap(JellyfinClient.serverURL(from:))
        await withDiscardingTaskGroup { group in
            for await server in ServerDiscovery.search() {
                foundServers.append(FoundServer(server: server, isCurrent: server.serverURL == currentURL))
                // The discovery reply has no version, so check each server separately.
                group.addTask { await self.check(server) }
            }
            discovery = .done
        }
    }

    func connect(to server: DiscoveredServer) async {
        address = server.serverURL.absoluteString
        await connect()
    }

    private func check(_ server: DiscoveredServer) async {
        let client = JellyfinClient(serverURL: server.serverURL, deviceID: SessionStorage.deviceID)
        let check: ServerCheck =
            if let info = try? await client.publicInfo() { .ready(version: info.version) } else { .unreachable }
        guard let index = foundServers.firstIndex(where: { $0.id == server.id }) else { return }
        foundServers[index].check = check
    }

    func connect() async {
        guard let serverURL = JellyfinClient.serverURL(from: address) else {
            phase = .failed(JellyfinError.invalidAddress.localizedDescription)
            return
        }
        phase = .checkingServer
        let client = JellyfinClient(serverURL: serverURL, deviceID: SessionStorage.deviceID)
        do {
            let server = try await client.publicInfo()
            SessionStorage.lastServerAddress = address
            let request = try await client.initiateQuickConnect()
            phase = .waitingForApproval(serverName: server.name, code: request.code)
            try await waitForApproval(of: request, client: client)
            let user = try await client.authenticate(quickConnectSecret: request.secret)
            let session = Session(
                serverURL: serverURL, serverID: server.id, serverName: server.name,
                userID: user.userID, userName: user.userName, accessToken: user.accessToken
            )
            SessionStorage.save(session)
            onSignedIn(session)
        } catch is CancellationError {
            phase = .enterAddress
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func waitForApproval(of request: QuickConnectRequest, client: JellyfinClient) async throws {
        let deadline = ContinuousClock.now + Self.quickConnectLifetime
        while try await !client.isQuickConnectApproved(secret: request.secret) {
            guard ContinuousClock.now < deadline else { throw SignInError.codeExpired }
            try await Task.sleep(for: Self.approvalPollInterval)
        }
    }
}

enum SignInError: LocalizedError {
    case codeExpired

    var errorDescription: String? {
        switch self {
        case .codeExpired: String(localized: "The code has expired. Try again for a new one.")
        }
    }
}
