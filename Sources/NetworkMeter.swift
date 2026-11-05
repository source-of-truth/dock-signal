import Foundation
import SystemConfiguration
import Darwin

struct ConnectionReading: Equatable {
    var freeGB: String = "—"
    var wifiIP: String?
    var receive: String = "—"
    var send: String = "—"
}

final class NetworkMeter {
    private struct Counters {
        let received: UInt64
        let sent: UInt64
    }
    private var previous: [UInt32: Counters] = [:]
    private var lastTime: TimeInterval?
    private var ports: [String: Bool] = [:] // BSD name -> is Wi-Fi
    private var lastPortScan = -Double.infinity

    func sample() -> ConnectionReading {
        var result = ConnectionReading()
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPortScan >= 30 {
            ports.removeAll()
            for port in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
                guard let name = SCNetworkInterfaceGetBSDName(port) as String?,
                      let type = SCNetworkInterfaceGetInterfaceType(port) else { continue }
                let wifi = CFEqual(type, kSCNetworkInterfaceTypeIEEE80211)
                if wifi || CFEqual(type, kSCNetworkInterfaceTypeEthernet) { ports[name] = wifi }
            }
            lastPortScan = now
        }
        var disk = statfs()
        if statfs(NSHomeDirectory(), &disk) == 0 {
            let gb = Double(disk.f_bavail) * Double(disk.f_bsize) / 1e9
            result.freeGB = String(format: gb < 10 ? "%.1f" : "%.0f", gb)
        }
        var head: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&head) == 0 {
            defer { freeifaddrs(head) }
            var cursor = head
            while let entry = cursor?.pointee {
                cursor = entry.ifa_next
                guard ports[String(cString: entry.ifa_name)] == true,
                      entry.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) == UInt32(IFF_UP | IFF_RUNNING),
                      let address = entry.ifa_addr, address.pointee.sa_family == AF_INET else { continue }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    result.wifiIP = String(cString: buffer)
                    break
                }
            }
        }
        guard let current = counters() else {
            lastTime = nil
            return result
        }
        defer { previous = current; lastTime = now }
        guard let lastTime, now > lastTime, now - lastTime < 15 else { return result }
        var received = 0.0, sent = 0.0
        var comparable = false
        for (index, counter) in current {
            guard let old = previous[index], old.received <= counter.received, old.sent <= counter.sent else { continue }
            comparable = true
            received += Double(counter.received - old.received)
            sent += Double(counter.sent - old.sent)
        }
        if comparable {
            result.receive = Self.rate(received / (now - lastTime))
            result.send = Self.rate(sent / (now - lastTime))
        }
        return result
    }

    private static func rate(_ bytes: Double) -> String {
        for (scale, unit) in [(1e9, "GB/s"), (1e6, "MB/s"), (1e3, "kB/s")] where bytes >= scale {
            let value = bytes / scale
            return String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, unit)
        }
        return String(format: "%.0f B/s", bytes)
    }

    // NET_RT_IFLIST2 supplies 64-bit byte counters even for long-lived links.
    private func counters() -> [UInt32: Counters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        let data = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: MemoryLayout<if_msghdr2>.alignment)
        defer { data.deallocate() }
        guard sysctl(&mib, 6, data, &length, nil, 0) == 0 else { return nil }
        var result: [UInt32: Counters] = [:]
        var offset = 0
        while offset + 4 <= length {
            let message = data.advanced(by: offset)
            let size = Int(message.loadUnaligned(as: UInt16.self))
            guard size >= 4, size <= length - offset else { return nil }
            if message.load(fromByteOffset: 3, as: UInt8.self) == RTM_IFINFO2, size >= MemoryLayout<if_msghdr2>.size {
                let info = message.loadUnaligned(as: if_msghdr2.self)
                let index = UInt32(info.ifm_index)
                var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                if info.ifm_flags & IFF_UP != 0, info.ifm_flags & IFF_RUNNING != 0,
                   if_indextoname(index, &name) != nil, ports[String(cString: name)] != nil {
                    result[index] = Counters(received: info.ifm_data.ifi_ibytes, sent: info.ifm_data.ifi_obytes)
                }
            }
            offset += size
        }
        return result
    }
}
