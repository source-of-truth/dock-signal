import AppKit

final class Controller: NSObject, NSApplicationDelegate {
    private let meter = SystemMeter()
    private let tile = Tile(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    private let detail = NSTextField(labelWithString: "")
    private var window: NSWindow?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let root = NSMenuItem()
        menu.addItem(root)
        let actions = NSMenu()
        root.submenu = actions
        actions.addItem(detailsItem())
        actions.addItem(.separator())
        actions.addItem(withTitle: "Завершить Dock Signal",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        tile.autoresizingMask = [.width, .height]
        NSApp.dockTile.contentView = tile
        refresh(force: true)
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh(force: Bool = false) {
        let reading = meter.sample()
        guard force || tile.reading != reading else { return }
        tile.reading = reading
        NSApp.dockTile.display()
        detail.stringValue = "Занято свопа: " + reading.swap + " " + reading.unit
            + "\nНагрузка на память: " + (reading.pressure?.description ?? "Нет данных")
            + "\nЗагрузка CPU: " + reading.cpu
    }

    private func detailsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Показатели системы", action: #selector(show), keyEquivalent: "")
        item.target = self
        return item
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(detailsItem())
        return menu
    }

    @objc func show() {
        if window == nil {
            let size = NSRect(x: 0, y: 0, width: 365, height: 125)
            let panel = NSWindow(contentRect: size, styleMask: [.titled, .closable, .miniaturizable],
                                 backing: .buffered, defer: false)
            panel.title = "Dock Signal"
            panel.isReleasedWhenClosed = false
            detail.font = .systemFont(ofSize: 16)
            detail.frame = size.insetBy(dx: 22, dy: 18)
            panel.contentView?.addSubview(detail)
            panel.center()
            window = panel
        }
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }
}

if CommandLine.arguments.contains("--check") {
    let meter = SystemMeter()
    _ = meter.sample()
    Thread.sleep(forTimeInterval: 1)
    let reading = meter.sample()
    print("SWAP", reading.swap, reading.unit, "MEM", reading.pressure?.description ?? "Нет данных", "CPU", reading.cpu)
    exit(0)
}

let app = NSApplication.shared
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--icon" {
    let tile = Tile(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    tile.draw(tile.bounds)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}

let controller = Controller()
app.setActivationPolicy(.regular)
app.delegate = controller
app.run()
