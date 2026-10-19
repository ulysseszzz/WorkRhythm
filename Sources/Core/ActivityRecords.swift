import Foundation

/// Display observations are kept distinct from inferred desk/away intervals.
public struct ScreenRecord: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let title: String
    public let symbol: String
    public let inactive: Bool
    public init?(_ event: SystemEvent) {
        guard event.type == "system_event" else { return nil }
        let action = String(event.metadata.prefix { $0 != "(" })
        let labels: (String, String, Bool)
        switch action {
        case "displaySleep": labels = ("屏幕熄灭", "display", true)
        case "displayWake": labels = ("屏幕亮起", "display", false)
        case "lock", "lockObserved": labels = ("锁定屏幕", "lock", true)
        case "unlock": labels = ("解锁屏幕", "lock.open", false)
        case "systemSleep": labels = ("系统睡眠", "moon", true)
        case "systemWake": labels = ("系统唤醒", "sun.max", false)
        case "lidClosed": labels = ("合上屏幕", "laptopcomputer", true)
        case "lidOpened": labels = ("打开屏幕", "laptopcomputer", false)
        case "screenSaverStarted": labels = ("屏幕保护启动", "sparkles.tv", true)
        case "screenSaverStopped": labels = ("屏幕保护结束", "sparkles.tv", false)
        default: return nil
        }
        id = event.id; timestamp = event.timestamp
        (title, symbol, inactive) = labels
    }
}

public struct DepartureRecord: Identifiable {
    public enum Kind: String {
        case active, lock, lid
        public var title: String {
            switch self {
            case .active: return "主动离座"
            case .lock: return "锁屏离座"
            case .lid: return "合盖离座"
            }
        }
        public var symbol: String {
            switch self {
            case .active: return "figure.walk"
            case .lock: return "lock"
            case .lid: return "laptopcomputer"
            }
        }
    }
    public let id: UUID
    public let start: Date
    public let end: Date?
    public let kind: Kind
    public let recovered: Bool
    public func duration(at now: Date) -> TimeInterval { max(0, (end ?? now).timeIntervalSince(start)) }
    public init?(_ session: Session) {
        switch session.kind {
        case .away:
            kind = session.trigger.contains("lock") ? .lock : .active
        case .locked:
            // A login screen shown after system wake/lid open is a return state,
            // not a new lock action and therefore not a new departure.
            guard session.trigger != "display_wake",
                  session.trigger != "lid_open_waiting_for_activity" else { return nil }
            kind = .lock
        case .moving:
            kind = .lid
        default:
            return nil
        }
        guard session.end == nil || session.end! > session.start else { return nil }
        id = session.id
        start = session.start
        end = session.end
        recovered = session.recovered
    }
}

public enum ActivityRecords {
    public static func drinks(_ events: [HydrationEvent], day: Date, now: Date,
                              calendar: Calendar = .current) -> [HydrationEvent] {
        guard let range = calendar.dateInterval(of: .day, for: day) else { return [] }
        return events.filter {
            $0.voidedAt == nil && $0.timestamp >= range.start && $0.timestamp < range.end && $0.timestamp <= now
        }.sorted { $0.timestamp > $1.timestamp }
    }
    public static func screens(_ events: [SystemEvent], day: Date, now: Date,
                               calendar: Calendar = .current) -> [ScreenRecord] {
        guard let range = calendar.dateInterval(of: .day, for: day) else { return [] }
        return events.filter {
            $0.timestamp >= range.start && $0.timestamp < range.end && $0.timestamp <= now
        }.compactMap(ScreenRecord.init).sorted { $0.timestamp > $1.timestamp }
    }
    public static func departures(_ sessions: [Session], day: Date, now: Date,
                                  calendar: Calendar = .current) -> [DepartureRecord] {
        guard let range = calendar.dateInterval(of: .day, for: day) else { return [] }
        return sessions.compactMap(DepartureRecord.init).filter {
            $0.start >= range.start && $0.start < range.end && $0.start <= now
        }.sorted { $0.start > $1.start }
    }
}
