import AppKit

final class Tile: NSView {
    var reading = SystemReading()

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

        func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor.white
            ]
            let string = text as NSString
            let extent = string.size(withAttributes: attributes)
            string.draw(at: NSPoint(x: x - extent.width / 2, y: y - extent.height / 2),
                        withAttributes: attributes)
        }

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
