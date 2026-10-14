import AppKit
import IOKit
import IOKit.pwr_mgt
import CoreGraphics

struct HotCornerConfiguration: Equatable {
    static let corners = ["tl", "tr", "bl", "br"]
    static let titles = ["tl": "左上角", "tr": "右上角", "bl": "左下角", "br": "右下角"]
    var actions: [String: Int] = [:]
    var modifiers: [String: UInt] = [:]
    var departureCorners: [String] { Self.corners.filter { actions[$0] == 10 || actions[$0] == 13 } }
    mutating func refresh() {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        for c in Self.corners {
            actions[c] = (CFPreferencesCopyAppValue("wvous-\(c)-corner" as CFString, "com.apple.dock" as CFString) as? NSNumber)?.intValue ?? 0
            modifiers[c] = (CFPreferencesCopyAppValue("wvous-\(c)-modifier" as CFString, "com.apple.dock" as CFString) as? NSNumber)?.uintValue ?? 0
        }
    }
    var description: String {
        Self.corners.map { c in
            let value = actions[c] ?? 0
            let name = [0: "未设置", 1: "未设置", 2: "调度中心", 3: "应用窗口", 4: "桌面", 5: "屏保", 6: "停用屏保", 10: "显示器睡眠", 13: "锁屏", 14: "快速备忘录"][value] ?? "动作 \(value)"
            return "\(Self.titles[c]!): \(name)"
        }.joined(separator: " · ")
    }
}

/// No keyboard event registration, event tap, screen capture, or Accessibility API.
final class SystemMonitor {
    var receive: ((Input, Date) -> Void)?
    var diagnostic: ((String, String) -> Void)?
    var settings = AppSettings() {
        didSet {
            if oldValue.corner != settings.corner {
                rebuildTargets()
                inside = nil
                receive?(.cornerExited, Date())
            }
        }
    }
    private(set) var configuration = HotCornerConfiguration()
    private(set) var mouseEventCount = 0
    private(set) var lastMouseEvent: Date?
    private(set) var lastLid: Bool?
    private(set) var lidRegistration: Int32 = -1
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var ioPort: IONotificationPortRef?
    private var root: io_service_t = 0
    private var notifier: io_object_t = 0
    private var inside: String?
    private var lastActivity = Date.distantPast
    private var frames: [(String, CGRect)] = []
    private var cornerTargets: [HotCornerTarget] = []
    private var settleTask: DispatchWorkItem?
    private var lastObservedIdle = false
    private var started = false

