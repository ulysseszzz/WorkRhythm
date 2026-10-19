import AppKit
import SwiftUI

@main
enum WorkRhythmMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var controller: AppController?
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var window: NSWindow?
    private let navigation = NavigationModel()
    private var displayTimer: Timer?
    private var lockFile: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LaunchServices normally enforces a single instance; flock also covers direct CLI launches.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WorkRhythm")
        do {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            lockFile = Darwin.open(appSupport.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
            guard lockFile >= 0, flock(lockFile, LOCK_EX | LOCK_NB) == 0 else { NSApp.terminate(nil); return }
            let controller = try AppController()
            self.controller = controller
            controller.openPage = { [weak self] in self?.showPage($0) }
            controller.statusChanged = { [weak self] in self?.updateStatus() }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            self.item = item
            item.button?.target = self
            item.button?.action = #selector(togglePopover)
            item.button?.image = NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: "工位节奏")
            popover.behavior = .transient
            popover.delegate = self
            controller.start()
            updateStatus()
            controller.log("status_item_ready", "visible=\(item.isVisible) button=\(item.button != nil)")
            if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
                showPage("settings")
                UserDefaults.standard.set(true, forKey: "didShowWelcome")
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "工位节奏无法打开本地数据库"
            alert.informativeText = "\(error.localizedDescription)\n原有数据未删除。请检查可用磁盘空间或恢复数据库备份。"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
    @objc private func togglePopover() {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            controller?.now = Date()
            let screenHeight = button.window?.screen?.visibleFrame.height ?? 700
            let height = max(380, min(440, screenHeight - 40))
            if let controller {
                popover.contentViewController = NSHostingController(rootView: MenuContent(app: controller, availableHeight: height))
            }
            popover.contentSize = NSSize(width: 340, height: height)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    private func updateStatus() {
        guard let controller else { return }
        if let focus = controller.currentFocus, focus.pausedAt == nil {
            updateCountdown()
            if displayTimer == nil {
                let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updateCountdown() }
                timer.tolerance = 0.2; RunLoop.main.add(timer, forMode: .common); displayTimer = timer
            }
        } else {
            displayTimer?.invalidate(); displayTimer = nil
            item?.button?.title = controller.state == .away ? " 离座" :
                controller.state == .moving ? " 合盖" : controller.state == .locked ? " 锁屏" : ""
        }
        item?.button?.toolTip = "工位节奏 · \(controller.state.title) · 今日 \(controller.today.breaks) 次离座"
    }
    private func updateCountdown() {
        guard let focus = controller?.currentFocus, focus.pausedAt == nil else {
            displayTimer?.invalidate(); displayTimer = nil
            return
        }
        let remaining = max(0, Int(focus.plannedDuration - focus.elapsed(at: Date())))
        let title = String(format: " %02d:%02d", remaining / 60, remaining % 60)
        if item?.button?.title != title { item?.button?.title = title }
    }
    func popoverDidClose(_ notification: Notification) {
        if !popover.isShown { popover.contentViewController = nil }
    }
    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === window else { return }
        closed.contentViewController = nil
        window = nil
    }
    private func showPage(_ page: String) {
        guard let controller else { return }
        controller.now = Date()
        navigation.page = page
        popover.performClose(nil)
        if window == nil {
            let host = NSHostingController(rootView: MainView(app: controller, navigation: navigation))
            let window = NSWindow(contentViewController: host)
            window.title = "工位节奏 · WorkRhythm"
            window.setContentSize(NSSize(width: 980, height: 740))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("WorkRhythmMainWindow")
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        controller.log("window_open", "page=\(page) visible=\(window?.isVisible ?? false)")
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPage("today")
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown(); displayTimer?.invalidate()
        if lockFile >= 0 { flock(lockFile, LOCK_UN); Darwin.close(lockFile) }
    }
}
