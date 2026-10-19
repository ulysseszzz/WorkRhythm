import Foundation

public enum GardenRecipe: String, CaseIterable {
    case dew, sunshine, velvet, starlight, morning, peach, latte, rainbow
    case teaBell, milkLily, matcha, creamDahlia
    public var title: String {
        switch self {
        case .dew: return "露珠雏菊"
        case .sunshine: return "暖阳向日葵"
        case .velvet: return "奶霜郁金香"
        case .starlight: return "星夜波斯菊"
        case .morning: return "晨光金盏花"
        case .peach: return "桃雾郁金香"
        case .latte: return "拿铁玫瑰"
        case .rainbow: return "四季彩虹花"
        case .teaBell: return "青岚铃兰"
        case .milkLily: return "云朵百合"
        case .matcha: return "抹茶兰花"
        case .creamDahlia: return "奶油大丽花"
        }
    }
    public var ingredients: [DrinkPreset] {
        switch self {
        case .dew: return [.waterBottle]
        case .sunshine: return [.coffee]
        case .velvet: return [.milkTea]
        case .starlight: return [.cola]
        case .morning: return [.waterBottle, .coffee]
        case .peach: return [.waterBottle, .milkTea]
        case .latte: return [.coffee, .milkTea]
        case .rainbow: return [.waterBottle, .coffee, .milkTea, .cola]
        case .teaBell: return [.tea]
        case .milkLily: return [.milk]
        case .matcha: return [.tea, .milk]
        case .creamDahlia: return [.coffee, .milk]
        }
    }
    public var formula: String { ingredients.map(\.shortTitle).joined(separator: " + ") }
    /// Stylized artwork palette, not a hydration or nutrition conversion.
    public var rgb: (Double, Double, Double) {
        switch self {
        case .dew: return (0.18, 0.72, 0.85)
        case .sunshine: return (0.77, 0.46, 0.20)
        case .velvet: return (0.82, 0.64, 0.46)
        case .starlight: return (0.51, 0.33, 0.69)
        case .morning: return (0.96, 0.68, 0.22)
        case .peach: return (0.96, 0.55, 0.65)
        case .latte: return (0.74, 0.36, 0.48)
        case .rainbow: return (0.51, 0.49, 0.91)
        case .teaBell: return (0.28, 0.63, 0.46)
        case .milkLily: return (0.79, 0.77, 0.62)
        case .matcha: return (0.58, 0.72, 0.35)
        case .creamDahlia: return (0.84, 0.65, 0.40)
        }
    }
}

/// Recomputed from non-voided daily events; undo/restart never leave behind phantom rewards.
public struct DrinkGarden: Equatable {
    public let volumes: [DrinkPreset: Int]
    public let unlocked: [GardenRecipe]
    public let recipe: GardenRecipe
    public var hasDrinks: Bool { !volumes.isEmpty }
    public static let empty = DrinkGarden(events: [])
    public init(events: [HydrationEvent]) {
        var amounts: [DrinkPreset: Int] = [:]
        for event in events where event.voidedAt == nil {
            guard let ml = event.amountML, ml > 0 else { continue }
            // Historical plain clicks were water. Unknown future types are not guessed.
            let type = event.drinkPresetID == nil ? DrinkPreset.waterBottle : DrinkPreset(rawValue: event.drinkPresetID!)
            if let type { amounts[type, default: 0] += ml }
        }
        volumes = amounts
        unlocked = GardenRecipe.allCases.filter { recipe in
            recipe.ingredients.allSatisfy { amounts[$0, default: 0] > 0 }
        }
        // Prefer the richest matching combination, then its volume, then stable catalog order.
        recipe = unlocked.max { a, b in
            if a.ingredients.count != b.ingredients.count { return a.ingredients.count < b.ingredients.count }
            let av = a.ingredients.reduce(0) { $0 + amounts[$1, default: 0] }
            let bv = b.ingredients.reduce(0) { $0 + amounts[$1, default: 0] }
            if av != bv { return av < bv }
            return GardenRecipe.allCases.firstIndex(of: a)! > GardenRecipe.allCases.firstIndex(of: b)!
        } ?? .dew
    }
}

public enum DrinkAmount {
    public static let range = 10...2000
    public static func bounded(_ ml: Int) -> Int { min(range.upperBound, max(range.lowerBound, ml)) }
    public static func isValid(_ ml: Int) -> Bool { range.contains(ml) }
    public static func sliderPosition(for amount: Int, nodes: [Int]) -> Double {
        guard nodes.count > 1 else { return 0 }
        let value = bounded(amount)
        if value <= nodes[0] { return 0 }
        for index in 0..<(nodes.count - 1) where value <= nodes[index + 1] {
            let lower = nodes[index]
            let width = nodes[index + 1] - lower
            return Double(index) + Double(value - lower) / Double(width)
        }
        return Double(nodes.count - 1)
    }
    public static func amount(atSliderPosition position: Double, nodes: [Int]) -> Int {
        guard let first = nodes.first else { return range.lowerBound }
        guard nodes.count > 1 else { return bounded(first) }
        let clamped = min(Double(nodes.count - 1), max(0, position))
        let index = min(nodes.count - 2, Int(clamped.rounded(.down)))
        let fraction = clamped - Double(index)
        return bounded(Int((Double(nodes[index]) + Double(nodes[index + 1] - nodes[index]) * fraction).rounded()))
    }
    public static func snappedAmount(atSliderPosition position: Double, nodes: [Int],
                                     threshold: Double = 0.12) -> Int {
        guard nodes.count > 1 else { return amount(atSliderPosition: position, nodes: nodes) }
        let clamped = min(Double(nodes.count - 1), max(0, position))
        let nearest = clamped.rounded()
        if abs(clamped - nearest) <= max(0, threshold) {
            return bounded(nodes[Int(nearest)])
        }
        return amount(atSliderPosition: clamped, nodes: nodes)
    }
    public static func parse(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              isValid(value) else { return nil }
        return value
    }
}
