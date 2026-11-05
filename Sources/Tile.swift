import AppKit

final class Tile: NSView {
    var reading = SystemReading()

    var pages = Page.initial
    var dark = true
    var history: [CPUSample] = []
    var power = PowerReading()
    private var ink: NSColor { dark ? .white : NSColor(white: 0.12, alpha: 1) }
    private var railColor: NSColor { ink.withAlphaComponent(dark ? 0.20 : 0.14) }
    private var cool: NSColor { dark ? .systemTeal : NSColor(srgbRed: 0.0, green: 0.38, blue: 0.42, alpha: 1) }
    private var warm: NSColor { dark ? .systemOrange : NSColor(srgbRed: 0.59, green: 0.26, blue: 0.03, alpha: 1) }
    var connection = ConnectionReading()
    var position: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: bounds.width / 128, y: bounds.height / 128)
        let shape = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 120, height: 120),
                                 xRadius: 26, yRadius: 26)
        shape.addClip()
        let top = dark ? NSColor(srgbRed: 0.14, green: 0.17, blue: 0.19, alpha: 1)
                       : NSColor(srgbRed: 0.99, green: 0.98, blue: 0.94, alpha: 1)
        let bottom = dark ? NSColor(srgbRed: 0.06, green: 0.08, blue: 0.10, alpha: 1)
                          : NSColor(srgbRed: 0.86, green: 0.85, blue: 0.81, alpha: 1)
        NSGradient(starting: bottom, ending: top)?.draw(in: shape.bounds, angle: 90)
        shape.lineWidth = 2
        let base = Int(floor(position))
        for slot in base...(base + 1) {
            let distance = CGFloat(slot) - position
            guard abs(distance) < 1 else { continue }
            context.saveGState()
            context.translateBy(x: 64, y: 64 - distance * 117)
            context.scaleBy(x: 1 - 0.06 * abs(distance), y: 1 - 0.20 * abs(distance))
            context.translateBy(x: -64, y: -64)
            switch pages[Page.index(slot, count: pages.count)] {
            case .system: summary()
            case .storage: storage()
            case .network: network()
            case .cpuHistory: cpuHistory()
            case .power: battery()
            }
            context.restoreGState()
        }
        // The stationary lip casts a shadow across the moving drum.
        NSGradient(starting: .clear, ending: .black.withAlphaComponent(dark ? 0.54 : 0.18))?
            .draw(in: NSRect(x: 4, y: 100, width: 120, height: 24), angle: 90)
        ink.withAlphaComponent(0.24).setStroke()
        shape.stroke()
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor? = nil) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color ?? ink
        ]
        let string = text as NSString
        let extent = string.size(withAttributes: attributes)
        string.draw(at: NSPoint(x: x - extent.width / 2, y: y - extent.height / 2),
                    withAttributes: attributes)
    }


    private func storage() {
        label("СВОБОДНО", x: 64, y: 103, size: 16, weight: .bold)
        label(connection.freeGB + " ГБ", x: 64, y: 77, size: connection.freeGB.count > 3 ? 25 : 31, weight: .heavy)
        divider(at: 60)
        label("Wi-Fi · IPv4", x: 64, y: 48, size: 14, weight: .medium)
        if let ip = connection.wifiIP {
            // Split at an octet boundary so the full address fits a small Dock.
            let parts = ip.split(separator: ".")
            if ip.count > 11 && parts.count == 4 {
                label(parts.prefix(2).joined(separator: ".") + ".", x: 64, y: 32, size: 17, weight: .bold)
                label(parts.suffix(2).joined(separator: "."), x: 64, y: 16, size: 17, weight: .bold)
            } else {
                label(ip, x: 64, y: 26, size: 17, weight: .bold)
            }
        } else {
            label("—", x: 64, y: 25, size: 20, weight: .bold)
        }
    }

    private func network() {
        label("СЕТЬ", x: 64, y: 103, size: 18, weight: .bold)
        rate(connection.receive, arrow: "↓", y: 80, color: cool)
        divider(at: 54)
        rate(connection.send, arrow: "↑", y: 34, color: warm)
    }

    private func rate(_ text: String, arrow: String, y: CGFloat, color: NSColor) {
        let parts = text.split(separator: " ")
        (arrow as NSString).draw(at: NSPoint(x: 15, y: y - 16), withAttributes: [
            .foregroundColor: color, .font: NSFont.systemFont(ofSize: 25, weight: .bold)
        ])
        label(parts.first.map(String.init) ?? "—", x: 73, y: y + 1, size: 28, weight: .heavy)
        if parts.count == 2 { label(String(parts[1]), x: 73, y: y - 19, size: 14, weight: .medium) }
    }

    private func divider(at y: CGFloat) {
        railColor.setFill()
        NSRect(x: 20, y: y, width: 88, height: 1.5).fill()
    }

    private func battery() {
        label("ПИТАНИЕ", x: 64, y: 102, size: 18, weight: .bold)
        label(power.percent.map { String($0) + "%" } ?? "—", x: 64, y: 74, size: 37, weight: .heavy)
        let track = NSRect(x: 22, y: 49, width: 84, height: 8)
        railColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
        if let percent = power.percent, percent > 0 {
            (percent <= 20 ? warm : cool).setFill()
            let fill = NSRect(x: track.minX, y: track.minY, width: track.width * CGFloat(percent)/100, height: track.height)
            NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
        }
        label(power.status, x: 64, y: 28, size: 17, weight: .bold)
    }

    private func cpuHistory() {
        label("CPU · 60 с", x: 64, y: 101, size: 19, weight: .bold)
        label(reading.cpu, x: 64, y: 73, size: 35, weight: .heavy)
        let chart = NSRect(x: 18, y: 19, width: 92, height: 34)
        railColor.setFill()
        NSBezierPath(roundedRect: chart, xRadius: 3, yRadius: 3).fill()
        guard let now = history.last?.time else { return }
        cool.setFill()
        for sample in history {
            guard let value = sample.percent else { continue }
            let x = chart.maxX - 4 - CGFloat(now - sample.time) / 60 * (chart.width - 4)
            guard x >= chart.minX else { continue }
            let height = max(1.5, chart.height * CGFloat(value) / 100)
            NSBezierPath(roundedRect: NSRect(x: x, y: chart.minY, width: 3.8, height: height),
                         xRadius: 1, yRadius: 1).fill()
        }
    }

    private func summary() {
        label("SWAP · " + reading.unit, x: 64, y: 102, size: 19, weight: .bold)
        label(reading.swap, x: 64, y: 73, size: reading.swap.count > 4 ? 33 : 44, weight: .heavy)
        label("MEM", x: 33, y: 42, size: 16, weight: .bold)
        let color: NSColor
        switch reading.pressure {
        case .normal: color = dark ? .systemGreen : NSColor(srgbRed: 0.12, green: 0.48, blue: 0.19, alpha: 1)
        case .warning: color = dark ? .systemYellow : NSColor(srgbRed: 0.63, green: 0.43, blue: 0.04, alpha: 1)
        case .critical: color = .systemRed
        case nil: color = .clear
        }
        for index in 0..<3 {
            let active = index < (reading.pressure?.segments ?? 0)
            (active ? color : railColor).setFill()
            let rect = NSRect(x: 56 + 20 * index, y: 37, width: 17, height: 10)
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }

        label("CPU", x: 33, y: 23, size: 16, weight: .bold)
        let track = NSRect(x: 56, y: 18, width: 57, height: 10)
        let rail = NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3)
        railColor.setFill()
        rail.fill()
        if let percent = reading.cpuPercent {
            let load = CGFloat(percent) / 100
            let intensity: CGFloat = dark ? 1 : 0.69
            NSColor(srgbRed: intensity * min(1, 0.24 + 1.52 * load),
                    green: intensity * min(0.88, 0.22 + 1.32 * (1 - load)),
                    blue: 0.25, alpha: 1).setFill()
            rail.addClip()
            NSRect(x: track.minX, y: track.minY, width: track.width * load, height: track.height).fill()
        }
    }
}
