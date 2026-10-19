import Foundation

public enum WorkstationState: String, Codable, CaseIterable {
    case active, focus, idle, away, moving, systemSleep, displaySleep, locked, unknown
    public var title: String {
        switch self {
        case .active: return "在工位"
        case .focus: return "专注"
        case .idle: return "静默 / 阅读"
        case .away: return "离座"
        case .moving: return "合盖离座"
        case .systemSleep: return "系统睡眠"
        case .displaySleep: return "显示器睡眠"
        case .locked: return "锁屏离座"
        case .unknown: return "未观测"
        }
    }
    public var atDesk: Bool { self == .active || self == .focus || self == .idle }
}

public enum SessionKind: String, Codable, CaseIterable {
    case work, away, moving, idle, systemSleep, displaySleep, locked, unknown
    public var title: String {
        switch self {
        case .work: return "在工位"
        case .away: return "离座"
        case .moving: return "合盖离座"
        case .idle: return "静默 / 阅读"
        case .systemSleep: return "系统睡眠"
        case .displaySleep: return "显示器睡眠"
        case .locked: return "锁屏离座"
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
public struct GardenTrophy: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var day: Date
    public var awardedAt: Date
    public var recipeID: String
    public var totalML: Int
    public var targetML: Int
    public var recipe: GardenRecipe { GardenRecipe(rawValue: recipeID) ?? .dew }
    public init(day: Date, awardedAt: Date, recipe: GardenRecipe, totalML: Int, targetML: Int) {
        self.day = day
        self.awardedAt = awardedAt
        recipeID = recipe.rawValue
        self.totalML = totalML
        self.targetML = targetML
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
        return ["微休息", "短休息", "长休息", "用餐 / 较长离座", "超长离座"][
            valid.firstIndex(where: { minutes < $0 }) ?? 4
        ]
    }
    public static let labels = ["如厕", "接水", "加餐", "用餐", "散步", "交谈", "会议", "其他"]
    public static func labelTitle(_ value: String) -> String {
        let legacy = [
            "Toilet": "如厕", "Water": "接水", "Snack": "加餐", "Meal": "用餐",
            "Walk": "散步", "Talk": "交谈", "Meeting": "会议", "Other": "其他"
        ]
        return legacy[value] ?? value
    }
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
        if value >= 3600 {
            let minutes = value % 3600 / 60
            return minutes == 0 ? "\(value / 3600)时" : "\(value / 3600)时 \(minutes)分"
        }
        if value >= 60 {
            let remainder = value % 60
            return remainder == 0 ? "\(value / 60)分" : "\(value / 60)分 \(remainder)秒"
        }
        return "\(value)秒"
    }
}
