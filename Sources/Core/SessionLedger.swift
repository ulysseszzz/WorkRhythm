import Foundation

/// Work spans Active + Idle + Focus. Idle is separately visible, not counted twice.
public final class SessionLedger {
    public private(set) var sessions: [Session] { didSet { timelineRevision &+= 1 } }
    public private(set) var focuses: [FocusSession] { didSet { timelineRevision &+= 1 } }
    public private(set) var timelineRevision: UInt64 = 0
    public private(set) var hydration: [HydrationEvent]
    public private(set) var gardenTrophies: [GardenTrophy]
    public let repository: Repository
    public init(repository: Repository) throws {
        self.repository = repository
        sessions = try repository.sessions(); focuses = try repository.focuses()
        hydration = try repository.hydration(); gardenTrophies = try repository.gardenTrophies()
    }
    public var openWork: Session? { sessions.last { $0.kind == .work && $0.end == nil } }
    public var currentFocus: FocusSession? { focuses.last { $0.end == nil } }
    private func close(_ index: Int, at: Date) throws {
        sessions[index].end = max(at, sessions[index].start)
        try repository.save(sessions[index])
    }
    public func transition(_ t: Transition) throws {
        try repository.transaction {
            if t.rollbackRecentAway, let i = sessions.lastIndex(where: { $0.kind == .away && $0.end == nil }) {
                sessions[i].kind = .displaySleep
                sessions[i].confidence = 1
                sessions[i].trigger = "reclassified_competing_power_event"
                try repository.save(sessions[i])
            }
            let target: SessionKind
            switch t.state {
            case .active, .focus: target = .work
            case .idle: target = .idle
            case .away: target = .away
            case .moving: target = .moving
            case .systemSleep: target = .systemSleep
            case .displaySleep: target = .displaySleep
            case .locked: target = .locked
            case .unknown: target = .unknown
            }
            for i in sessions.indices where sessions[i].end == nil {
                let keepWork = sessions[i].kind == .work && t.state.atDesk
                let keepSame = sessions[i].kind == target
                if !keepWork && !keepSame { try close(i, at: t.at) }
            }
            if t.state.atDesk && openWork == nil {
                let session = Session(kind: .work, start: t.at, trigger: t.reason, confidence: t.confidence)
                sessions.append(session); try repository.save(session)
            }
            if target != .work && !sessions.contains(where: { $0.kind == target && $0.end == nil }) {
                let session = Session(kind: target, start: t.at, trigger: t.reason, confidence: t.confidence)
                sessions.append(session); try repository.save(session)
            }
        }
    }
    /// Never invent work, away or focus duration while the process wasn't observing.
    /// Close at the last durable heartbeat, mark censored, and add an explicit Unknown gap.
    public func recover(checkpoint: Checkpoint?, now: Date) throws {
        let boundary = min(checkpoint?.timestamp ?? now, now)
        try repository.transaction {
            for i in sessions.indices where sessions[i].end == nil {
                sessions[i].recovered = true
                sessions[i].note = "观测中断；实际结束时间未知，截断于最后持久化时间"
                try close(i, at: boundary)
            }
            for i in focuses.indices where focuses[i].end == nil {
                if let j = focuses[i].segments.indices.last, focuses[i].segments[j].end == nil {
                    focuses[i].segments[j].end = max(boundary, focuses[i].segments[j].start)
                }
                focuses[i].end = max(boundary, focuses[i].start)
                focuses[i].interrupted = true
                try repository.save(focuses[i])
            }
            if let checkpoint, now.timeIntervalSince(checkpoint.timestamp) > 2 {
                var gap = Session(kind: .unknown, start: checkpoint.timestamp, end: now, trigger: "app_not_observing", confidence: 0)
                gap.recovered = true; sessions.append(gap); try repository.save(gap)
            }
        }
    }
    public func closeAll(at: Date) throws {
        try repository.transaction {
            for i in sessions.indices where sessions[i].end == nil { try close(i, at: at) }
            try finishFocus(at: at, completed: false)
        }
    }
    public func label(id: UUID, value: String) throws {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].label = value; try repository.save(sessions[i])
    }
    public func startFocus(minutes: Double, at: Date) throws {
        guard currentFocus == nil else { return }
        let session = FocusSession(start: at, plannedDuration: max(60, min(240, minutes) * 60), segments: [FocusSegment(start: at)])
        focuses.append(session); try repository.save(session)
    }
    public func pauseFocus(at: Date) throws {
        guard let i = focuses.lastIndex(where: { $0.end == nil }), focuses[i].pausedAt == nil else { return }
        if let j = focuses[i].segments.indices.last {
            focuses[i].segments[j].end = max(at, focuses[i].segments[j].start)
        }
        focuses[i].pausedAt = at; focuses[i].interrupted = true
        try repository.save(focuses[i])
    }
    public func resumeFocus(at: Date) throws {
        guard let i = focuses.lastIndex(where: { $0.end == nil }), let pause = focuses[i].pausedAt else { return }
        focuses[i].pauseDuration += max(0, at.timeIntervalSince(pause))
        focuses[i].pausedAt = nil
        focuses[i].segments.append(FocusSegment(start: at))
        try repository.save(focuses[i])
    }
    public func finishFocus(at: Date, completed: Bool) throws {
        guard let i = focuses.lastIndex(where: { $0.end == nil }) else { return }
        if let j = focuses[i].segments.indices.last, focuses[i].segments[j].end == nil {
            focuses[i].segments[j].end = max(at, focuses[i].segments[j].start)
        }
        if let paused = focuses[i].pausedAt { focuses[i].pauseDuration += max(0, at.timeIntervalSince(paused)) }
        focuses[i].pausedAt = nil
        focuses[i].end = at; focuses[i].completed = completed
        focuses[i].interrupted = focuses[i].interrupted || !completed
        try repository.save(focuses[i])
    }
    public func drink(at: Date, source: String, amountML: Int? = nil, drinkPresetID: String? = nil) throws {
        let event = HydrationEvent(timestamp: at, source: source,
                                   amountML: amountML.map { min(2000, max(10, $0)) }, drinkPresetID: drinkPresetID)
        try repository.save(event); hydration.append(event)
    }
    public func undoDrink(id: UUID, at: Date) throws {
        guard let index = hydration.firstIndex(where: { $0.id == id && $0.voidedAt == nil }) else { return }
        var event = hydration[index]
        event.voidedAt = at
        try repository.save(event); hydration[index] = event
    }
    @discardableResult
    public func awardGardenTrophy(for date: Date, plan: HydrationPlan,
                                  calendar: Calendar = .current) throws -> GardenTrophy? {
        let progress = HydrationProgress(events: hydration, plan: plan, date: date, calendar: calendar)
        guard progress.completed, progress.garden.hasDrinks else { return nil }
        let day = calendar.startOfDay(for: date)
        if let index = gardenTrophies.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
            var trophy = gardenTrophies[index]
            trophy.recipeID = progress.garden.recipe.rawValue
            trophy.totalML = max(trophy.totalML, progress.totalML)
            try repository.save(trophy)
            gardenTrophies[index] = trophy
            return trophy
        }
        let trophy = GardenTrophy(day: day, awardedAt: progress.lastEntry?.timestamp ?? date,
                                  recipe: progress.garden.recipe, totalML: progress.totalML,
                                  targetML: plan.targetML)
        try repository.save(trophy)
        gardenTrophies.append(trophy)
        gardenTrophies.sort { $0.day < $1.day }
        return trophy
    }
    public func backfillGardenTrophies(plan: HydrationPlan, calendar: Calendar = .current) throws {
        let days = Set(hydration.compactMap { event -> Date? in
            guard event.voidedAt == nil, (event.amountML ?? 0) > 0 else { return nil }
            return calendar.startOfDay(for: event.timestamp)
        })
        for day in days.sorted() {
            _ = try awardGardenTrophy(for: day, plan: plan, calendar: calendar)
        }
    }
}
