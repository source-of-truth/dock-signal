import AppKit

final class Controller: NSObject, NSApplicationDelegate {
    private let dial = Dial()
    private let network = NetworkMeter()
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
        dial.draw = { [weak self] position in
            self?.tile.position = position
            NSApp.dockTile.display()
        }
        if !AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey: "didOfferScrollPermission") {
            UserDefaults.standard.set(true, forKey: "didOfferScrollPermission")
            enableScroll()
        }
        refresh(force: true)
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh(force: Bool = false) {
        dial.updatePermission()
        let reading = meter.sample()
        let connection = network.sample()
        guard force || tile.reading != reading || tile.connection != connection else { return }
        let redraw: Bool
        switch dial.page {
        case 0: redraw = tile.reading != reading
        case 1: redraw = tile.connection.freeGB != connection.freeGB || tile.connection.wifiIP != connection.wifiIP
        default: redraw = tile.connection.receive != connection.receive || tile.connection.send != connection.send
        }
        tile.connection = connection
        tile.reading = reading
        if force || redraw { NSApp.dockTile.display() }
        detail.stringValue = "Занято свопа: " + reading.swap + " " + reading.unit
            + "\nНагрузка на память: " + (reading.pressure?.description ?? "Нет данных")
            + "\nЗагрузка CPU: " + reading.cpu
            + "\nСвободно на диске: " + connection.freeGB + " ГБ"
            + "\nWi-Fi IPv4: " + (connection.wifiIP ?? "—")
            + "\nСеть ↓ " + connection.receive + "   ↑ " + connection.send
    }

    private func detailsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Показатели системы", action: #selector(show), keyEquivalent: "")
        item.target = self
        return item
    }

    private func addNavigation(to menu: NSMenu) {
        menu.addItem(.separator())
        for (index, title) in Dial.titles.enumerated() {
            let item = menu.addItem(withTitle: title, action: #selector(selectPage(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == dial.page ? .on : .off
        }
        if !AXIsProcessTrusted() {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Включить прокрутку…", action: #selector(enableScroll), keyEquivalent: "").target = self
        }
    }

    @objc private func selectPage(_ sender: NSMenuItem) { dial.select(sender.tag) }

    @objc private func enableScroll() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(detailsItem())
        addNavigation(to: menu)
        return menu
    }

    @objc func show() {
        if window == nil {
            let size = NSRect(x: 0, y: 0, width: 395, height: 194)
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
    let network = NetworkMeter()
    _ = network.sample()
    _ = meter.sample()
    Thread.sleep(forTimeInterval: 1)
    let reading = meter.sample()
    print("SWAP", reading.swap, reading.unit, "MEM", reading.pressure?.description ?? "Нет данных", "CPU", reading.cpu)
    let connection = network.sample()
    print("FREE GB", connection.freeGB, "Wi-Fi IPv4", connection.wifiIP ?? "—",
          "RX", connection.receive, "TX", connection.send)
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
