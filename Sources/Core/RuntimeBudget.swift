import Foundation

/// Resource policy never changes Hot Corner detection windows or input-event delivery.
public enum RuntimeBudget {
    public static func heartbeatInterval(sleeping: Bool, displayAwake: Bool, locked: Bool) -> TimeInterval? {
        if sleeping { return nil }
        return displayAwake && !locked ? 15 : 30
    }
    public static func animationFPS(lowPower: Bool, thermallyConstrained: Bool) -> Double {
        if thermallyConstrained { return 0 }
        return lowPower ? 6 : 12
    }
    public static func heartbeatDelay(interval: TimeInterval, sinceCheckpoint: TimeInterval) -> TimeInterval {
        min(interval, max(0.1, 30 - sinceCheckpoint))
    }
}
