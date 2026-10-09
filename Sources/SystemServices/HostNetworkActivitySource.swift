import Darwin
import Foundation
import SystemConfiguration

/// Reads the live machine through public APIs: `getifaddrs` for the byte counters
/// (`if_data` on each `AF_LINK` entry) and addresses, and SystemConfiguration's
/// `SCNetworkInterfaceCopyAll` for the names Network Settings shows.
public struct HostNetworkActivitySource: NetworkActivitySource {
    public init() {}

    public func interfaces() -> [NetworkInterfaceReading] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let list else { return [] }
        defer { freeifaddrs(list) }

        var order: [String] = []
        var readings: [String: NetworkInterfaceReading] = [:]
        var addresses: [String: [String]] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = list
        while let entry = pointer {
            pointer = entry.pointee.ifa_next
            guard let address = entry.pointee.ifa_addr else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            let flags = entry.pointee.ifa_flags
            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                guard let data = entry.pointee.ifa_data else { continue }
                let counters = data.load(as: if_data.self)
                let isLoopback = flags & UInt32(IFF_LOOPBACK) != 0
                let isPointToPoint = flags & UInt32(IFF_POINTOPOINT) != 0
                if readings[name] == nil { order.append(name) }
                readings[name] = NetworkInterfaceReading(
                    name: name,
                    kind: NetworkInterfaceReading.kind(
                        forName: name, isLoopback: isLoopback, isPointToPoint: isPointToPoint),
                    isUp: flags & UInt32(IFF_UP) != 0,
                    isRunning: flags & UInt32(IFF_RUNNING) != 0,
                    isPointToPoint: isPointToPoint,
                    bytesIn: UInt64(counters.ifi_ibytes),
                    bytesOut: UInt64(counters.ifi_obytes))
            case AF_INET, AF_INET6:
                if let text = Self.numericHost(address) {
                    addresses[name, default: []].append(text)
                }
            default:
                continue
            }
        }

        return order.compactMap { name in
            guard var reading = readings[name] else { return nil }
            reading.addresses = NetworkMath.orderedAddresses(addresses[name] ?? [])
            return reading
        }
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        guard result == 0 else { return nil }
        return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public func descriptions() -> [String: NetworkInterfaceDescription] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var result: [String: NetworkInterfaceDescription] = [:]
        for interface in all {
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsdName
            let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
            result[bsdName] = NetworkInterfaceDescription(
                displayName: displayName, kind: type.flatMap { Self.kindsByType[$0] })
        }
        return result
    }

    /// SystemConfiguration's interface types as the widget's kinds. Types missing here
    /// keep the name-based guess.
    private static let kindsByType: [String: NetworkInterfaceKind] = [
        kSCNetworkInterfaceTypeIEEE80211 as String: .wifi,
        kSCNetworkInterfaceTypeEthernet as String: .ethernet,
        kSCNetworkInterfaceTypeFireWire as String: .ethernet,
        kSCNetworkInterfaceTypeBluetooth as String: .ethernet,
        kSCNetworkInterfaceTypeWWAN as String: .cellular,
        kSCNetworkInterfaceTypePPP as String: .tunnel,
        kSCNetworkInterfaceTypeIPSec as String: .tunnel,
        kSCNetworkInterfaceTypeL2TP as String: .tunnel,
        kSCNetworkInterfaceTypeBond as String: .virtual,
        kSCNetworkInterfaceTypeVLAN as String: .virtual,
        kSCNetworkInterfaceType6to4 as String: .virtual,
    ]
}
