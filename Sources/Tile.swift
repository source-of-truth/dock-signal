import AppKit

final class Tile: NSView {
    var reading = SystemReading()

    var connection = ConnectionReading()
    var position: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: bounds.width / 128, y: bounds.height / 128)
        let shape = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 120, height: 120),
                                 xRadius: 26, yRadius: 26)
        NSColor(srgbRed: 0.08, green: 0.11, blue: 0.14, alpha: 1).setFill()
        shape.fill()
        NSColor.white.withAlphaComponent(0.24).setStroke()
        shape.lineWidth = 1.5
        shape.stroke()

        shape.addClip()
        let base = Int(floor(position))
        for slot in base...(base + 1) {
            let distance = CGFloat(slot) - position
            guard abs(distance) < 1 else { continue }
            context.saveGState()
            context.translateBy(x: 64, y: 64 - distance * 117)
            context.scaleBy(x: 1 - 0.06 * abs(distance), y: 1 - 0.20 * abs(distance))
            context.translateBy(x: -64, y: -64)
            switch Dial.index(slot) {
            case 0: summary()
            case 1: storage()
            default: network()
            }
            context.restoreGState()
        }
        // The stationary lip casts a shadow across the moving drum.
        NSGradient(starting: .clear, ending: .black.withAlphaComponent(0.54))?
            .draw(in: NSRect(x: 4, y: 100, width: 120, height: 24), angle: 90)
        NSColor.white.withAlphaComponent(0.20).setStroke()
        shape.stroke()
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white
        ]
        let string = text as NSString
        let extent = string.size(withAttributes: attributes)
        string.draw(at: NSPoint(x: x - extent.width / 2, y: y - extent.height / 2),
                    withAttributes: attributes)
    }


    private func storage() {
        label("ДИСК · ГБ", x: 64, y: 102, size: 18, weight: .bold)
        label(connection.freeGB, x: 64, y: 75, size: 39, weight: .heavy)
        label("Wi-Fi · IPv4", x: 64, y: 47, size: 15, weight: .medium)
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
        rate(connection.receive, arrow: "↓", y: 76, color: .systemTeal)
        rate(connection.send, arrow: "↑", y: 34, color: .systemOrange)
    }

    private func rate(_ text: String, arrow: String, y: CGFloat, color: NSColor) {
        let parts = text.split(separator: " ")
        (arrow as NSString).draw(at: NSPoint(x: 15, y: y - 16), withAttributes: [
            .foregroundColor: color, .font: NSFont.systemFont(ofSize: 25, weight: .bold)
        ])
        label(parts.first.map(String.init) ?? "—", x: 73, y: y + 1, size: 28, weight: .heavy)
        if parts.count == 2 { label(String(parts[1]), x: 73, y: y - 19, size: 14, weight: .medium) }
    }

    private func summary() {
        label("SWAP · " + reading.unit, x: 64, y: 102, size: 19, weight: .bold)
        label(reading.swap, x: 64, y: 73, size: reading.swap.count > 4 ? 33 : 44, weight: .heavy)
        label("MEM", x: 33, y: 42, size: 16, weight: .bold)
        let color: NSColor
        switch reading.pressure {
        case .normal: color = .systemGreen
        case .warning: color = .systemYellow
        case .critical: color = .systemRed
        case nil: color = .clear
        }
        for index in 0..<3 {
            let active = index < (reading.pressure?.segments ?? 0)
            (active ? color : NSColor.white.withAlphaComponent(0.2)).setFill()
            let rect = NSRect(x: 56 + 20 * index, y: 37, width: 17, height: 10)
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        }

        label("CPU", x: 33, y: 23, size: 16, weight: .bold)
        let track = NSRect(x: 56, y: 18, width: 57, height: 10)
        let rail = NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3)
        NSColor.white.withAlphaComponent(0.2).setFill()
        rail.fill()
        if let percent = reading.cpuPercent {
            let load = CGFloat(percent) / 100
            NSColor(srgbRed: min(1, 0.24 + 1.52 * load),
                    green: min(0.88, 0.22 + 1.32 * (1 - load)),
                    blue: 0.25, alpha: 1).setFill()
            rail.addClip()
            NSRect(x: track.minX, y: track.minY, width: track.width * load, height: track.height).fill()
        }
    }
}
