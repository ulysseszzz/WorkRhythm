import Foundation

/// Pure reducer: all observation ordering and classification lives here, never in a View.
public final class WorkstationStateMachine {
    public private(set) var state: WorkstationState = .unknown
    public private(set) var displayAwake = true
    public private(set) var sleeping = false
    public private(set) var lidClosed = false
    public private(set) var locked = false
    public private(set) var screenSaver = false
    public private(set) var lastDecision = "等待系统事件"
    public var window: Double = 1.5
    public let settleDelay: Double = 1.25
    /// macOS does not expose which UI initiated a lock. A lock immediately after
    /// aggregate user input is treated as manual; idle/security locks are not.
    public let manualLockInputWindow: Double = 5
    private struct Candidate {
        var uptime: Double
        var name: String
        var screen: String
        var point: String
    }
    private struct Pending { var at: Date; var reason: String; var confidence: Double }
    private var candidate: Candidate?
    private var pending: Pending?
    private var lastAway: Date?
    public var onTransition: ((Transition) -> Void)?
    public var onDiagnostic: ((Date, String) -> Void)?
    public var hasPending: Bool { pending != nil }
    public var candidateAge: Double?

    public init() {}
    public func setFocus(_ enabled: Bool, at: Date) {
        if state.atDesk { transition(enabled ? .focus : .active, at, enabled ? "focus_start" : "focus_stop") }
    }
    private func transition(_ next: WorkstationState, _ at: Date, _ reason: String,
                            _ confidence: Double = 1, rollback: Bool = false) {
        guard state != next else { return }
        state = next
        onTransition?(Transition(state: next, at: at, reason: reason, confidence: confidence, rollbackRecentAway: rollback))
    }
    private func diagnose(_ text: String, at: Date) {
        lastDecision = text; onDiagnostic?(at, text)
    }
    private func commitPending() {
        guard let value = pending else { return }
        pending = nil; lastAway = value.at
        transition(.away, value.at, value.reason, value.confidence)
        let classification = value.reason.hasPrefix("hot_corner") ? "manual_hot_corner" : "manual_lock_recent_input"
        diagnose("classification=\(classification) (inferred) \(value.reason)", at: value.at)
    }
    public func handle(_ input: Input, at: Date) {
        switch input {
        case let .cornerEntered(name, screen, x, y, uptime):
            guard displayAwake, !sleeping, !lidClosed, !locked, !screenSaver, state.atDesk else { return }
            candidate = Candidate(uptime: uptime, name: name, screen: screen, point: "\(x),\(y)")
            diagnose("hot_corner_candidate corner=\(name) screen=\(screen) mouse=\(x),\(y)", at: at)
        case .cornerExited:
            candidate = nil
        case let .displaySleep(uptime, idleSeconds, stillInCorner):
            guard displayAwake else { diagnose("duplicate display_sleep ignored", at: at); return }
            displayAwake = false
            if pending != nil || state == .away {
                candidate = nil
                diagnose("display_sleep follows established/pending Away; preserve original leave timestamp", at: at)
                return
            }
            let age = candidate.map { uptime - $0.uptime }
            candidateAge = age
            if let c = candidate, let age, age >= 0, age <= window,
               idleSeconds <= window + 0.5, stillInCorner, !sleeping, !lidClosed, !locked, !screenSaver {
                // Hold the original timestamp; competing power events can arrive after display sleep.
                pending = Pending(at: at, reason: "hot_corner:\(c.name) screen=\(c.screen) delta=\(String(format: "%.3f", age))s mouse=\(c.point)",
                                  confidence: 0.85)
                diagnose("display_sleep pending; wait \(settleDelay)s for competing power events", at: at)
            } else {
                diagnose("classification=unattributed_display_sleep cornerAge=\(age.map { String($0) } ?? "none") idle=\(idleSeconds) locked=\(locked) lid=\(lidClosed) sleeping=\(sleeping)", at: at)
                if !sleeping && !lidClosed && state != .away {
                    transition(locked ? .locked : .displaySleep, at, "unattributed_display_sleep")
                }
            }
            candidate = nil
        case .confirmSleep:
            if let value = pending, at.timeIntervalSince(value.at) >= settleDelay { commitPending() }
        case .displayWake:
            if displayAwake && (pending != nil || state == .away || state.atDesk || locked) {
                diagnose("duplicate display_wake ignored; unlock required if display never slept", at: at)
                return
            }
            displayAwake = true
            // A rapid real sleep/wake must still yield a single completed Away session.
            commitPending()
            if state == .away {
                transition(locked ? .locked : .active, at, "display_wake")
            } else if !sleeping && !lidClosed {
                transition(locked ? .locked : .active, at, "display_wake")
            }
            candidate = nil
        case .systemSleep:
            sleeping = true; candidate = nil
            let pendingAt = pending?.at
            pending = nil
            let competing = lastAway.map { at.timeIntervalSince($0) < 3 } ?? false
            if !lidClosed && (state != .away || competing) {
                transition(.systemSleep, pendingAt ?? at, "system_sleep", rollback: competing)
            }
            diagnose("system_sleep; pending hot corner cancelled; established Away preserved", at: at)
        case .systemWake:
            sleeping = false; candidate = nil
            // A dark/maintenance wake is not proof of a person's return.
            diagnose("system_wake; waiting for display or user activity", at: at)
        case .lidClosed:
            guard !lidClosed else { return }
            lidClosed = true; candidate = nil
            let pendingAt = pending?.at; pending = nil
            let competing = lastAway.map { at.timeIntervalSince($0) < 3 } ?? false
            transition(.moving, pendingAt ?? at, "lid_closed_possible_moving", 0.75, rollback: competing)
        case .lidOpened:
            guard lidClosed else { return }
            lidClosed = false
            // Ends Moving at the actual opening edge. Input/display wake starts Work.
            transition(locked ? .locked : .unknown, at, "lid_open_waiting_for_activity")
        case let .lockObserved(uptime, idleSeconds, stillInCorner):
            let age = candidate.map { uptime - $0.uptime }
            let canClassify = state.atDesk || (locked && state == .locked)
            if pending == nil, let c = candidate, let age,
               age >= 0, age <= window, idleSeconds <= window + 0.5, stillInCorner,
               displayAwake, !sleeping, !lidClosed, !screenSaver, canClassify {
                candidateAge = age
                pending = Pending(at: at, reason: "hot_corner_lock:\(c.name) screen=\(c.screen) delta=\(String(format: "%.3f", age))s mouse=\(c.point)",
                                  confidence: 0.85)
                diagnose("lock pending; correlated hot corner starts Away without requiring display sleep", at: at)
            } else if pending == nil, idleSeconds >= 0, idleSeconds <= manualLockInputWindow,
                      displayAwake, !sleeping, !lidClosed, !screenSaver, canClassify {
                pending = Pending(at: at,
                                  reason: "manual_lock_recent_input idle=\(String(format: "%.3f", idleSeconds))s",
                                  confidence: 0.75)
                diagnose("lock pending; recent aggregate input indicates keyboard/menu/manual lock", at: at)
            } else if locked {
                diagnose("duplicate/unattributed lock ignored idle=\(idleSeconds)", at: at)
                candidate = nil
                return
            }
            handle(.lock, at: at)
        case .lock:
            locked = true
            // Lock AFTER sleep is often macOS's password policy, not the sleep's cause.
            if pending == nil && state != .away && state != .moving && !sleeping {
                transition(.locked, at, "lock")
            }
            diagnose("lock observed; Away requires corner or recent-input evidence", at: at)
        case .unlock:
            // Lock-screen-only departures end on unlock even if no display sleep/wake occurred.
            commitPending()
            locked = false; candidate = nil
            if !sleeping && !lidClosed && displayAwake {
                transition(.active, at, "unlock")
            }
        case .screenSaverStarted:
            screenSaver = true; candidate = nil
            if let value = pending {
                if locked && (value.reason.hasPrefix("hot_corner_lock:") || value.reason.hasPrefix("manual_lock_recent_input")) {
                    diagnose("screen saver UI followed a manual lock; preserve Away candidate", at: at)
                } else {
                    pending = nil
                    transition(.displaySleep, value.at, "screen_saver_competing_with_sleep")
                }
            } else if state.atDesk { transition(.idle, at, "screen_saver") }
        case .screenSaverStopped:
            screenSaver = false
        case .userActivity:
            guard !sleeping, displayAwake, !locked, !screenSaver else { return }
            // Input while closed with an external screen proves clamshell desk use.
            if state != .focus { transition(.active, at, lidClosed ? "clamshell_external_activity" : "user_activity") }
        case .idle:
            if state == .active { transition(.idle, at, "input_idle_not_away") }
        }
    }
}
