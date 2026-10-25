import Darwin
import Foundation

/// Whether the server sits on the same local network as this device: its IPv4 address falls in
/// the subnet of one of the device's own interfaces. A VPN tunnel (point-to-point) doesn't count,
/// and neither does a host name, which would need a lookup.
nonisolated enum LocalNetwork {
    static func contains(serverURL: URL) -> Bool {
        guard let host = serverURL.host(), let server = ipv4(host) else { return false }
        return subnets().contains { server & $0.mask == $0.network }
    }

    private static func ipv4(_ host: String) -> UInt32? {
        var address = in_addr()
        guard inet_pton(AF_INET, host, &address) == 1 else { return nil }
        return UInt32(bigEndian: address.s_addr)
    }

    private static func subnets() -> [(network: UInt32, mask: UInt32)] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        return sequence(first: first, next: { $0.pointee.ifa_next }).compactMap { entry in
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let netmask = entry.pointee.ifa_netmask
            else { return nil }
            let mask = value(netmask)
            return (value(address) & mask, mask)
        }
    }

    private static func value(_ address: UnsafeMutablePointer<sockaddr>) -> UInt32 {
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
        }
    }
}
