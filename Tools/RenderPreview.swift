// Optional native UI smoke test. Compile with Sources except WorkRhythmApp.swift
// into a temporary .app bundle. Uses a fresh isolated database, never personal records.
import AppKit
import SwiftUI

@main
struct RenderPreview {
    @MainActor static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do { try await run() }
            catch {
                try? Data("FAIL: \(error)".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
            }
        }
        NSApp.run()
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        // Materialize SwiftUI's otherwise lazy accessibility tree for local UI checks.
        NSApp.accessibilitySetValue(true, forAttribute: .init(rawValue: "AXEnhancedUserInterface"))
        NSApp.accessibilitySetValue(true, forAttribute: .init(rawValue: "AXManualAccessibility"))
        NSApp.activate(ignoringOtherApps: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkRhythm-preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try AppController(dataDirectory: directory)
        app.state = .active
        app.settings.corner = "tl"
        try app.ledger.transition(Transition(state: .away, at: app.now.addingTimeInterval(-480), reason: "preview_fixture", confidence: 0.85))
        try app.ledger.transition(Transition(state: .active, at: app.now.addingTimeInterval(-60), reason: "preview_fixture", confidence: 1))
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func capture<V: View>(_ content: V, size: NSSize, name: String, dark: Bool = false) async throws {
            let host = NSHostingView(rootView: content.environment(\.colorScheme, dark ? .dark : .light))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.setContentSize(size)
            window.orderFront(nil)
            try await Task.sleep(for: .seconds(0.2))
            host.layoutSubtreeIfNeeded()
            if name.hasPrefix("menu-") {
                func containsScroll(_ view: NSView) -> Bool {
                    view is NSScrollView || view.subviews.contains { containsScroll($0) }
                }
                precondition(!containsScroll(host), "Main menu must not require scrolling")
                precondition(host.fittingSize.height <= size.height + 1, "Menu content must fit its window")
            }
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "Preview", code: 1) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Preview", code: 2) }
            try png.write(to: output.appendingPathComponent(name + ".png"))
            window.orderOut(nil)
        }
        func render(_ name: String, height: CGFloat = 440) async throws {
            try await capture(MenuContent(app: app, availableHeight: height).background(Color(nsColor: .windowBackgroundColor)),
                        size: NSSize(width: 340, height: height), name: name)
        }
        try await render("menu-garden-empty")
        precondition(app.summary(app.now).waterML == 0)
        for _ in 0..<3 { app.drink(source: "preview_fixture") }
        precondition(app.waterProgress.totalML == 600)
        precondition(app.summary(app.now).waterML == 600, "Summary cache must invalidate on drink")
        try await render("menu-garden-partial")
        app.undoLastDrink()
        precondition(app.waterProgress.totalML == 400)
        precondition(app.summary(app.now).waterML == 400, "Summary cache must invalidate on undo")
        try await render("menu-undo")
        for _ in 0..<6 { app.drink(source: "preview_fixture") }
        precondition(app.waterProgress.completed)
        try await render("menu-garden-complete")
        try await render("menu-short-screen", height: 380)
        try await capture(DashboardPage(app: app).frame(width: 770, height: 700).background(Color(nsColor: .windowBackgroundColor)),
                    size: NSSize(width: 770, height: 700), name: "dashboard")
        let gallery = HStack(spacing: 18) {
            ForEach([0.0, 0.5, 1.0], id: \.self) { fraction in
                VStack(spacing: 10) {
                    ZStack {
                        HydrationWaterBackdrop(fraction: fraction, motionEnabled: false, recipe: .teaBell)
                        HydrationArtwork(theme: .flowers, fraction: fraction, phase: 0.5, recipe: .teaBell)
                            .padding(12)
                    }
                    .frame(width: 130, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.teal.opacity(0.15)))
                    Text("\(Int(fraction * 100))%").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(24).background(Color(nsColor: .windowBackgroundColor))
        try await capture(gallery, size: NSSize(width: 490, height: 260), name: "water-levels")
        try await capture(MenuContent(app: app).background(Color(nsColor: .windowBackgroundColor)),
                    size: NSSize(width: 340, height: 440), name: "menu-dark", dark: true)
        // Verify native window and scroll visibility with the same probe used by animation.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 136))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 500))
        scroll.documentView = document
        let probe = SceneVisibilityProbe.VisibilityView(frame: NSRect(x: 0, y: 0, width: 100, height: 136))
        var visible = false
        probe.onChange = { visible = $0 }
        document.addSubview(probe)
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scroll
        scroll.contentView.scroll(to: .zero)
        window.level = .floating
        window.center(); window.orderFrontRegardless()
        try await Task.sleep(for: .seconds(0.5))
        try Data("visible=\(visible) window=\(window.isVisible) occlusion=\(window.occlusionState.rawValue) rect=\(probe.visibleRect) scroll=\(scroll.contentView.bounds)".utf8)
            .write(to: output.appendingPathComponent("visibility.txt"))
        let canCheckLiveAnimation = visible
        if canCheckLiveAnimation {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        try await Task.sleep(for: .seconds(0.2))
        try Data("visible=\(visible) rect=\(probe.visibleRect) clip=\(scroll.contentView.bounds) observedClip=\(probe.enclosingScrollView != nil)".utf8)
            .write(to: output.appendingPathComponent("offscreen.txt"))
        precondition(!visible, "Offscreen scene must pause")
        scroll.contentView.scroll(to: .zero)
        try await Task.sleep(for: .seconds(0.2))
        precondition(visible, "Scene must resume on scroll back")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        try await Task.sleep(for: .seconds(0.1))
        precondition(!visible, "Scene must pause on display sleep")
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await Task.sleep(for: .seconds(0.1))
        precondition(visible, "Scene must resume on wake")
        window.orderOut(nil)
        try await Task.sleep(for: .seconds(0.2))
        precondition(!visible, "Hidden scene must pause")
        probe.stop()
        // Regression: SwiftUI can recreate the bridge while keeping an existing true @State.
        var retainedVisible = true
        let replacement = SceneVisibilityProbe.VisibilityView(frame: probe.frame)
        replacement.onChange = { retainedVisible = $0 }
        document.addSubview(replacement)
        try await Task.sleep(for: .seconds(0.1))
        precondition(!retainedVisible, "A recreated hidden bridge must reset retained visible state")
        replacement.stop()

        func animationFrames(theme: HydrationTheme, enabled: Bool) async throws -> Bool {
            let scene = HydrationScene(theme: theme, fraction: 0.65, motionEnabled: enabled)
            let host = NSHostingView(rootView: scene)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 136),
                             styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = host; w.level = .floating; w.center(); w.orderFrontRegardless()
            func artwork(in view: NSView) -> HydrationLayerView.ArtworkView? {
                if let found = view as? HydrationLayerView.ArtworkView { return found }
                return view.subviews.compactMap { artwork(in: $0) }.first
            }
            func layers(_ layer: CALayer) -> [CALayer] {
                [layer] + (layer.sublayers ?? []).flatMap(layers)
            }
            func frame() throws -> Data {
                host.layoutSubtreeIfNeeded()
                let native = artwork(in: host)!
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 272,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                context.scaleBy(x: 2, y: 2)
                // cacheDisplay renders model layers. Presentation layers contain the actual
                // compositor transforms; comparing model snapshots would miss live motion.
                (native.layer!.presentation() ?? native.layer!).render(in: context)
                return bitmap.representation(using: .png, properties: [:])!
            }
            try await Task.sleep(for: .seconds(0.3))
            let first = try frame()
            try await Task.sleep(for: .seconds(0.7))
            let second = try frame()
            let prefix = "\(theme.rawValue)-\(enabled ? "motion" : "disabled")"
            try first.write(to: output.appendingPathComponent("\(prefix)-a.png"))
            try second.write(to: output.appendingPathComponent("\(prefix)-b.png"))
            w.orderOut(nil)
            try await Task.sleep(for: .seconds(0.2))
            precondition(layers(artwork(in: host)!.layer!).allSatisfy { ($0.animationKeys() ?? []).isEmpty },
                         "Retained hidden scene must remove compositor animations")
            return first != second
        }
        func waterFrames(enabled: Bool) async throws -> Bool {
            let scene = HydrationWaterBackdrop(fraction: 0.65, motionEnabled: enabled, recipe: .teaBell)
            let host = NSHostingView(rootView: scene)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 220),
                             styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = host; w.level = .floating; w.center(); w.orderFrontRegardless()
            func water(in view: NSView) -> HydrationWaterLayerView.WaterView? {
                if let found = view as? HydrationWaterLayerView.WaterView { return found }
                return view.subviews.compactMap { water(in: $0) }.first
            }
            func layers(_ layer: CALayer) -> [CALayer] {
                [layer] + (layer.sublayers ?? []).flatMap(layers)
            }
            func frame() throws -> Data {
                host.layoutSubtreeIfNeeded()
                let native = water(in: host)!
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 440,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
                context.scaleBy(x: 2, y: 2)
                (native.layer!.presentation() ?? native.layer!).render(in: context)
                return bitmap.representation(using: .png, properties: [:])!
            }
            try await Task.sleep(for: .seconds(0.3))
            let first = try frame()
            try await Task.sleep(for: .seconds(0.7))
            let second = try frame()
            let prefix = "water-\(enabled ? "motion" : "disabled")"
            try first.write(to: output.appendingPathComponent("\(prefix)-a.png"))
            try second.write(to: output.appendingPathComponent("\(prefix)-b.png"))
            w.orderOut(nil)
            try await Task.sleep(for: .seconds(0.2))
            precondition(layers(water(in: host)!.layer!).allSatisfy { ($0.animationKeys() ?? []).isEmpty },
                         "Hidden water backdrop must remove compositor animations")
            return first != second
        }
        let gardenMoving = try await animationFrames(theme: .flowers, enabled: true)
        let gardenDisabled = try await animationFrames(theme: .flowers, enabled: false)
        let waterMoving = try await waterFrames(enabled: true)
        let waterDisabled = try await waterFrames(enabled: false)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        precondition(gardenMoving != reduceMotion && waterMoving != reduceMotion,
                     "Garden and water must animate unless system Reduce Motion is enabled")
        precondition(!gardenDisabled && !waterDisabled, "Disabled motion must remain still")
        } else {
            window.orderOut(nil)
            probe.stop()
            try Data("SKIPPED: desktop did not expose the floating window (occlusion=\(window.occlusionState.rawValue)); live animation/visibility not verified in this run. Static layout and data checks continue.".utf8)
                .write(to: output.appendingPathComponent("animation-limitation.txt"))
        }
        // A separate fixture day exercises dense hourly distribution without personal data.
        let calendar = Calendar.current
        let fixtureDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        func at(_ minutes: Double) -> Date { fixtureDay.addingTimeInterval(minutes * 60) }
        let timelineDirectory = directory.appendingPathComponent("timeline")
        let repo = try Repository(url: timelineDirectory.appendingPathComponent("workrhythm.sqlite"))
        let blocks: [(SessionKind, Double, Double)] = [
            (.systemSleep, 0, 475), (.work, 475, 555), (.away, 555, 565),
            (.work, 565, 640), (.away, 640, 650), (.work, 650, 720),
            (.away, 720, 785), (.work, 785, 895), (.away, 895, 900),
            (.work, 900, 915), (.away, 915, 925), (.work, 925, 960),
            (.moving, 960, 982), (.work, 982, 1080), (.locked, 1080, 1440),
            (.idle, 515, 533), (.idle, 855, 880)
        ]
        for (kind, a, b) in blocks {
            try repo.save(Session(kind: kind, start: at(a), end: at(b), trigger: "preview_fixture"))
        }
        try repo.save(FocusSession(start: at(570), end: at(620), plannedDuration: 3000,
            segments: [FocusSegment(start: at(570), end: at(595)), FocusSegment(start: at(600), end: at(620))], completed: true))
        let timelineApp = try AppController(dataDirectory: timelineDirectory)
        let cached = timelineApp.timeline(fixtureDay)
        precondition(cached === timelineApp.timeline(fixtureDay))
        timelineApp.now = timelineApp.now.addingTimeInterval(15)
        precondition(cached === timelineApp.timeline(fixtureDay), "Historical day must survive clock-only refresh")
        let leave = cached.sessions.first { $0.kind == .away }!
        timelineApp.label(leave, "Walk")
        let updated = timelineApp.timeline(fixtureDay)
        precondition(updated !== cached, "Editing a label must invalidate timeline snapshots")
        precondition(updated.sessions.first { $0.id == leave.id }!.label == "Walk")
        _ = timelineApp.events
        timelineApp.log("cache_fixture", "event cache invalidation")
        precondition(timelineApp.events.first?.type == "cache_fixture")
        timelineApp.refreshEvents()
        precondition(timelineApp.events.first?.type == "cache_fixture")
        try await capture(TimelinePage(app: timelineApp, day: fixtureDay)
                            .background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 750, height: 710), name: "timeline-overview")
        try await capture(TimelinePage(app: timelineApp, day: fixtureDay, selectedHour: at(900))
                            .background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 750, height: 1020), name: "timeline-selected-hour")
        try await capture(TimelinePage(app: timelineApp, day: fixtureDay, showDetails: true)
                            .background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 640, height: 900), name: "timeline-details-narrow")
        try await capture(TimelinePage(app: timelineApp, day: fixtureDay)
                            .background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 750, height: 710), name: "timeline-dark", dark: true)
        try await capture(TimelinePage(app: timelineApp)
                            .background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 640, height: 710), name: "timeline-empty-today")
        let drinks = try AppController(dataDirectory: directory.appendingPathComponent("presets"))
        drinks.state = .active
        for preset in [DrinkPreset.waterBottle, .coffee, .milkTea, .cola] { drinks.drink(source: "preview_fixture", preset: preset) }
        precondition(drinks.waterProgress.totalML == 1420)
        precondition(drinks.summary(drinks.now).waterML == 1420)
        precondition(drinks.waterProgress.lastEntry?.drinkPresetID == "cola")
        func drinkCard() -> some View {
            HydrationBottleCard(progress: drinks.waterProgress, feedback: drinks.hydrationFeedback,
                onRecord: { drinks.recordPresetDrink($0, amountML: $1) },
                onUndo: { drinks.undoLastDrink() }, onSettings: {})
                .padding(14).background(Color(nsColor: .windowBackgroundColor))
        }
        try await capture(drinkCard(), size: NSSize(width: 300, height: 420), name: "drink-presets")
        try await capture(drinkCard(), size: NSSize(width: 300, height: 420), name: "drink-presets-dark", dark: true)
        drinks.undoLastDrink()
        precondition(drinks.waterProgress.totalML == 1090)
        precondition(drinks.summary(drinks.now).waterML == 1090)
        drinks.updateWaterPlan {
            $0.dailyTargetML = 1400
            $0.setServingML(350, for: .coffee)
        }
        drinks.drink(source: "preview_fixture", preset: .coffee)
        precondition(drinks.waterProgress.totalML == 1440 && drinks.waterProgress.completed)
        precondition(drinks.waterProgress.lastEntry?.amountML == 350)
        precondition(drinks.waterProgress.lastEntry?.drinkTitle == "一杯咖啡")
        precondition(drinks.hydrationFeedback.contains("获得今日奖杯"))
        precondition(drinks.gardenTrophies.count == 1)
        try await capture(drinkCard(), size: NSSize(width: 300, height: 420), name: "drink-presets-custom")
        let trophyApp = try AppController(dataDirectory: directory.appendingPathComponent("trophies"))
        var trophyPlan = trophyApp.settings.waterPlan
        trophyPlan.dailyTargetML = 300
        let trophyDays = [-18, -9, -3, 0]
        let trophyTypes: [DrinkPreset] = [.waterBottle, .coffee, .tea, .milk]
        for (offset, preset) in zip(trophyDays, trophyTypes) {
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))!
            try trophyApp.ledger.drink(at: day.addingTimeInterval(12 * 3600), source: "preview_fixture",
                                       amountML: 300, drinkPresetID: preset.rawValue)
            try trophyApp.ledger.awardGardenTrophy(for: day, plan: trophyPlan)
        }
        precondition(trophyApp.gardenTrophies.count == 4)
        precondition(trophyApp.gardenTrophies.last?.recipe == .milkLily)
        try await capture(HistoryPage(app: trophyApp).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 790, height: 900), name: "trophy-calendar")
        try await capture(HistoryPage(app: trophyApp).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 790, height: 900), name: "trophy-calendar-dark", dark: true)
        let migrationDirectory = directory.appendingPathComponent("serving-migration")
        let migrationRepository = try Repository(url: migrationDirectory.appendingPathComponent("workrhythm.sqlite"))
        var legacySettings = AppSettings()
        var legacyPlan = legacySettings.waterPlan
        legacyPlan.presetVolumesML = ["waterBottle": 450, "tea": 450, "coffee": 500]
        legacySettings.hydrationPlan = legacyPlan
        try migrationRepository.saveSettings(legacySettings)
        try migrationRepository.save(HydrationEvent(timestamp: Date(), source: "legacy", amountML: 450,
                                                    drinkPresetID: DrinkPreset.waterBottle.rawValue))
        let migratedApp = try AppController(dataDirectory: migrationDirectory)
        precondition(migratedApp.settings.waterPlan.servingML(for: .waterBottle) == 500)
        precondition(migratedApp.settings.waterPlan.servingML(for: .tea) == 500)
        precondition(migratedApp.settings.waterPlan.servingML(for: .coffee) == 500)
        precondition(migratedApp.water.first?.amountML == 450, "Serving migration must not rewrite history")
        let fresh = try AppController(dataDirectory: directory.appendingPathComponent("actual-amounts"))
        fresh.state = .active
        fresh.drink(source: "preview_fixture", preset: .coffee, amountML: 500)
        precondition(fresh.waterProgress.totalML == 500)
        precondition(fresh.settings.waterPlan.servingML(for: .coffee) == 500)
        precondition(fresh.waterProgress.garden.recipe == .sunshine)
        fresh.drink(source: "preview_fixture", preset: .milkTea, amountML: 700)
        precondition(fresh.waterProgress.garden.recipe == .latte)
        fresh.drink(source: "preview_fixture", preset: .cola, amountML: 0)
        precondition(fresh.waterProgress.totalML == 1200, "Invalid amounts cannot create events")
        fresh.errorMessage = ""
        let restored = try AppController(dataDirectory: directory.appendingPathComponent("actual-amounts"))
        precondition(restored.settings.waterPlan.servingML(for: .coffee) == 500)
        precondition(restored.settings.waterPlan.servingML(for: .milkTea) == 700)
        precondition(restored.settings.waterPlan.selectedDrink == .milkTea)
        precondition(restored.waterProgress.garden == fresh.waterProgress.garden)
        try await capture(MenuContent(app: fresh).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 340, height: 440), name: "menu-latte")
        fresh.undoLastDrink()
        precondition(fresh.waterProgress.garden.recipe == .sunshine)
        try await capture(MenuContent(app: fresh, availableHeight: 380).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 340, height: 380), name: "menu-coffee-small")
        fresh.startFocus(25)
        fresh.pendingReminder = "water"
        try await capture(MenuContent(app: fresh, availableHeight: 380).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 340, height: 380), name: "menu-focus-reminder-small")
        fresh.pauseFocus()
        try await capture(MenuContent(app: fresh).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 340, height: 440), name: "menu-paused-dark", dark: true)
        fresh.endFocus()
        try await capture(RecipeCatalog(garden: drinks.waterProgress.garden).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 402, height: 470), name: "recipe-catalog")
        let recipes = LazyVGrid(columns: [GridItem(.fixed(190)), GridItem(.fixed(190))], spacing: 18) {
            ForEach(GardenRecipe.allCases, id: \.self) { recipe in
                VStack(spacing: 5) {
                    HydrationArtwork(theme: .flowers, fraction: 1, phase: 0, recipe: recipe)
                        .frame(width: 120, height: 122)
                    Text(recipe.title).font(.headline).foregroundStyle(recipe.tint)
                    Text(recipe.formula).font(.caption).foregroundStyle(.secondary)
                }.padding(10).background(recipe.tint.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
        }.padding(20).background(Color(nsColor: .windowBackgroundColor))
        try await capture(recipes, size: NSSize(width: 450, height: 1300), name: "recipe-gallery")
        let sliderApp = try AppController(dataDirectory: directory.appendingPathComponent("slider"))
        sliderApp.state = .active
        for ml in [-1, 0, 2001, 3000] { sliderApp.recordPresetDrink(.tea, amountML: ml) }
        precondition(sliderApp.water.isEmpty, "Out-of-range package submissions must not record")
        sliderApp.errorMessage = ""
        sliderApp.recordPresetDrink(.tea, amountML: 310)
        precondition(sliderApp.waterProgress.garden.recipe == .teaBell)
        sliderApp.recordPresetDrink(.milk, amountML: 250)
        precondition(sliderApp.waterProgress.totalML == 560)
        precondition(sliderApp.waterProgress.garden.recipe == .matcha)
        for height: CGFloat in [380, 440] {
            let natural = NSHostingView(rootView: MenuContent(app: sliderApp, availableHeight: height)
                .menuBody.frame(width: 340).fixedSize(horizontal: false, vertical: true))
            natural.layoutSubtreeIfNeeded()
            let needed = natural.fittingSize.height
            try Data("naturalHeight=\(needed) available=\(height)".utf8)
                .write(to: output.appendingPathComponent("menu-natural-\(Int(height)).txt"))
            precondition(needed <= height, "Unconstrained menu contents must fit: \(needed) > \(height)")
        }
        try await capture(MenuContent(app: sliderApp).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 340, height: 440), name: "menu-six-drinks")
        try await capture(MenuContent(app: sliderApp, availableHeight: 380).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 340, height: 380), name: "menu-slider-small")
        try await capture(MenuContent(app: sliderApp).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 340, height: 440), name: "menu-slider-dark", dark: true)
        let reopenedSlider = try AppController(dataDirectory: directory.appendingPathComponent("slider"))
        precondition(reopenedSlider.settings.waterPlan.selectedDrink == .milk)
        precondition(reopenedSlider.settings.waterPlan.servingML(for: .milk) == 250)
        precondition(reopenedSlider.waterProgress.garden.recipe == .matcha)
        sliderApp.undoLastDrink()
        precondition(sliderApp.waterProgress.totalML == 310 && sliderApp.waterProgress.garden.recipe == .teaBell)
        for (offset, metadata) in [(-3600.0, "lockObserved(uptime: 12.0, idleSeconds: 0.0, stillInCorner: true)"),
                                   (-3500.0, "displaySleep(uptime: 13.0, idleSeconds: 0.0, stillInCorner: true)"),
                                   (-1800.0, "displayWake"), (-1799.0, "unlock")] {
            sliderApp.log("system_event", metadata, at: sliderApp.now.addingTimeInterval(offset))
        }
        for (offset, state, reason) in [
            (-5400.0, WorkstationState.active, "preview_return"),
            (-4800.0, .locked, "lock"),
            (-4500.0, .active, "unlock"),
            (-3000.0, .moving, "lid_closed_possible_moving"),
            (-2700.0, .active, "lid_open_return"),
            (-1200.0, .away, "hot_corner:br"),
            (-900.0, .active, "display_wake")
        ] {
            try sliderApp.ledger.transition(Transition(state: state, at: sliderApp.now.addingTimeInterval(offset),
                                                       reason: reason, confidence: 1))
        }
        let previewLock = sliderApp.sessions.first { $0.kind == .locked }!
        let previewLid = sliderApp.sessions.first { $0.kind == .moving }!
        try sliderApp.ledger.label(id: previewLock.id, value: "会议")
        try sliderApp.ledger.label(id: previewLid.id, value: "用餐")
        sliderApp.revision += 1
        let departureSummary = sliderApp.summary(sliderApp.now)
        precondition(departureSummary.breaks == 3 && departureSummary.lockLeaves == 1 && departureSummary.lidLeaves == 1)
        precondition(ActivityRecords.departures(sliderApp.sessions, day: sliderApp.now, now: sliderApp.now).count == 3)
        precondition(ActivityRecords.departures(sliderApp.sessions, day: sliderApp.now, now: sliderApp.now)
            .filter { !$0.label.isEmpty }.count == 2)
        sliderApp.recordPresetDrink(.coffee, amountML: 240)
        sliderApp.recordPresetDrink(.milkTea, amountML: 350)
        sliderApp.recordPresetDrink(.waterBottle, amountML: 500)
        try await render("menu-empty-screen-events")
        try await capture(MenuContent(app: sliderApp).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 340, height: 440), name: "menu-records")
        try await capture(MenuContent(app: sliderApp).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 340, height: 440), name: "menu-records-dark", dark: true)
        try await capture(MenuContent(app: sliderApp, availableHeight: 380).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 340, height: 380), name: "menu-records-short")
        try await capture(DrinkComposer(plan: sliderApp.settings.waterPlan, tint: .teal, onRecord: { _, _ in })
                            .background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 320, height: 310), name: "drink-composer")
        try await capture(ActivityRecordsPage(app: sliderApp).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 770, height: 680), name: "records")
        try await capture(ActivityRecordsPage(app: sliderApp).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 650, height: 680), name: "records-dark-narrow", dark: true)
        try await capture(DashboardPage(app: sliderApp).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 770, height: 740), name: "dashboard-records")
        try await capture(DashboardPage(app: sliderApp).background(Color(nsColor: .windowBackgroundColor)),
                          size: NSSize(width: 635, height: 740), name: "dashboard-narrow")
        // Exercise actual SwiftUI accessibility actions in the isolated preview process.
        // No Accessibility permission or personal app interaction is needed.
        let interactionApp = try AppController(dataDirectory: directory.appendingPathComponent("interaction"))
        interactionApp.state = .active
        interactionApp.updateWaterPlan { $0.setServingML(500, for: .waterBottle) }
        var openedPage = ""
        interactionApp.openPage = { openedPage = $0 }
        let interactionHost = NSHostingView(rootView: MenuContent(app: interactionApp))
        let interactionWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
                                          styleMask: [.borderless], backing: .buffered, defer: false)
        interactionWindow.contentView = interactionHost
        interactionWindow.center()
        interactionWindow.makeKeyAndOrderFront(nil)
        func accessibilityTree(_ node: Any, depth: Int = 0) -> [NSObject] {
            guard depth < 24, let element = node as? NSObject else { return [] }
            // SwiftUI's virtual children use the informal accessibility bridge.
            let children = (element as? NSAccessibilityProtocol)?.accessibilityChildren()
                ?? (element.accessibilityAttributeValue(.children) as? [Any]) ?? []
            return [element] + children.flatMap { accessibilityTree($0, depth: depth + 1) }
        }
        func axLabel(_ element: NSObject) -> String {
            (element as? NSAccessibilityProtocol)?.accessibilityLabel()
                ?? axString(element, selector: "accessibilityLabel")
                ?? (element.accessibilityAttributeValue(.init(rawValue: "AXDescription")) as? String)
                ?? (element.accessibilityAttributeValue(.title) as? String) ?? ""
        }
        func axRole(_ element: NSObject) -> String {
            (element as? NSAccessibilityProtocol)?.accessibilityRole()?.rawValue
                ?? axString(element, selector: "accessibilityRole")
                ?? (element.accessibilityAttributeValue(.role) as? String) ?? ""
        }
        func axString(_ element: NSObject, selector: String) -> String? {
            let action = NSSelectorFromString(selector)
            guard element.responds(to: action) else { return nil }
            return element.perform(action)?.takeUnretainedValue() as? String
        }
        func press(_ label: String, exact: Bool = true) async throws {
            try await Task.sleep(for: .seconds(0.15))
            let nodes = NSApp.windows.filter(\.isVisible).flatMap { accessibilityTree($0) }
            let match = nodes.first {
                let title = axLabel($0)
                return axRole($0) == "AXButton" && (exact ? title == label : title.contains(label))
            }
            guard let match else {
                let dump = nodes.map { "\(type(of: $0)) | \(axRole($0)) | \(axLabel($0))" }.joined(separator: "\n")
                try dump.write(to: output.appendingPathComponent("accessibility-tree.txt"), atomically: true, encoding: .utf8)
                throw NSError(domain: "PreviewAction", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot press \(label)"])
            }
            let action = NSSelectorFromString("accessibilityPerformPress")
            if let element = match as? NSAccessibilityProtocol { precondition(element.accessibilityPerformPress()) }
            else if match.responds(to: action) {
                typealias PressAction = @convention(c) (AnyObject, Selector) -> Bool
                let perform = unsafeBitCast(match.method(for: action), to: PressAction.self)
                precondition(perform(match, action))
            } else { match.accessibilityPerformAction(.press) }
            try await Task.sleep(for: .seconds(0.1))
        }
        try await press("水 · 500 mL", exact: false)
        try await press("选择咖啡，不记录")
        try await press("选择咖啡 270 毫升节点")
        precondition(interactionApp.water.isEmpty, "Selection must not record")
        try await press("记录咖啡 · 270 mL")
        precondition(interactionApp.waterProgress.totalML == 270 && interactionApp.waterProgress.count == 1)
        precondition(interactionApp.settings.waterPlan.selectedDrink == .coffee)
        try await press("记录咖啡 270 毫升")
        precondition(interactionApp.waterProgress.totalML == 540 && interactionApp.waterProgress.count == 2)
        try await press("撤销")
        precondition(interactionApp.waterProgress.totalML == 270 && interactionApp.waterProgress.count == 1)
        try await press("30分")
        precondition(interactionApp.currentFocus?.plannedDuration == 30 * 60)
        interactionApp.endFocus()
        try await press("45分")
        precondition(interactionApp.currentFocus?.plannedDuration == 45 * 60)
        interactionApp.endFocus()
        try await press("花历")
        precondition(openedPage == "history")
        try await press("全部", exact: false)
        precondition(openedPage == "records")
        interactionWindow.orderOut(nil)
        sliderApp.startFocus(25)
        sliderApp.pendingReminder = "water"
        sliderApp.errorMessage = "preview error"
        for height: CGFloat in [380, 440] {
            let natural = NSHostingView(rootView: MenuContent(app: sliderApp, availableHeight: height)
                .menuBody.frame(width: 340).fixedSize(horizontal: false, vertical: true))
            natural.layoutSubtreeIfNeeded()
            precondition(natural.fittingSize.height <= height, "Dense menu + focus + reminder must fit")
        }
        try "PASS: native chooser, select without saving, confirm once, remembered quick record, undo, direct 30/45-minute focus controls, flower calendar and full records navigation; lock, lid and active departure records/counts with quick labels; dense layout with focus/reminder/error."
            .write(to: output.appendingPathComponent("interaction-result.txt"), atomically: true, encoding: .utf8)
        try Data("PASS: subtle recipe tint covers the full menu while rising card water remains distinct; direct 25/30/45-minute focus controls; rising card water levels at empty/partial/complete, garden and water animations stop when hidden or disabled; garden trophy persistence and four-day calendar in light/dark; six drinks with merged package nodes, continuous sliders and exact custom amounts, invalid ranges rejected, tea310 and milk250 persisted, matcha undo/restart, twelve recipe artwork previews; main menu no NSScrollView and natural contents fit 440/380pt; legacy timeline/cache/hydration regression. Live animation/visibility: \(canCheckLiveAnimation ? "PASS" : "SKIPPED (window occluded)")".utf8)
            .write(to: output.appendingPathComponent("result.txt"))
        NSApp.terminate(nil)
    }
}
