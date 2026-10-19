// Native Release performance harness. All behavioral fixtures use an isolated temporary database.
// Run via performance_probe.py; no permissions, user settings, or personal records are changed.
import AppKit
import SwiftUI
import Darwin

private struct Resources {
    var cpu: Double
    var footprint: UInt64
    var resident: UInt64
    var interrupts: UInt64
    var idleWakeups: UInt64
    static func read() -> Resources {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        var vm = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: vm) / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        var power = task_power_info_data_t()
        count = mach_msg_type_number_t(MemoryLayout.size(ofValue: power) / MemoryLayout<integer_t>.size)
        let powerStatus = withUnsafeMutablePointer(to: &power) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), $0, &count)
            }
        }
        precondition(vmStatus == KERN_SUCCESS && powerStatus == KERN_SUCCESS)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        return Resources(cpu: cpu, footprint: vm.phys_footprint, resident: vm.resident_size,
                         interrupts: power.task_interrupt_wakeups, idleWakeups: power.task_platform_idle_wakeups)
    }
}

@main
struct PerformanceProbe {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run() }
            catch { fputs("PERFORMANCE FAILED: \(error)\n", stderr) }
            NSApp.terminate(nil)
        }
        NSApp.run()
    }
    @MainActor static func run() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkRhythm-performance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try AppController(dataDirectory: directory)
        app.settings.launchAtLogin = false
        app.settings.hydrationEnabled = false; app.settings.sedentaryEnabled = false
        app.start()
        defer { app.shutdown() }
        app.drink(source: "performance_fixture")
        app.drink(source: "performance_fixture")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 520),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .floating; window.center()
        var rows: [[String: Any]] = []
        func measure(_ name: String, duration: Double = 12) async throws {
            try await Task.sleep(for: .seconds(1))
            let start = Resources.read()
            let clock = ProcessInfo.processInfo.systemUptime
            try await Task.sleep(for: .seconds(duration))
            let end = Resources.read()
            let seconds = ProcessInfo.processInfo.systemUptime - clock
            let row: [String: Any] = [
                "scenario": name, "seconds": seconds,
                "cpu_percent_one_core": 100 * (end.cpu - start.cpu) / seconds,
                "footprint_mib": Double(end.footprint) / 1_048_576,
                "resident_mib": Double(end.resident) / 1_048_576,
                "interrupt_wakeups_per_s": Double(end.interrupts - start.interrupts) / seconds,
                "platform_idle_wakeups_per_s": Double(end.idleWakeups - start.idleWakeups) / seconds,
                "visible": window.isVisible && window.occlusionState.contains(.visible)
            ]
            rows.append(row)
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: output)
            print(name, row)
        }
        try await measure("background", duration: 30)
        window.contentViewController = NSHostingController(rootView: MenuContent(app: app))
        window.orderFrontRegardless()
        try await measure("menu_garden_water")
        app.updateWaterPlan { $0.ambientMotion = false }
        try await measure("menu_motion_off")
        app.updateWaterPlan { $0.ambientMotion = true }
        window.orderOut(nil)
        // Retaining an ordered-out hosting view mimics the old 1.3 lifecycle.
        try await measure("hidden_retained")
        window.contentViewController = nil
        try await measure("hidden_released")
        print("PASS: performance measurements complete")
    }
}