    var idleSeconds: Double {
        let anyInput = CGEventType(rawValue: UInt32.max)!
        let value = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return value.isFinite ? value : 0
    }
    var screenLocked: Bool {
        let dict = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (dict?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
    var screenAwake: Bool {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &displays, &count) == .success else { return true }
        return displays.prefix(Int(count)).contains { CGDisplayIsAsleep($0) == 0 }
    }
    func refreshConfiguration() {
        let previous = configuration
        configuration.refresh()
        if frames.isEmpty || previous != configuration { updateScreens() }
    }
    private func updateScreens() {
        frames = NSScreen.screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "unknown"
            return (id, screen.frame)
        }
        rebuildTargets()
        inside = nil
        receive?(.cornerExited, Date())
    }
    private func rebuildTargets() {
        let selected = settings.corner == "auto" ? configuration.departureCorners : [settings.corner]
        cornerTargets = HotCornerGeometry.targets(screens: frames, corners: selected,
                                                 requiredModifiers: configuration.modifiers)
    }
    private func matchedCorner(point: CGPoint, modifiers: UInt) -> (String, String)? {
        HotCornerGeometry.match(point: point, targets: cornerTargets, modifiers: modifiers)
    }
    private func mouse(_ event: NSEvent) {
        mouseEventCount += 1
        if mouseEventCount == 1 { diagnostic?("mouse_listener_alive", "first mouse event delivered; no keyboard monitor registered") }
        let now = Date()
        lastMouseEvent = now
        let point = NSEvent.mouseLocation
        if let (corner, screen) = matchedCorner(point: point, modifiers: event.modifierFlags.rawValue) {
            let identity = "\(screen):\(corner)"
            if inside != identity {
                inside = identity
                receive?(.cornerEntered(name: corner, screen: screen, x: point.x, y: point.y, uptime: event.timestamp), now)
            }
        } else if inside != nil {
            inside = nil; receive?(.cornerExited, now)
        }
        if now.timeIntervalSince(lastActivity) > 2 {
            lastActivity = now
            receive?(.userActivity, now)
        }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
        observers.append((center, token))
    }
    private func scheduleConfirmation() {
        settleTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.settleTask = nil
            self?.receive?(.confirmSleep, Date())
        }
        settleTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: task)
    }
    private func observeLock() {
        refreshLid()
        receive?(.lockObserved(uptime: ProcessInfo.processInfo.systemUptime, idleSeconds: idleSeconds,
                               stillInCorner: matchedCorner(point: NSEvent.mouseLocation, modifiers: NSEvent.modifierFlags.rawValue) != nil), Date())
        inside = nil
        scheduleConfirmation()
    }
    private func observeSessionResign() {
        // sessionDidResignActive can precede the distributed lock notification,
        // and it can also mean Fast User Switching. Let the session dictionary
        // settle before deciding whether lock heuristics apply.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            if self.screenLocked { self.observeLock() }
            else { self.receive?(.lock, Date()) }
        }
    }
    func start() {
        guard !started else { return }
        started = true
        refreshConfiguration()
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] in self?.mouse($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.mouse(event); return event }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            guard let self else { return }
            self.refreshLid()
            let point = NSEvent.mouseLocation
            self.receive?(.displaySleep(uptime: ProcessInfo.processInfo.systemUptime, idleSeconds: self.idleSeconds,
                                       stillInCorner: self.matchedCorner(point: point, modifiers: NSEvent.modifierFlags.rawValue) != nil), Date())
            self.inside = nil
            self.scheduleConfirmation()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.refreshLid(); self?.receive?(.displayWake, Date()); self?.inside = nil
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.lastActivity = Date()
            self?.refreshLid(); self?.receive?(.systemSleep, Date())
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.refreshLid(); self?.receive?(.systemWake, Date())
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.observeSessionResign() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.receive?(.unlock, Date()) }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.updateScreens(); self?.diagnostic?("display_topology", "updated NSScreen frames; candidate invalidated")
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.observeLock() }
        for (name, input) in [
            ("com.apple.screenIsUnlocked", Input.unlock),
            ("com.apple.screensaver.didstart", .screenSaverStarted),
            ("com.apple.screensaver.didstop", .screenSaverStopped)
        ] {
            observe(distributed, Notification.Name(name)) { [weak self] in self?.receive?(input, Date()) }
        }
        root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        ioPort = IONotificationPortCreate(kIOMainPortDefault)
        if root != 0, let port = ioPort {
            IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
            lidRegistration = IOServiceAddInterestNotification(port, root, kIOGeneralInterest, { ref, _, message, _ in
                guard let ref else { return }
                let monitor = Unmanaged<SystemMonitor>.fromOpaque(ref).takeUnretainedValue()
                monitor.refreshLid()
            }, Unmanaged.passUnretained(self).toOpaque(), &notifier)
        }
        refreshLid()
        diagnostic?("monitor_start", "mouseGlobal=\(globalMonitor != nil) lidRegistration=\(lidRegistration) lid=\(String(describing: lastLid)) screens=\(frames.count) departureCorners=\(configuration.departureCorners) idleSeconds=\(idleSeconds) \(configuration.description)")
        if screenLocked { receive?(.lock, Date()) }
        if !screenAwake {
            receive?(.displaySleep(uptime: ProcessInfo.processInfo.systemUptime, idleSeconds: idleSeconds, stillInCorner: false), Date())
        } else if !screenLocked && lastLid != true {
            receive?(.userActivity, Date())
            if idleSeconds >= settings.idleMinutes * 60 { receive?(.idle, Date()) }
        }
    }
    func refreshLid() {
        guard root != 0, let raw = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else { return }
        let closed = raw.boolValue
        if lastLid != closed {
            let initial = lastLid == nil
            lastLid = closed
            if closed {
                lastActivity = Date()
                receive?(.lidClosed, Date())
            }
            else if !initial { receive?(.lidOpened, Date()) }
        }
    }
    /// 15s coarse aggregate idle check; never samples keyboard keys or text.
    func activityTick() {
        let idle = idleSeconds
        let nowIdle = idle >= settings.idleMinutes * 60
        if nowIdle && !lastObservedIdle { receive?(.idle, Date()) }
        let inputTime = Date().addingTimeInterval(-idle)
        if !nowIdle && idle < 16 && inputTime > lastActivity {
            lastActivity = inputTime
            receive?(.userActivity, Date())
        }
        lastObservedIdle = nowIdle
    }
    func stop() {
        settleTask?.cancel()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        if notifier != 0 { IOObjectRelease(notifier) }
        if root != 0 { IOObjectRelease(root) }
        if let ioPort { IONotificationPortDestroy(ioPort) }
        notifier = 0; root = 0; ioPort = nil; started = false
    }
}
