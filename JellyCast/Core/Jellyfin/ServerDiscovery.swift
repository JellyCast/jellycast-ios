import Darwin
import Foundation

struct DiscoveredServer: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let serverURL: URL
}

/// Finds Jellyfin servers on the local network through Jellyfin's UDP discovery on port 7359.
nonisolated enum ServerDiscovery {
    private static let port: UInt16 = 7359
    private static let question = Array("who is JellyfinServer?".utf8)
    private static let listenDuration = Duration.seconds(2)
    private static let receiveInterval = Duration.milliseconds(50)
    private static let sendBatchSize = 64
    private static let sendBatchPause = Duration.milliseconds(5)
    private static let receiveBufferSize = 4096
    /// Caps a sweep at a /22 (1022 hosts).
    private static let narrowestSweepMask: UInt32 = 0xFFFF_FC00
    private static let linkLocalNetwork: UInt32 = 0xA9FE_0000
    private static let linkLocalMask: UInt32 = 0xFFFF_0000

    static func search() -> AsyncStream<DiscoveredServer> {
        AsyncStream { continuation in
            let task = Task {
                await sweep(into: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // Broadcast needs the multicast entitlement, which the free personal team can't get,
    // so the question goes unicast to every address in the local subnets instead.
    private static func sweep(into continuation: AsyncStream<DiscoveredServer>.Continuation) async {
        let socket = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socket >= 0 else { return }
        defer { close(socket) }
        _ = fcntl(socket, F_SETFL, fcntl(socket, F_GETFL) | O_NONBLOCK)

        var seen = Set<String>()
        let report = { (servers: [DiscoveredServer]) in
            for server in servers where seen.insert(server.id).inserted {
                continuation.yield(server)
            }
        }

        for (index, host) in localHosts().enumerated() {
            send(to: host, on: socket)
            if index % sendBatchSize == sendBatchSize - 1 {
                report(receive(on: socket))
                guard (try? await Task.sleep(for: sendBatchPause)) != nil else { return }
            }
        }
        let deadline = ContinuousClock.now + listenDuration
        while ContinuousClock.now < deadline {
            report(receive(on: socket))
            guard (try? await Task.sleep(for: receiveInterval)) != nil else { return }
        }
        report(receive(on: socket))
    }

    private static func send(to host: UInt32, on socket: Int32) {
        var target = sockaddr_in()
        target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        target.sin_family = sa_family_t(AF_INET)
        target.sin_port = port.bigEndian
        target.sin_addr.s_addr = host.bigEndian
        _ = withUnsafePointer(to: &target) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                sendto(
                    socket, question, question.count, 0,
                    address, socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
    }

    private static func receive(on socket: Int32) -> [DiscoveredServer] {
        var servers: [DiscoveredServer] = []
        var buffer = [UInt8](repeating: 0, count: receiveBufferSize)
        while true {
            let count = recv(socket, &buffer, buffer.count, 0)
            guard count > 0 else { return servers }
            if let server = decodeReply(Data(buffer[0..<count])) { servers.append(server) }
        }
    }

    static func decodeReply(_ data: Data) -> DiscoveredServer? {
        struct Reply: Decodable {
            let Id: String
            let Name: String?
            let Address: String
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let url = JellyfinClient.serverURL(from: reply.Address)
        else { return nil }
        let name = reply.Name?.trimmingCharacters(in: .whitespaces) ?? ""
        return DiscoveredServer(id: reply.Id, name: name.isEmpty ? url.absoluteString : name, serverURL: url)
    }

    /// Every IPv4 host address in the subnets of the active interfaces, in host byte order.
    private static func localHosts() -> [UInt32] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        var hosts: [UInt32] = []
        var seen = Set<UInt32>()
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let netmask = entry.pointee.ifa_netmask
            else { continue }
            let own = ipv4(address)
            let mask = max(ipv4(netmask), narrowestSweepMask)
            guard own & linkLocalMask != linkLocalNetwork else { continue }
            let network = own & mask
            let broadcast = network | ~mask
            guard broadcast > network + 1 else { continue }
            for host in (network + 1)..<broadcast where host != own && seen.insert(host).inserted {
                hosts.append(host)
            }
        }
        return hosts
    }

    private static func ipv4(_ address: UnsafeMutablePointer<sockaddr>) -> UInt32 {
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
        }
    }
}
