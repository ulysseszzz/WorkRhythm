import Foundation

public enum WorkstationState: String, Codable, CaseIterable {
    case active, focus, idle, away, moving, systemSleep, displaySleep, locked, unknown
    public var title: String {
        switch self {
        case .active: return "在工位"
        case .focus: return "专注"
        case .idle: return "静默 / 阅读"
        case .away: return "主动离开"
        case .moving: return "合盖 / 可能移动"
        case .systemSleep: return "系统睡眠"
        case .displaySleep: return "显示器睡眠"
        case .locked: return "锁屏"
        case .unknown: return "未观测"
        }
    }
    public var atDesk: Bool { self == .active || self == .focus || self == .idle }
}

public enum SessionKind: String, Codable, CaseIterable {
    case work, away, moving, idle, systemSleep, displaySleep, locked, unknown
    public var title: String {
        switch self {
        case .work: return "Work · 在工位"
        case .away: return "Away · 主动离开"
        case .moving: return "Moving · 合盖"
        case .idle: return "Idle · 静默"
        case .systemSleep: return "System Sleep"
        case .displaySleep: return "Display Sleep"
        case .locked: return "Locked · 锁屏"
        case .unknown: return "未观测区间"
        }
    }
}

public struct Session: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var kind: SessionKind
    public var start: Date
    public var end: Date?
    public var trigger: String
    public var confidence: Double
    public var label: String = ""
    public var note: String = ""
    public var interruptions = 0
    public var recovered = false
    public init(kind: SessionKind, start: Date, end: Date? = nil,
                trigger: String = "", confidence: Double = 1) {
        self.kind = kind; self.start = start; self.end = end
        self.trigger = trigger; self.confidence = confidence
    }
    public func duration(at now: Date) -> TimeInterval { max(0, (end ?? now).timeIntervalSince(start)) }
}
public typealias WorkSession = Session
public typealias AwaySession = Session
public typealias MoveSession = Session

public struct FocusSegment: Codable, Equatable {
    public var start: Date
    public var end: Date?
}
public struct FocusSession: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var start: Date
    public var end: Date?
    public var plannedDuration: TimeInterval
    public var segments: [FocusSegment] = []
    public var completed = false
    public var interrupted = false
    public var pausedAt: Date?
    public var pauseDuration: TimeInterval = 0
    public var actualDuration: TimeInterval { segments.reduce(0) { $0 + max(0, ($1.end ?? $1.start).timeIntervalSince($1.start)) } }
    public func elapsed(at now: Date) -> TimeInterval {
        segments.reduce(0) { $0 + max(0, ($1.end ?? now).timeIntervalSince($1.start)) }
    }
}
public struct HydrationEvent: Codable, Identifiable {
    public var id = UUID()
    public var timestamp: Date
    public var source: String
    /// nil on pre-1.2 records: never invent a volume for historical check-ins.
    public var amountML: Int?
    public var voidedAt: Date?
    public var drinkPresetID: String?
    public var drinkTitle: String { DrinkPreset(rawValue: drinkPresetID ?? "")?.title ?? "饮水" }
    public init(timestamp: Date, source: String, amountML: Int? = nil, drinkPresetID: String? = nil) {
        self.timestamp = timestamp; self.source = source; self.amountML = amountML
        self.drinkPresetID = drinkPresetID
    }
}
public struct SystemEvent: Codable, Identifiable {
    public var id = UUID()
    public var timestamp: Date
    public var type: String
    public var metadata: String
    public init(timestamp: Date, type: String, metadata: String) {
        self.timestamp = timestamp; self.type = type; self.metadata = metadata
    }
}
public struct Checkpoint: Codable {
    public var timestamp: Date
    public var bootID: String
    public var cleanShutdown: Bool
}

public struct AppSettings: Codable, Equatable {
    public var corner = "auto"
    public var detectionWindow: Double = 0
    public var calibratedWindow: Double?
    public var idleMinutes: Double = 5
    public var hydrationEnabled = true
    public var hydrationMinutes: Double = 90
    public var hydrationPlan: HydrationPlan?
    public var sedentaryEnabled = true
    public var sedentaryMinutes: Double = 60
    public var returnGraceSeconds: Double = 120
    public var pauseFocusOnAway = true
    public var customFocusMinutes: Double = 25
    public var breakThresholds: [Double] = [2, 10, 30, 90]
    public var debugEnabled = false
    public var launchAtLogin = true
    public init() {}
    public var waterPlan: HydrationPlan { hydrationPlan ?? HydrationPlan() }
    public var effectiveWindow: Double { detectionWindow > 0 ? min(5, max(0.2, detectionWindow)) : (calibratedWindow ?? 1.5) }
    public func classification(seconds: Double) -> String {
        let valid = breakThresholds.count == 4 ? breakThresholds.sorted() : [2, 10, 30, 90]
        let minutes = seconds / 60
        return ["Micro Break", "Short Break", "Long Break", "Meal / Long Away Candidate", "Extended Away"][
            valid.firstIndex(where: { minutes < $0 }) ?? 4
        ]
    }
    public static let labels = ["Toilet", "Water", "Snack", "Meal", "Walk", "Talk", "Meeting", "Other"]
}

public enum Input {
    case cornerEntered(name: String, screen: String, x: Double, y: Double, uptime: Double)
    case cornerExited
    case displaySleep(uptime: Double, idleSeconds: Double, stillInCorner: Bool)
    case displayWake
    case systemSleep
    case systemWake
    case lidClosed
    case lidOpened
    case lock
    case lockObserved(uptime: Double, idleSeconds: Double, stillInCorner: Bool)
    case unlock
    case screenSaverStarted
    case screenSaverStopped
    case userActivity
    case idle
    case confirmSleep
}
public struct Transition {
    public var state: WorkstationState
    public var at: Date
    public var reason: String
    public var confidence: Double
    public var rollbackRecentAway = false
}

public enum DurationText {
    public static func short(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        if value >= 3600 { return "\(value / 3600)h \(value % 3600 / 60)m" }
        if value >= 60 { return "\(value / 60)m \(value % 60)s" }
        return "\(value)s"
    }
}
