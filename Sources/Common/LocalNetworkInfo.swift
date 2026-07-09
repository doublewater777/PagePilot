//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Lightweight helpers for local Wi‑Fi diagnostics (Watch → iPhone → iPad relay).
enum LocalNetworkInfo {
    /// IPv4 addresses on non-loopback interfaces (typically Wi‑Fi / Ethernet).
    static func ipv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = pointer {
            defer { pointer = iface.pointee.ifa_next }

            let flags = Int32(iface.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = iface.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            if !addresses.contains(ip) {
                addresses.append(ip)
            }
        }

        return addresses
    }

    /// Strip port from strings like "192.168.1.10:54321".
    static func hostOnly(_ address: String) -> String {
        if address.contains("]:") {
            // [IPv6]:port
            if let close = address.firstIndex(of: "]") {
                return String(address[address.startIndex...close]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            }
        }
        if let colon = address.lastIndex(of: ":"),
           address[address.index(after: colon)...].allSatisfy(\.isNumber) {
            return String(address[..<colon])
        }
        return address
    }

    /// Best-effort: same /24 for IPv4 (common home/office LAN heuristic).
    static func likelySameSubnet(localIPs: [String], remoteAddress: String) -> Bool? {
        let remote = hostOnly(remoteAddress)
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        guard remoteParts.count == 4 else { return nil }

        for local in localIPs {
            let localParts = local.split(separator: ".").compactMap { Int($0) }
            guard localParts.count == 4 else { continue }
            if localParts[0] == remoteParts[0],
               localParts[1] == remoteParts[1],
               localParts[2] == remoteParts[2] {
                return true
            }
        }
        return false
    }
}
