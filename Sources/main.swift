import AppKit

final class Controller: NSObject, NSApplicationDelegate {
    private let dial = Dial()
    private let network = NetworkMeter()
    private let meter = SystemMeter()
    private let tile = Tile(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    private let detail = NSTextField(labelWithString: "")
    private var window: NSWindow?
    private var settings: NSWindow?
    private var checks: [Page: NSButton] = [:]
    private var appearanceObserver: NSKeyValueObservation?
    private var lastPowerSample = -Double.infinity
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let root = NSMenuItem()
        menu.addItem(root)
        let actions = NSMenu()
        root.submenu = actions
        actions.addItem(detailsItem())
        actions.addItem(settingsItem(shortcut: ","))
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
        applyPages(Page.load())
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] app, _ in
            self?.tile.dark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            app.dockTile.display()
        }
        if dial.pages.count > 1, !AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey: "didOfferScrollPermission") {
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
        let now = Date.timeIntervalSinceReferenceDate
        if dial.pages.contains(.cpuHistory) {
            tile.history.removeAll { now - $0.time > 60 || $0.time > now }
            tile.history.append(CPUSample(time: now, percent: reading.cpuPercent))
        }
        let oldPower = tile.power
        let uptime = ProcessInfo.processInfo.systemUptime
        if dial.pages.contains(.power), uptime - lastPowerSample >= 30 {
            tile.power = PowerReading.sample()
            lastPowerSample = uptime
        }
        let redraw: Bool
        switch dial.pages[dial.page] {
        case .system: redraw = tile.reading != reading
        case .storage: redraw = tile.connection.freeGB != connection.freeGB || tile.connection.wifiIP != connection.wifiIP
        case .cpuHistory: redraw = true
        case .power: redraw = oldPower != tile.power
        case .network: redraw = tile.connection.receive != connection.receive || tile.connection.send != connection.send
        }
        tile.connection = connection
        tile.reading = reading
        if force || redraw { NSApp.dockTile.display() }
        updateDetails()
    }

    private func updateDetails() {
        let reading = tile.reading
        let connection = tile.connection
        detail.stringValue = "Занято свопа: " + reading.swap + " " + reading.unit
            + "\nНагрузка на память: " + (reading.pressure?.description ?? "Нет данных")
            + "\nЗагрузка CPU: " + reading.cpu
            + "\nСвободно на диске: " + connection.freeGB + " ГБ"
            + "\nWi-Fi IPv4: " + (connection.wifiIP ?? "—")
            + "\nСеть ↓ " + connection.receive + "   ↑ " + connection.send
        if dial.pages.contains(.power) {
            let level = tile.power.percent.map { String($0) + "% · " } ?? ""
            detail.stringValue += "\nПитание: " + level + tile.power.status
        }
    }

    private func detailsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Показатели системы", action: #selector(show), keyEquivalent: "")
        item.target = self
        return item
    }

    private func addNavigation(to menu: NSMenu) {
        menu.addItem(.separator())
        for (index, page) in dial.pages.enumerated() {
            let item = menu.addItem(withTitle: page.title, action: #selector(selectPage(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == dial.page ? .on : .off
        }
        if dial.pages.count > 1, !AXIsProcessTrusted() {
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
        menu.addItem(.separator())
        menu.addItem(settingsItem(shortcut: ""))
        return menu
    }

    private func settingsItem(shortcut: String) -> NSMenuItem {
        let item = NSMenuItem(title: "Настроить страницы…", action: #selector(showSettings), keyEquivalent: shortcut)
        item.target = self
        return item
    }

    private func applyPages(_ pages: [Page]) {
        tile.pages = pages
        if !pages.contains(.cpuHistory) { tile.history.removeAll() }
        if !pages.contains(.power) { lastPowerSample = -Double.infinity }
        else if !dial.pages.contains(.power) {
            tile.power = PowerReading.sample()
            lastPowerSample = ProcessInfo.processInfo.systemUptime
        }
        dial.configure(pages)
        updateDetails()
        dial.updatePermission()
        for (page, button) in checks {
            let on = pages.contains(page)
            button.state = on ? .on : .off
            button.isEnabled = !on || pages.count > 1
        }
    }

    @objc private func togglePage(_ sender: NSButton) {
        guard let page = checks.first(where: { $0.value === sender })?.key else { return }
        let pages = Page.allCases.filter { $0 == page ? sender.state == .on : dial.pages.contains($0) }
        guard !pages.isEmpty else { sender.state = .on; return }
        UserDefaults.standard.set(pages.map(\.rawValue), forKey: Page.preference)
        applyPages(pages)
    }

    @objc private func showSettings() {
        if settings == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 290, height: 218),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Страницы в Dock"
            panel.isReleasedWhenClosed = false
            for (i, page) in Page.allCases.enumerated() {
                let button = NSButton(checkboxWithTitle: page.title, target: self, action: #selector(togglePage(_:)))
                button.frame = NSRect(x: 24, y: 171 - 36 * i, width: 245, height: 24)
                let on = dial.pages.contains(page)
                button.state = on ? .on : .off
                button.isEnabled = !on || dial.pages.count > 1
                panel.contentView?.addSubview(button)
                checks[page] = button
            }
            panel.center()
            settings = panel
        }
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    let power = PowerReading.sample()
    print("POWER", power.percent.map { String($0) + "%" } ?? "—", power.status)
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
