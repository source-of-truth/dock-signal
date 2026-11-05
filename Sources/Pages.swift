import Foundation
import IOKit.ps

enum Page: String, CaseIterable {
    case system, storage, network, cpuHistory, power

    static let initial: [Page] = [.system, .storage, .network]
    static let preference = "enabledPages"

    static func load(from defaults: UserDefaults = .standard) -> [Page] {
        guard let ids = defaults.stringArray(forKey: preference) else { return initial }
        let pages = allCases.filter { ids.contains($0.rawValue) }
        return pages.isEmpty ? initial : pages
    }

    var title: String {
        switch self {
        case .system: return "Система"
        case .storage: return "Диск и Wi-Fi"
        case .network: return "Скорость сети"
        case .cpuHistory: return "CPU за минуту"
        case .power: return "Питание"
        }
    }

    static func index(_ slot: Int, count: Int) -> Int { (slot % count + count) % count }
}

struct CPUSample: Equatable {
    let time: TimeInterval
    let percent: Int?
}

struct PowerReading: Equatable {
    var percent: Int?
    var status = "Нет данных"

    static func sample() -> Self {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return Self() }
        for source in list {
            guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            var reading = Self()
            if let current = data[kIOPSCurrentCapacityKey] as? Int,
               let total = data[kIOPSMaxCapacityKey] as? Int, total > 0, (0...total).contains(current) {
                reading.percent = Int((100 * Double(current) / Double(total)).rounded())
            }
            if data[kIOPSIsChargingKey] as? Bool == true { reading.status = "Зарядка" }
            else if data[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue { reading.status = "Адаптер" }
            else if data[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue { reading.status = "Батарея" }
            return reading
        }
        return Self(percent: nil, status: "Нет батареи")
    }
}
