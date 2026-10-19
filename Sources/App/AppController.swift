import AppKit
import Combine
import ServiceManagement
import UserNotifications
import OSLog
import UniformTypeIdentifiers

final class AppController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var revision = 0 {
        didSet { summaryCache.removeAll(keepingCapacity: true) }
    }
    @Published var state: WorkstationState = .unknown
    @Published var now = Date() {
        didSet {
            summaryCache.removeAll(keepingCapacity: true)
            if !Calendar.current.isDate(oldValue, inSameDayAs: now) { hydrationFeedback = "" }
        }
    }
    @Published var errorMessage = ""
    @Published var notificationStatus = "尚未授权"
    @Published var loginStatus = ""
    @Published var lastDecision = "等待事件"
    @Published var pendingReminder: String?
    @Published var hydrationFeedback = ""
    @Published var settings: AppSettings {
        didSet {
            summaryCache.removeAll(keepingCapacity: true)
            perform { try repository.saveSettings(settings) }
            machine.window = settings.effectiveWindow
            monitor.settings = settings
            monitor.refreshConfiguration()
            if oldValue.hydrationMinutes != settings.hydrationMinutes {
                reminders.hydrationDue = Date().addingTimeInterval(settings.hydrationMinutes * 60)
            }
            if !settings.hydrationEnabled {
                if pendingReminder == "water" { pendingReminder = nil }
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["water"])
            }
            if !settings.sedentaryEnabled {
                if pendingReminder == "sedentary" { pendingReminder = nil }
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["sedentary"])
            }
            if oldValue.launchAtLogin != settings.launchAtLogin { updateLogin() }
        }
    }
    let repository: Repository
    let ledger: SessionLedger
    let machine = WorkstationStateMachine()
    let monitor = SystemMonitor()
    private var reminders: ReminderPolicy
    private var heartbeat: Timer?
    private var focusTimer: Timer?
    private var focusDeadline: Date?
    private var heartbeatInterval: TimeInterval?
    private var lastCheckpointUptime: TimeInterval = 0
    private var lastConfigurationUptime: TimeInterval = 0
    private var lastPrunedDay = Calendar.current.startOfDay(for: Date())
    private var summaryCache: [Date: DailySummary] = [:]
    private let timelineCache = DayTimelineCache(capacity: 4)
    private var cachedEvents: (version: UInt64, rows: [SystemEvent])?
    private var cachedScreenDays: [Date: (version: UInt64, rows: [SystemEvent])] = [:]
    private let bootID: String
    private let logger = Logger(subsystem: "local.workrhythm.app", category: "events")
    var statusChanged: (() -> Void)?
    var openPage: ((String) -> Void)?
    var sessions: [Session] { ledger.sessions }
    var focuses: [FocusSession] { ledger.focuses }
    var water: [HydrationEvent] { ledger.hydration }
    var gardenTrophies: [GardenTrophy] { ledger.gardenTrophies }
    var waterProgress: HydrationProgress { HydrationProgress(events: water, plan: settings.waterPlan, date: now) }
    func updateWaterPlan(_ change: (inout HydrationPlan) -> Void) {
        var plan = settings.waterPlan
        change(&plan)
        settings.hydrationPlan = plan
        hydrationFeedback = ""
        if waterProgress.completed && pendingReminder == "water" {
            pendingReminder = nil
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["water"])
        }
        configureNotifications()
    }
    var currentFocus: FocusSession? { ledger.currentFocus }
    var lastAway: Session? { sessions.last { $0.kind == .away } }
    var focusRemaining: Double { currentFocus.map { max(0, $0.plannedDuration - $0.elapsed(at: now)) } ?? 0 }
    var today: DailySummary { summary(Date()) }
    var events: [SystemEvent] {
        if let cachedEvents, cachedEvents.version == repository.eventRevision { return cachedEvents.rows }
        guard let rows = try? repository.events() else { return [] }
        cachedEvents = (repository.eventRevision, rows)
        return rows
    }
    func refreshEvents() { cachedEvents = nil; revision += 1 }
    func screenRecords(_ day: Date) -> [ScreenRecord] {
        guard let range = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        let rows: [SystemEvent]
        if let cached = cachedScreenDays[range.start], cached.version == repository.eventRevision {
            rows = cached.rows
        } else {
            guard let result = try? repository.events(in: range) else { return [] }
            rows = result
            if cachedScreenDays.count >= 4 { cachedScreenDays.removeAll(keepingCapacity: true) }
            cachedScreenDays[range.start] = (repository.eventRevision, rows)
        }
        return ActivityRecords.screens(rows, day: day, now: now)
    }
    func timeline(_ day: Date) -> DayTimelineSnapshot {
        timelineCache.snapshot(day: day, now: now, version: ledger.timelineRevision) {
            (sessions: sessions, focuses: focuses)
        }
    }
    var cornerDescription: String { monitor.configuration.description }

    init(dataDirectory: URL? = nil) throws {
        let directory = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WorkRhythm", isDirectory: true)
        repository = try Repository(url: directory.appendingPathComponent("workrhythm.sqlite"))
        ledger = try SessionLedger(repository: repository)
        let initialSettings = try repository.settings()
        settings = initialSettings
        bootID = String(Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime)
        reminders = ReminderPolicy(now: Date(), settings: initialSettings, lastDrink: ledger.hydration.last { $0.voidedAt == nil }?.timestamp)
        super.init()
        try ledger.backfillGardenTrophies(plan: initialSettings.waterPlan)
        try ledger.recover(checkpoint: repository.checkpoint(), now: Date())
        try repository.pruneEvents(before: Date().addingTimeInterval(-30 * 86400))
        machine.window = settings.effectiveWindow
        machine.onTransition = { [weak self] in self?.transition($0) }
        machine.onDiagnostic = { [weak self] date, text in
            self?.lastDecision = text
            self?.log("classification", text, at: date)
        }
        monitor.settings = settings
        monitor.receive = { [weak self] input, date in self?.receive(input, at: date) }
        monitor.diagnostic = { [weak self] kind, text in self?.log(kind, text) }
        configureNotifications()
    }
    func start() {
        log("app_start", "version=1.1.0 build=15 schema=2; lock and lid count as departures")
        monitor.start()
        startHeartbeat()
        checkpoint()
        if settings.launchAtLogin { updateLogin() }
        refreshNotificationStatus()
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation() }
        catch {
            errorMessage = "本地数据写入失败：\(error.localizedDescription)。请保留数据库并检查磁盘空间。"
            logger.error("\(self.errorMessage, privacy: .public)")
        }
    }
    func log(_ type: String, _ text: String, at: Date = Date()) {
        logger.info("\(type, privacy: .public) \(text, privacy: .public)")
        perform { try repository.save(SystemEvent(timestamp: at, type: type, metadata: text)) }
    }
    private func receive(_ input: Input, at: Date) {
        // Activity floods aren't retained; transitions and corner edges are.
        var refresh = true
        switch input {
        case .userActivity, .idle, .cornerExited: refresh = false
        default: log("system_event", String(describing: input), at: at)
        }
        machine.handle(input, at: at)
        if case .systemSleep = input {
            checkpoint()
            focusTimer?.invalidate(); focusTimer = nil
        }
        startHeartbeat()
        if refresh { revision += 1 }
    }
    private func transition(_ t: Transition) {
        let previous = state
        perform {
            try ledger.transition(t)
            if !t.state.atDesk {
                if t.state == .away && !settings.pauseFocusOnAway {
                    try ledger.finishFocus(at: t.at, completed: false)
                } else { try ledger.pauseFocus(at: t.at) }
            } else if t.state == .idle {
                // Idle doesn't prove absence. An explicitly started focus may continue.
            }
        }
        state = t.state
        if state.atDesk && !previous.atDesk {
            reminders.eligibleAfter = t.at.addingTimeInterval(settings.returnGraceSeconds)
            reminders.lastSedentaryNotification = .distantPast
            reminders.sedentarySnoozeUntil = .distantPast
            if pendingReminder == "sedentary" { pendingReminder = nil }
        }
        if !state.atDesk || state == .focus {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["water", "sedentary"])
        }
        log("state_transition", "\(previous.rawValue) -> \(state.rawValue) reason=\(t.reason) confidence=\(t.confidence)", at: t.at)
        checkpoint(at: max(Date(), t.at))
        scheduleFocus()
        revision += 1; statusChanged?()
    }
    private func checkpoint(at: Date = Date(), clean: Bool = false) {
        perform { try repository.saveCheckpoint(Checkpoint(timestamp: at, bootID: bootID, cleanShutdown: clean)) }
        lastCheckpointUptime = ProcessInfo.processInfo.systemUptime
    }
    private func startHeartbeat() {
        let interval = RuntimeBudget.heartbeatInterval(sleeping: machine.sleeping,
                                                       displayAwake: machine.displayAwake, locked: machine.locked)
        guard interval != heartbeatInterval else { return }
        heartbeat?.invalidate(); heartbeat = nil; heartbeatInterval = interval
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        // Changing cadence must not postpone the next durable checkpoint beyond ~30 seconds.
        timer.fireDate = Date().addingTimeInterval(RuntimeBudget.heartbeatDelay(
            interval: interval, sinceCheckpoint: ProcessInfo.processInfo.systemUptime - lastCheckpointUptime))
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }
    private func tick() {
        now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        if machine.displayAwake && !machine.locked {
            monitor.activityTick()
            if uptime - lastConfigurationUptime >= 60 {
                monitor.refreshConfiguration(); lastConfigurationUptime = uptime
            }
        }
        if uptime - lastCheckpointUptime >= 29 { checkpoint() }
        let today = Calendar.current.startOfDay(for: now)
        if today != lastPrunedDay {
            perform { try repository.pruneEvents(before: now.addingTimeInterval(-30 * 86400)) }
            lastPrunedDay = today
        }
        for kind in reminders.due(state: state, awake: machine.displayAwake, locked: machine.locked,
                                  workStart: ledger.openWork?.start, settings: settings, now: now) {
            if kind == "water" && waterProgress.completed { continue }
            pendingReminder = kind
            notify(kind, title: kind == "water" ? "该喝水了" : "起来活动一下",
                   body: kind == "water" ? "今天已记录 \(waterProgress.totalML) mL。喝好后点击喝水卡片，按当前每次 \(settings.waterPlan.servingML) mL 记录。" : "已连续在工位 \(DurationText.short(ledger.openWork.map { now.timeIntervalSince($0.start) } ?? 0))。可以用触发角开始一次休息。")
        }
        revision += 1; statusChanged?()
        if let interval = heartbeatInterval {
            heartbeat?.fireDate = Date().addingTimeInterval(RuntimeBudget.heartbeatDelay(
                interval: interval, sinceCheckpoint: ProcessInfo.processInfo.systemUptime - lastCheckpointUptime))
        }
    }
    func summary(_ day: Date) -> DailySummary {
        let key = Calendar.current.startOfDay(for: day)
        if let result = summaryCache[key] { return result }
        let result = StatisticsService.summary(date: day, sessions: sessions, focuses: focuses, hydration: water, settings: settings, now: now)
        if summaryCache.count >= 64 { summaryCache.removeAll(keepingCapacity: true) }
        summaryCache[key] = result
        return result
    }
    func startFocus(_ minutes: Double) {
        guard state.atDesk, currentFocus == nil else { return }
        now = Date()
        perform { try ledger.startFocus(minutes: minutes, at: now) }
        machine.setFocus(true, at: now)
        log("focus_start", "planned_minutes=\(minutes)")
        scheduleFocus(); revision += 1
    }
    func pauseFocus() {
        perform { try ledger.pauseFocus(at: Date()) }
        machine.setFocus(false, at: Date()); scheduleFocus(); revision += 1
    }
    func resumeFocus() {
        guard state.atDesk else { return }
        perform { try ledger.resumeFocus(at: Date()) }
        machine.setFocus(true, at: Date()); scheduleFocus(); revision += 1
    }
    func endFocus() {
        perform { try ledger.finishFocus(at: Date(), completed: false) }
        machine.setFocus(false, at: Date()); scheduleFocus(); revision += 1
    }
    private func scheduleFocus() {
        focusTimer?.invalidate(); focusTimer = nil; focusDeadline = nil
        guard let focus = currentFocus, focus.pausedAt == nil, state.atDesk else { return }
        let remaining = max(0.1, focus.plannedDuration - focus.elapsed(at: Date()))
        focusDeadline = Date().addingTimeInterval(remaining)
        // One deadline timer, not a background per-second loop.
        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in self?.completeFocus() }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common); focusTimer = timer
    }
    private func completeFocus() {
        guard currentFocus?.pausedAt == nil else { return }
        let ended = focusDeadline ?? Date()
        perform { try ledger.finishFocus(at: ended, completed: true) }
        machine.setFocus(false, at: ended)
        log("focus_complete", "planned duration reached")
        pendingReminder = "focus"
        notify("focus", title: "专注完成", body: "做得够久了。准备好时，用触发角离开休息。")
        scheduleFocus(); revision += 1; statusChanged?()
    }
    func recordSliderDrink(_ preset: DrinkPreset, amountML: Int) {
        guard DrinkAmount.isSliderValue(amountML) else {
            errorMessage = "请选择 150、300、450 或 600 mL。"
            return
        }
        drink(source: "slider", preset: preset, amountML: amountML)
    }
    func drink(source: String = "menu", preset: DrinkPreset? = nil, amountML: Int? = nil) {
        if let amountML, !(10...2000).contains(amountML) {
            errorMessage = "请输入 10–2000 mL 的实际饮用量。"
            return
        }
        now = Date()
        let amount = amountML ?? preset.map { settings.waterPlan.servingML(for: $0) } ?? settings.waterPlan.servingML
        let alreadyAwarded = gardenTrophies.contains { Calendar.current.isDate($0.day, inSameDayAs: now) }
        let trophy: GardenTrophy?
        do {
            try ledger.drink(at: now, source: source, amountML: amount, drinkPresetID: preset?.rawValue)
            trophy = try ledger.awardGardenTrophy(for: now, plan: settings.waterPlan)
        }
        catch { errorMessage = "喝水记录保存失败：\(error.localizedDescription)"; return }
        if let preset, amountML != nil {
            var plan = settings.waterPlan
            plan.setServingML(amount, for: preset)
            plan.lastDrinkPresetID = preset.rawValue
            if plan != settings.waterPlan { settings.hydrationPlan = plan }
        }
        reminders.hydrationDue = now.addingTimeInterval(settings.hydrationMinutes * 60)
        reminders.lastHydrationNotification = .distantPast
        if pendingReminder == "water" { pendingReminder = nil }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["water"])
        if let trophy, !alreadyAwarded {
            hydrationFeedback = "获得今日奖杯 · \(trophy.recipe.title)"
        } else {
            hydrationFeedback = "已记录\(preset?.shortTitle ?? "水") +\(amount) mL"
        }
        log("hydration_done", "\(source) amountML=\(amount) preset=\(preset?.rawValue ?? "custom")"); revision += 1
    }
    func undoLastDrink() {
        now = Date()
        guard let event = waterProgress.lastEntry else { return }
        do { try ledger.undoDrink(id: event.id, at: now) }
        catch { errorMessage = "撤销失败：\(error.localizedDescription)"; return }
        let last = water.last { $0.voidedAt == nil }?.timestamp ?? now
        reminders.hydrationDue = max(now.addingTimeInterval(60), last.addingTimeInterval(settings.hydrationMinutes * 60))
        reminders.lastHydrationNotification = .distantPast
        hydrationFeedback = "已撤销最近一次"
        log("hydration_undo", "id=\(event.id)"); revision += 1
    }
    func snooze(_ kind: String) {
        if kind == "water" {
            reminders.hydrationDue = Date().addingTimeInterval(900)
            reminders.lastHydrationNotification = .distantPast
        } else {
            reminders.sedentarySnoozeUntil = Date().addingTimeInterval(900)
            reminders.lastSedentaryNotification = .distantPast
        }
        pendingReminder = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [kind])
    }
    func ignoreSedentary() {
        reminders.sedentarySnoozeUntil = .distantFuture
        pendingReminder = nil
    }
    func label(_ session: Session, _ label: String) {
        perform { try ledger.label(id: session.id, value: label) }; revision += 1
    }
    func calibrateFromLastCandidate() {
        guard let measured = machine.candidateAge, measured >= 0, measured <= 5 else { return }
        settings.calibratedWindow = min(3, max(0.4, measured + 0.35))
        log("calibration", "user-confirmed sample=\(measured)s; window=\(settings.effectiveWindow)s")
    }
    func updateLogin() {
        do {
            if settings.launchAtLogin {
                if SMAppService.mainApp.status == .notRegistered { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            switch SMAppService.mainApp.status {
            case .enabled: loginStatus = "已开启"
            case .requiresApproval: loginStatus = "等待系统设置批准"
            case .notRegistered: loginStatus = "已关闭"
            case .notFound: loginStatus = "请先将 App 安装到 Applications"
            @unknown default: loginStatus = "未知状态"
            }
        } catch { loginStatus = error.localizedDescription }
        log("launch_at_login", loginStatus)
    }
    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let done = UNNotificationAction(identifier: "done", title: "记录喝水（按当前每次量）")
        let snooze = UNNotificationAction(identifier: "snooze", title: "15 分钟后")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "water", actions: [done, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: "sedentary", actions: [
                UNNotificationAction(identifier: "break", title: "准备休息", options: .foreground),
                snooze, UNNotificationAction(identifier: "ignore", title: "忽略本工作区间")
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: "focus", actions: [], intentIdentifiers: [])
        ])
    }
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error { self?.errorMessage = error.localizedDescription }
                self?.refreshNotificationStatus()
            }
        }
    }
    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] value in
            DispatchQueue.main.async {
                self?.notificationStatus = value.authorizationStatus == .authorized ? "已允许通知" :
                    (value.authorizationStatus == .denied ? "系统通知已拒绝；菜单栏仍显示提醒" : "尚未授权")
            }
        }
    }
    private func notify(_ kind: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.categoryIdentifier = kind
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: kind, content: content, trigger: nil)) { [weak self] error in
            if let error {
                DispatchQueue.main.async { self?.log("notification_error", error.localizedDescription) }
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { completionHandler(); return }
            let kind = response.notification.request.content.categoryIdentifier
            switch response.actionIdentifier {
            case "done": self.drink(source: "notification")
            case "snooze": self.snooze(kind)
            case "ignore": self.ignoreSedentary()
            case "break": self.pendingReminder = "breakGuide"; self.openPage?("today")
            default: self.openPage?("today")
            }
            completionHandler()
        }
    }
    func export(_ kind: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "WorkRhythm-\(kind)-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).\(kind == "backup" ? "sqlite" : kind == "csv" ? "csv" : "json")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            if kind == "backup" { try repository.backup(to: url) }
            else if kind == "csv" {
                try StatisticsService.csv(sessions: sessions, focuses: focuses, hydration: water, now: Date()).write(to: url, atomically: true, encoding: .utf8)
            } else {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(repository.events(limit: 100_000).reversed().map { $0 }).write(to: url, options: .atomic)
            }
        }
    }
    func shutdown() {
        monitor.stop(); heartbeat?.invalidate(); focusTimer?.invalidate()
        perform { try ledger.closeAll(at: Date()) }
        checkpoint(clean: true); log("app_stop", "clean shutdown")
    }
}
