import Foundation
import Darwin

enum MemoryPressure: Int32 {
    case normal = 1, warning = 2, critical = 4

    var segments: Int {
        switch self {
        case .normal: return 1
        case .warning: return 2
        case .critical: return 3
        }
    }

    var description: String {
        switch self {
        case .normal: return "В норме"
        case .warning: return "Повышенная"
        case .critical: return "Критическая"
        }
    }
}

struct SystemReading: Equatable {
    var swap = "—"
    var unit = "ГБ"
    var pressure: MemoryPressure?
    var cpuPercent: Int?
    var cpu: String { cpuPercent.map { "\($0)%" } ?? "—" }
}

final class SystemMeter {
    private let host = mach_host_self()
    private var lastTicks: (UInt32, UInt32, UInt32, UInt32)?

    deinit { mach_port_deallocate(mach_task_self_, host) }

    func sample() -> SystemReading {
        var reading = SystemReading()
        var swap = xsw_usage()
        var swapSize = MemoryLayout.size(ofValue: swap)
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            let bytes = swap.xsu_used
            if bytes > 0 && bytes < 1_000_000_000 {
                reading.unit = "МБ"
                reading.swap = String(format: "%.0f", Double(bytes) / 1e6)
            } else {
                reading.swap = String(format: "%.1f", Double(bytes) / 1e9)
            }
        }

        var level: Int32 = 0
        var levelSize = MemoryLayout.size(ofValue: level)
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 {
            reading.pressure = MemoryPressure(rawValue: level)
        }

        var cpu = host_cpu_load_info()
        var cpuCount = mach_msg_type_number_t(MemoryLayout.size(ofValue: cpu) / MemoryLayout<integer_t>.stride)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        guard cpuStatus == KERN_SUCCESS else {
            lastTicks = nil
            return reading
        }
        let ticks = cpu.cpu_ticks // user, system, idle, nice
        defer { lastTicks = ticks }
        if let previous = lastTicks {
            let busy = UInt64(ticks.0 &- previous.0) + UInt64(ticks.1 &- previous.1) + UInt64(ticks.3 &- previous.3)
            let total = busy + UInt64(ticks.2 &- previous.2)
            if total > 0 {
                reading.cpuPercent = Int((100 * Double(busy) / Double(total)).rounded())
            }
        }
        return reading
    }
}
