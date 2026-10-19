import Foundation

public struct DrinkServingOption: Hashable {
    public let amountML: Int
    public let container: String
    public init(_ amountML: Int, _ container: String) {
        self.amountML = amountML
        self.container = container
    }
}

public enum DrinkPreset: String, Codable, CaseIterable {
    case waterBottle, coffee, milkTea, cola, tea, milk
    public static let displayOrder: [DrinkPreset] = [.tea, .waterBottle, .milkTea, .milk, .cola, .coffee]
    public var title: String {
        switch self {
        case .waterBottle: return "一瓶水"
        case .coffee: return "一杯咖啡"
        case .milkTea: return "一杯奶茶"
        case .cola: return "一罐可乐"
        case .tea: return "一杯茶"
        case .milk: return "一杯牛奶"
        }
    }
    public var symbol: String {
        switch self {
        case .waterBottle: return "waterbottle"
        case .coffee: return "cup.and.saucer"
        case .milkTea: return "cup.and.saucer.fill"
        case .cola: return "cylinder"
        case .tea: return "leaf"
        case .milk: return "mug"
        }
    }
    public var shortTitle: String {
        switch self {
        case .waterBottle: return "水"
        case .coffee: return "咖啡"
        case .milkTea: return "奶茶"
        case .cola: return "可乐"
        case .tea: return "茶"
        case .milk: return "牛奶"
        }
    }
    /// Editable starting values, not universal package sizes.
    public var defaultML: Int {
        switch self {
        case .waterBottle: return 500
        case .coffee: return 240
        case .milkTea: return 350
        case .cola: return 330
        case .tea: return 500
        case .milk: return 250
        }
    }
    public var servingOptions: [DrinkServingOption] {
        switch self {
        case .waterBottle:
            return [.init(350, "瓶装"), .init(500, "瓶装"), .init(550, "瓶装"), .init(1500, "大瓶")]
        case .coffee:
            return [.init(240, "听装"), .init(268, "瓶装"), .init(270, "瓶装"), .init(450, "瓶装")]
        case .milkTea:
            return [.init(250, "瓶装"), .init(300, "杯装"), .init(350, "瓶装"), .init(400, "瓶装")]
        case .cola:
            return [.init(200, "迷你听"), .init(330, "听装"), .init(500, "瓶装"), .init(888, "大瓶")]
        case .tea:
            return [.init(250, "盒装"), .init(310, "听装"), .init(500, "瓶装"), .init(1000, "大瓶")]
        case .milk:
            return [.init(200, "盒装"), .init(250, "盒装"), .init(500, "盒装"), .init(1000, "家庭装")]
        }
    }
}

public enum HydrationTheme: String, Codable, CaseIterable {
    case bottle, flowers
    public var title: String {
        switch self {
        case .bottle: return "水瓶"
        case .flowers: return "花园"
        }
    }
    public var symbol: String {
        switch self {
        case .bottle: return "waterbottle"
        case .flowers: return "camera.macro"
        }
    }
}

public struct HydrationPlan: Codable, Equatable {
    public var dailyTargetML = 1600
    public var plannedDrinks = 8
    /// nil follows the calculated suggestion; existing events retain their recorded amount.
    public var customServingML: Int?
    /// Optional raw value keeps older plans readable, and unknown future themes fall back safely.
    public var themeID: String?
    public var ambientMotion: Bool?
    public var presetVolumesML: [String: Int]?
    public var servingOptionsVersion: Int?
    public var theme: HydrationTheme {
        if themeID == "ivy" { return .flowers }
        return HydrationTheme(rawValue: themeID ?? "") ?? .bottle
    }
    public var lastDrinkPresetID: String?
    public var selectedDrink: DrinkPreset { DrinkPreset(rawValue: lastDrinkPresetID ?? "") ?? .waterBottle }
    public var motionEnabled: Bool { ambientMotion ?? true }
    public init() {}
    public var targetML: Int { min(6000, max(200, dailyTargetML)) }
    public var targetCount: Int { min(30, max(1, plannedDrinks)) }
    public var suggestedServingML: Int {
        min(2000, max(10, Int((Double(targetML) / Double(targetCount) / 10).rounded()) * 10))
    }
    public var servingML: Int { min(2000, max(10, customServingML ?? suggestedServingML)) }
    public func servingML(for preset: DrinkPreset) -> Int {
        min(2000, max(10, presetVolumesML?[preset.rawValue] ?? preset.defaultML))
    }
    public mutating func setServingML(_ amount: Int, for preset: DrinkPreset) {
        var values = presetVolumesML ?? [:]
        values[preset.rawValue] = min(2000, max(10, amount))
        presetVolumesML = values
    }
    @discardableResult
    public mutating func migrateLegacyServingOptions() -> Bool {
        guard (servingOptionsVersion ?? 0) < 1 else { return false }
        let legacySteps = Set([150, 300, 450, 600])
        if var values = presetVolumesML {
            for preset in DrinkPreset.allCases {
                guard let value = values[preset.rawValue], legacySteps.contains(value),
                      let nearest = preset.servingOptions.min(by: {
                          let left = abs($0.amountML - value)
                          let right = abs($1.amountML - value)
                          return left == right ? $0.amountML < $1.amountML : left < right
                      }) else { continue }
                values[preset.rawValue] = nearest.amountML
            }
            presetVolumesML = values
        }
        servingOptionsVersion = 1
        return true
    }
}

public struct HydrationProgress {
    public let totalML: Int
    public let count: Int
    public let legacyCount: Int
    public let plan: HydrationPlan
    public let lastEntry: HydrationEvent?
    public let garden: DrinkGarden
    public var remainingML: Int { max(0, plan.targetML - totalML) }
    public var fraction: Double { min(1, max(0, Double(totalML) / Double(plan.targetML))) }
    public var completed: Bool { totalML >= plan.targetML }
    public var remainingDrinks: Int { Int(ceil(Double(remainingML) / Double(plan.servingML))) }
    public init(events: [HydrationEvent], plan: HydrationPlan, date: Date, calendar: Calendar = .current) {
        let day = calendar.dateInterval(of: .day, for: date)!
        let entries = events.filter {
            $0.voidedAt == nil && $0.timestamp >= day.start && $0.timestamp < day.end
        }
        totalML = entries.reduce(0) { $0 + max(0, $1.amountML ?? 0) }
        count = entries.count
        legacyCount = entries.filter { $0.amountML == nil }.count
        lastEntry = entries.max { $0.timestamp < $1.timestamp }
        garden = DrinkGarden(events: entries)
        self.plan = plan
    }
}
