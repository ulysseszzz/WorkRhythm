import Foundation
import CoreGraphics

public struct HotCornerTarget {
    public let corner: String
    public let screen: String
    public let screenBounds: CGRect
    public let point: CGPoint
    public let requiredModifiers: UInt
}

public enum HotCornerGeometry {
    /// Rebuilt only when screen geometry or settings change, not for every mouse event.
    public static func targets(screens: [(String, CGRect)], corners: [String],
                               requiredModifiers: [String: UInt]) -> [HotCornerTarget] {
        screens.flatMap { screen, frame in
            corners.filter { ["tl", "tr", "bl", "br"].contains($0) }.map { corner in
                HotCornerTarget(corner: corner, screen: screen,
                    screenBounds: frame.insetBy(dx: -1, dy: -1),
                    point: CGPoint(x: corner.hasSuffix("l") ? frame.minX : frame.maxX - 1,
                                   y: corner.hasPrefix("t") ? frame.maxY - 1 : frame.minY),
                    requiredModifiers: requiredModifiers[corner] ?? 0)
            }
        }
    }
    public static func match(point: CGPoint, targets: [HotCornerTarget], modifiers: UInt) -> (corner: String, screen: String)? {
        for target in targets where target.screenBounds.contains(point) {
            if abs(point.x - target.point.x) <= 3 && abs(point.y - target.point.y) <= 3 &&
                (modifiers & target.requiredModifiers) == target.requiredModifiers {
                return (target.corner, target.screen)
            }
        }
        return nil
    }
    /// Uses AppKit points throughout; no backing-pixel conversions across mixed-DPI screens.
    public static func match(point: CGPoint, screens: [(String, CGRect)], corners: [String],
                             modifiers: UInt, requiredModifiers: [String: UInt]) -> (corner: String, screen: String)? {
        match(point: point, targets: targets(screens: screens, corners: corners, requiredModifiers: requiredModifiers),
              modifiers: modifiers)
    }
}
