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
}
