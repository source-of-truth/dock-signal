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

    static func current() -> Self {
        var reading = Self()
        var usage = xsw_usage()
        var size = MemoryLayout.size(ofValue: usage)
        if sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 {
            let bytes = usage.xsu_used
            if bytes > 0 && bytes < 1_000_000_000 {
                reading.swap = String(format: "%.0f", Double(bytes) / 1e6)
                reading.unit = "МБ"
            } else {
                reading.swap = String(format: "%.1f", Double(bytes) / 1e9)
            }
        }

        var level: Int32 = 0
        size = MemoryLayout.size(ofValue: level)
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            reading.pressure = MemoryPressure(rawValue: level)
        }
        return reading
    }
}
