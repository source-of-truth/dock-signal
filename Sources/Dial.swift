import AppKit
import ApplicationServices

final class Dial {
    private(set) var pages = Page.initial
    var draw: (CGFloat) -> Void = { _ in }
    private(set) var page = 0
    private var position: CGFloat = 0
    private var start: CGFloat = 0
    private var destination: CGFloat = 0
    private var started: TimeInterval = 0
    private var timer: Timer?
    private var monitor: Any?
    private var dock: NSRunningApplication?
    private let system = AXUIElementCreateSystemWide()
    private var dragging = false
    private var accumulated: CGFloat = 0
    private var lastWheel = -Double.infinity
    private var wheelInside = false
    private var lastWheelEvent = -Double.infinity
    private var preciseWheelTurned = false

    func updatePermission() {
        guard pages.count > 1, AXIsProcessTrusted() else {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            if dragging { dragging = false; settle(at: page) }
            return
        }
        guard monitor == nil else { return }
        AXUIElementSetMessagingTimeout(system, 0.08)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.scroll(event)
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        timer?.invalidate()
    }

    private func overIcon(_ event: NSEvent) -> Bool {
        guard let point = event.cgEvent?.location, AXIsProcessTrusted() else { return false }
        // Skip accessibility IPC for scrolls away from the three possible Dock edges.
        let location = NSEvent.mouseLocation
        guard NSScreen.screens.contains(where: { screen in
            let r = screen.frame
            return r.contains(location) && min(location.x - r.minX, r.maxX - location.x, location.y - r.minY) < 320
        }) else { return false }
        var element: AXUIElement?
        if dock?.isTerminated != false {
            dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        }
        var pid: pid_t = 0
        guard let dock, AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success,
              let element, AXUIElementGetPid(element, &pid) == .success, pid == dock.processIdentifier else { return false }
        func attribute(_ node: AXUIElement, _ key: String) -> CFTypeRef? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(node, key as CFString, &result) == .success else { return nil }
            return result
        }
        var node = element
        for _ in 0..<4 {
            if attribute(node, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
               let url = attribute(node, kAXURLAttribute) as? URL {
                return url.standardizedFileURL.resolvingSymlinksInPath().path ==
                    Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
            }
            guard let parent = attribute(node, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            node = parent as! AXUIElement
        }
        return false
    }

    private func scroll(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let phase = event.phase
        if !phase.isEmpty {
            if phase.contains(.began) {
                dragging = overIcon(event)
                if dragging {
                    stopAnimation()
                    start = CGFloat(Int(position.rounded()))
                    accumulated = position - start
                }
            }
            guard dragging else { return }
            if phase.contains(.cancelled) {
                dragging = false
                settle(at: Int(start))
                return
            }
            accumulated = max(-1, min(1, accumulated - event.scrollingDeltaY / 80))
            let next = start + accumulated
            if next != position && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                position = next
                draw(position)
            }
            if phase.contains(.ended) {
                dragging = false
                let step = abs(accumulated) >= 0.23 ? (accumulated > 0 ? 1 : -1) : 0
                settle(at: Int(start) + step)
            }
            return
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let now = event.timestamp
        let newBurst = now - lastWheelEvent > 0.18
        lastWheelEvent = now
        if newBurst { preciseWheelTurned = false; accumulated = 0 }
        guard now - lastWheel > 0.12 else { return }
        if event.hasPreciseScrollingDeltas {
            if newBurst { wheelInside = overIcon(event) }
            guard wheelInside, !preciseWheelTurned else { return }
            accumulated -= delta / 80
            guard abs(accumulated) >= 0.23 else { return }
            preciseWheelTurned = true
        } else if !overIcon(event) { return }
        lastWheel = now
        let direction = event.hasPreciseScrollingDeltas ? accumulated : -delta
        settle(at: Int(destination.rounded()) + (direction > 0 ? 1 : -1))
    }

    func configure(_ enabled: [Page]) {
        guard !enabled.isEmpty else { return }
        let current = pages[page]
        pages = enabled
        dragging = false
        preciseWheelTurned = false
        wheelInside = false
        lastWheelEvent = -Double.infinity
        page = pages.firstIndex(of: current) ?? 0
        finish()
    }

    func select(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        dragging = false
        let current = Int(position.rounded())
        let forward = Page.index(index - current, count: pages.count)
        let step = forward * 2 <= pages.count ? forward : forward - pages.count
        settle(at: current + step)
    }

    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }

    private func settle(at target: Int) {
        stopAnimation()
        destination = CGFloat(target)
        page = Page.index(target, count: pages.count)
        if abs(destination - position) < 0.001 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            finish()
            return
        }
        start = position
        started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 45, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let t = min(1, (ProcessInfo.processInfo.systemUptime - started) / 0.24)
        if t >= 1 { finish(); return }
        position = start + (destination - start) * (1 - pow(1 - t, 3))
        draw(position)
    }

    private func finish() {
        stopAnimation()
        position = CGFloat(page)
        destination = position
        draw(position)
    }
}
