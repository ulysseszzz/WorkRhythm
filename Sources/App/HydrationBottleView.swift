import SwiftUI
import AppKit
import Combine
import QuartzCore

/// Shared event-driven policy; no battery or temperature polling.
final class AnimationEnergyPolicy: ObservableObject {
    static let shared = AnimationEnergyPolicy()
    @Published private(set) var framesPerSecond: Double
    private var subscriptions: [AnyCancellable] = []
    private static func currentFPS() -> Double {
        let process = ProcessInfo.processInfo
        return RuntimeBudget.animationFPS(lowPower: process.isLowPowerModeEnabled,
            thermallyConstrained: process.thermalState == .serious || process.thermalState == .critical)
    }
    private init() {
        framesPerSecond = Self.currentFPS()
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange,
                     ProcessInfo.thermalStateDidChangeNotification] {
            NotificationCenter.default.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    let value = Self.currentFPS()
                    if self?.framesPerSecond != value { self?.framesPerSecond = value }
                }.store(in: &subscriptions)
        }
    }
}

/// The scene is the only animated subtree. Hidden/occluded windows, offscreen scroll content,
/// display sleep and Reduce Motion remove its animation schedule entirely.
struct HydrationScene: View {
    let theme: HydrationTheme
    let fraction: Double
    var motionEnabled = true
    var recipe: GardenRecipe = .dew
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var energy = AnimationEnergyPolicy.shared
    @ViewState private var visible = false
    var body: some View {
        HydrationLayerView(theme: theme, fraction: fraction, recipe: recipe,
            fps: visible && motionEnabled && !reduceMotion ? energy.framesPerSecond : 0)
        .background(SceneVisibilityProbe { visible = $0 })
        .accessibilityHidden(true)
    }
}

/// The card itself acts as the bottle: its waterline rises with daily progress.
/// Core Animation moves cached shape layers without invalidating the card contents.
struct HydrationWaterBackdrop: View {
    let fraction: Double
    var motionEnabled = true
    var recipe: GardenRecipe = .dew
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var energy = AnimationEnergyPolicy.shared
    @ViewState private var visible = false
    var body: some View {
        HydrationWaterLayerView(fraction: fraction, recipe: recipe,
            fps: visible && motionEnabled && !reduceMotion ? energy.framesPerSecond : 0)
        .background(SceneVisibilityProbe { visible = $0 })
        .accessibilityHidden(true)
    }
}

struct HydrationWaterLayerView: NSViewRepresentable {
    let fraction: Double
    let recipe: GardenRecipe
    let fps: Double
    func makeNSView(context: Context) -> WaterView { WaterView() }
    func updateNSView(_ view: WaterView, context: Context) {
        view.configure(fraction: fraction, recipe: recipe, fps: fps)
    }
    static func dismantleNSView(_ view: WaterView, coordinator: ()) { view.stopMotion() }

    final class WaterView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        private var fraction = -1.0
        private var recipe: GardenRecipe = .dew
        private var fps = 0.0
        private var renderedSize = CGSize.zero
        private var moving: [CALayer] = []
        private var appliedFPS = -1.0
        private var dirty = true
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(fraction: Double, recipe: GardenRecipe, fps: Double) {
            let clamped = min(1, max(0, fraction))
            if self.fraction != clamped || self.recipe != recipe { dirty = true }
            self.fraction = clamped
            self.recipe = recipe
            self.fps = clamped > 0 ? fps : 0
            rebuildIfNeeded()
            updateMotion()
        }
        override func layout() {
            super.layout()
            rebuildIfNeeded()
            updateMotion()
        }
        private func rebuildIfNeeded() {
            guard bounds.width > 0, bounds.height > 0, fraction >= 0, let root = layer else { return }
            guard dirty || renderedSize != bounds.size else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            root.sublayers = nil
            moving.removeAll()
            appliedFPS = -1
            dirty = false
            renderedSize = bounds.size
            let color = NSColor(red: recipe.rgb.0, green: recipe.rgb.1, blue: recipe.rgb.2, alpha: 1)
            let base = CAGradientLayer()
            base.frame = bounds
            base.colors = [color.withAlphaComponent(0.045).cgColor, color.withAlphaComponent(0.018).cgColor]
            base.startPoint = CGPoint(x: 0, y: 0)
            base.endPoint = CGPoint(x: 1, y: 1)
            root.addSublayer(base)
            guard fraction > 0 else { return }
            let amplitude: CGFloat = 3
            let width = bounds.width + amplitude * 8
            let level = fraction >= 1 ? -amplitude : bounds.height * CGFloat(1 - fraction)
            for index in 0..<2 {
                let wave = CAShapeLayer()
                wave.frame = CGRect(x: -amplitude * 4, y: 0, width: width, height: bounds.height)
                let path = CGMutablePath()
                let offset = CGFloat(index) * 2
                path.move(to: CGPoint(x: 0, y: level + offset))
                var x: CGFloat = 0
                while x <= width {
                    let y = level + offset + sin(x * 0.055 + CGFloat(index) * 2.2) * amplitude
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += 3
                }
                path.addLine(to: CGPoint(x: width, y: bounds.height))
                path.addLine(to: CGPoint(x: 0, y: bounds.height))
                path.closeSubpath()
                wave.path = path
                wave.fillColor = color.withAlphaComponent(index == 0 ? 0.075 : 0.115).cgColor
                root.addSublayer(wave)
                moving.append(wave)
            }
        }
        func stopMotion() {
            moving.forEach { $0.removeAllAnimations() }
            appliedFPS = -1
        }
        private func updateMotion() {
            guard appliedFPS != fps else { return }
            moving.forEach { $0.removeAllAnimations() }
            appliedFPS = fps
            guard fps > 0 else { return }
            for (index, wave) in moving.enumerated() {
                let animation = CABasicAnimation(keyPath: "transform.translation.x")
                let travel = bounds.width * (index == 0 ? 0.035 : 0.025)
                animation.fromValue = index == 0 ? -travel : travel
                animation.toValue = index == 0 ? travel : -travel
                animation.duration = index == 0 ? 2.4 : 3.1
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.preferredFrameRateRange = CAFrameRateRange(
                    minimum: Float(fps), maximum: Float(fps), preferred: Float(fps))
                wave.add(animation, forKey: "waterline")
            }
        }
    }
}

/// Rasterize tiny vector parts only when their content/size changes. Core Animation
/// moves the cached parts; no per-frame SwiftUI invalidation or Canvas execution.
struct HydrationLayerView: NSViewRepresentable {
    let theme: HydrationTheme
    let fraction: Double
    let recipe: GardenRecipe
    let fps: Double
    func makeNSView(context: Context) -> ArtworkView { ArtworkView() }
    func updateNSView(_ view: ArtworkView, context: Context) {
        view.configure(theme: theme, fraction: fraction, fps: fps, recipe: recipe)
    }
    static func dismantleNSView(_ view: ArtworkView, coordinator: ()) { view.stopMotion() }

    final class ArtworkView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        private var theme: HydrationTheme = .bottle
        private var fraction = -1.0
        private var fps = 0.0
        private var recipe: GardenRecipe = .dew
        private var renderedSize = CGSize.zero
        private var renderedScale = 0.0
        private var dirty = true
        private var moving: [CALayer] = []
        private var appliedFPS = -1.0
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func configure(theme: HydrationTheme, fraction: Double, fps: Double, recipe: GardenRecipe) {
            let clamped = min(1, max(0, fraction))
            if self.theme != theme || self.fraction != clamped || self.recipe != recipe { dirty = true }
            self.recipe = recipe
            self.theme = theme; self.fraction = clamped
            self.fps = theme == .bottle && clamped == 0 ? 0 : fps
            rebuildIfNeeded()
            updateMotion()
        }
        override func layout() { super.layout(); rebuildIfNeeded(); updateMotion() }
        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties(); rebuildIfNeeded(); updateMotion()
        }
        private func rebuildIfNeeded() {
            guard bounds.width > 0, bounds.height > 0, fraction >= 0, let root = layer else { return }
            let scale = window?.backingScaleFactor ?? 2
            guard dirty || renderedSize != bounds.size || renderedScale != scale else { return }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }
            root.sublayers = nil; moving.removeAll(); appliedFPS = -1
            renderedSize = bounds.size; renderedScale = scale; dirty = false
            func image(_ part: HydrationArtPart, parent: CALayer? = nil) -> CALayer {
                let renderer = ImageRenderer(content:
                    HydrationArtwork(theme: theme, fraction: fraction, phase: 0, part: part, recipe: recipe)
                        .frame(width: bounds.width, height: bounds.height))
                renderer.scale = scale
                let result = CALayer()
                result.frame = CGRect(origin: .zero, size: bounds.size)
                result.contents = renderer.cgImage; result.contentsScale = scale
                (parent ?? root).addSublayer(result)
                return result
            }
            if theme == .bottle {
                let container = CALayer()
                container.frame = CGRect(origin: .zero, size: bounds.size)
                let mask = CAShapeLayer()
                var transform = CGAffineTransform(scaleX: bounds.width / 100, y: bounds.height / 136)
                mask.path = HydrationArtwork.bottleOutline.cgPath.copy(using: &transform)
                container.mask = mask
                root.addSublayer(container)
                moving.append(image(.water, parent: container))
                _ = image(.base)
            } else {
                _ = image(.base)
                for i in 0..<3 {
                    let plant = image(.plant(i))
                    let anchor = CGPoint(x: [0.50, 0.25, 0.76][i], y: 118.0 / 136)
                    plant.anchorPoint = anchor
                    plant.position = CGPoint(x: anchor.x * bounds.width, y: anchor.y * bounds.height)
                    moving.append(plant)
                }
            }
        }
        func stopMotion() {
            moving.forEach { $0.removeAllAnimations() }
            appliedFPS = -1
        }
        private func updateMotion() {
            guard appliedFPS != fps, !moving.isEmpty else { return }
            moving.forEach { $0.removeAllAnimations() }
            appliedFPS = fps
            guard fps > 0 else { return }
            for (i, part) in moving.enumerated() {
                let water = theme == .bottle
                let animation = CABasicAnimation(keyPath: water ? "transform.translation.x" : "transform.rotation.z")
                let amplitude = water ? bounds.width * 0.06 : 0.035
                animation.fromValue = -amplitude; animation.toValue = amplitude
                animation.duration = water ? 1.8 : 1.7 + Double(i) * 0.3
                animation.autoreverses = true; animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: Float(fps), maximum: Float(fps), preferred: Float(fps))
                part.add(animation, forKey: "ambient")
            }
        }
    }
}

struct SceneVisibilityProbe: NSViewRepresentable {
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }
    func updateNSView(_ view: VisibilityView, context: Context) { view.onChange = onChange; view.check() }
    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.stop() }

    final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observations: [(NotificationCenter, NSObjectProtocol)] = []
        // SwiftUI can replace this NSView while retaining HydrationScene's @State.
        // Always deliver the initial false as well, or a retained true can keep a hidden timeline alive.
        private var lastValue: Bool?
        private var displayAwake = true
        private weak var observedClip: NSClipView?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); observe() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); observe() }
        override func layout() {
            super.layout()
            if enclosingScrollView?.contentView !== observedClip { observe() }
            else { check() }
        }
        func stop() {
            observations.forEach { $0.0.removeObserver($0.1) }
            observations.removeAll()
        }
        deinit { stop() }
        private func observe() {
            stop()
            guard let window else { check(); return }
            let center = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.didResizeNotification] {
                watch(center, name, window)
            }
            observedClip = enclosingScrollView?.contentView
            if let clip = observedClip {
                clip.postsBoundsChangedNotifications = true
                watch(center, NSView.boundsDidChangeNotification, clip)
            }
            let workspace = NSWorkspace.shared.notificationCenter
            watch(workspace, NSWorkspace.screensDidSleepNotification, nil)
            watch(workspace, NSWorkspace.screensDidWakeNotification, nil)
            check()
        }
        private func watch(_ center: NotificationCenter, _ name: Notification.Name, _ object: Any?) {
            let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] note in
                guard let self else { return }
                if note.name == NSWorkspace.screensDidSleepNotification { self.displayAwake = false }
                if note.name == NSWorkspace.screensDidWakeNotification { self.displayAwake = true }
                self.check()
            }
            observations.append((center, token))
        }
        func check() {
            // Modern NSView may report visibleRect outside its bounds when clipsToBounds is false.
            let value = displayAwake && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
                && !isHiddenOrHasHiddenAncestor && !bounds.isEmpty && bounds.intersects(visibleRect)
            guard value != lastValue else { return }
            lastValue = value
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastValue == value else { return }
                self.onChange?(value)
            }
        }
    }
}

/// Vector art uses a 100 × 136 coordinate space and no image resources.
enum HydrationArtPart: Equatable { case all, base, water, plant(Int) }

struct HydrationArtwork: View, Animatable {
    let theme: HydrationTheme
    var fraction: Double
    var phase: Double
    var part: HydrationArtPart = .all
    var recipe: GardenRecipe = .dew
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }
    var body: some View {
        Canvas { context, size in
            var c = context
            c.scaleBy(x: size.width / 100, y: size.height / 136)
            switch theme {
            case .bottle: bottle(&c)
            case .flowers: flowers(&c)
            }
        }
    }
    private var growth: Double { min(1, max(0, fraction)) }
    private var foliage: Color { Color(red: 0.20, green: 0.54, blue: 0.40) }
    private func stroke(_ c: inout GraphicsContext, _ points: [CGPoint], color: Color, width: Double) {
        var p = Path(); p.addLines(points)
        c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
    private func ellipse(_ c: inout GraphicsContext, x: Double, y: Double, w: Double, h: Double, color: Color) {
        c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
    }
    static var bottleOutline: Path {
        var outline = Path()
        outline.move(to: CGPoint(x: 34, y: 17))
        outline.addLine(to: CGPoint(x: 66, y: 17))
        outline.addLine(to: CGPoint(x: 66, y: 29))
        outline.addCurve(to: CGPoint(x: 87, y: 53), control1: CGPoint(x: 66, y: 39), control2: CGPoint(x: 87, y: 40))
        outline.addLine(to: CGPoint(x: 87, y: 116))
        outline.addQuadCurve(to: CGPoint(x: 76, y: 128), control: CGPoint(x: 87, y: 128))
        outline.addLine(to: CGPoint(x: 24, y: 128))
        outline.addQuadCurve(to: CGPoint(x: 13, y: 116), control: CGPoint(x: 13, y: 128))
        outline.addLine(to: CGPoint(x: 13, y: 53))
        outline.addCurve(to: CGPoint(x: 34, y: 29), control1: CGPoint(x: 13, y: 40), control2: CGPoint(x: 34, y: 39))
        outline.closeSubpath()
        return outline
    }
    private func bottle(_ c: inout GraphicsContext) {
        let outline = Self.bottleOutline
        if part != .water { c.fill(outline, with: .color(.cyan.opacity(0.07))) }
        var water = c
        if part == .all { water.clip(to: outline) }
        if growth > 0 && (part == .all || part == .water) {
            for layer in 0..<2 {
                let level = 129 - 105 * growth + Double(layer) * 2
                var wave = Path()
                wave.move(to: CGPoint(x: 0, y: level))
                for x in stride(from: 0.0, through: 100.0, by: 2) {
                    let y = level + sin(x * 0.075 + phase * 1.8 + Double(layer) * 2.3) * 2.4
                    wave.addLine(to: CGPoint(x: x, y: y))
                }
                wave.addLine(to: CGPoint(x: 100, y: 136)); wave.addLine(to: CGPoint(x: 0, y: 136))
                wave.closeSubpath()
                let colors: [Color] = recipe == .rainbow
                    ? [.pink.opacity(0.7), .indigo.opacity(0.75), .cyan.opacity(0.85)]
                    : [recipe.tint.opacity(layer == 0 ? 0.35 : 0.65), recipe.tint.opacity(0.95)]
                water.fill(wave, with: .linearGradient(Gradient(colors: colors),
                                                       startPoint: CGPoint(x: 50, y: level), endPoint: CGPoint(x: 50, y: 136)))
            }
            for i in 0..<3 {
                let rise = (phase * 5 + Double(i) * 27).truncatingRemainder(dividingBy: 95)
                ellipse(&water, x: 28 + Double(i) * 16, y: 125 - rise * growth, w: 3, h: 3, color: .white.opacity(0.35))
            }
        }
        guard part != .water else { return }
        c.stroke(outline, with: .color(.teal.opacity(0.6)), lineWidth: 1.5)
        c.fill(Path(roundedRect: CGRect(x: 31, y: 9, width: 38, height: 10), cornerRadius: 4), with: .color(.teal))
        stroke(&c, [CGPoint(x: 24, y: 57), CGPoint(x: 24, y: 106)], color: .white.opacity(0.55), width: 3)
        for y in [64.0, 83.0, 102.0] {
            stroke(&c, [CGPoint(x: 65, y: y), CGPoint(x: 77, y: y)], color: .white.opacity(0.8), width: 2)
        }
        let mark = Text(growth >= 1 ? "✓" : "+").font(.system(size: 22, weight: .medium)).foregroundColor(.teal)
        c.draw(mark, at: CGPoint(x: 49, y: 85))
    }
    private func leaf(_ c: inout GraphicsContext, at origin: CGPoint, angle: Double, length: Double, color: Color) {
        var local = c
        local.translateBy(x: origin.x, y: origin.y)
        local.rotate(by: .degrees(angle))
        var p = Path()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: 0, y: -length), control1: CGPoint(x: -length * 0.7, y: -length * 0.4),
                   control2: CGPoint(x: -length * 0.35, y: -length * 0.85))
        p.addCurve(to: .zero, control1: CGPoint(x: length * 0.65, y: -length * 0.8),
                   control2: CGPoint(x: length * 0.5, y: -length * 0.25))
        local.fill(p, with: .color(color))
        stroke(&local, [.zero, CGPoint(x: 0, y: -length * 0.76)], color: .white.opacity(0.32), width: 0.65)
    }
    private func flowers(_ c: inout GraphicsContext) {
        if part == .all || part == .base {
            ellipse(&c, x: 7, y: 117, w: 88, h: 13, color: .teal.opacity(0.1))
            ellipse(&c, x: 76, y: 9, w: 15, h: 15, color: .yellow.opacity(0.35))
        }
        for i in 0..<3 {
            guard part == .all || part == .plant(i) else { continue }
            let index = Double(i)
            let height = [85.0, 63.0, 70.0][i] * (0.18 + growth * 0.82)
            let x = [50.0, 25.0, 76.0][i]
            let sway = sin(phase * 1.5 + index * 1.7) * (2 + growth)
            var plant = c
            plant.translateBy(x: x, y: 118)
            plant.rotate(by: .degrees(sway))
            var stem = Path()
            stem.move(to: .zero)
            stem.addCurve(to: CGPoint(x: 0, y: -height),
                          control1: CGPoint(x: -7, y: -height * 0.4), control2: CGPoint(x: 5, y: -height * 0.8))
            plant.stroke(stem, with: .color(foliage), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for side in 0..<2 {
                leaf(&plant, at: CGPoint(x: -1, y: -height * (side == 0 ? 0.32 : 0.58)),
                     angle: (side == 0 ? -58.0 : 58.0) + sin(phase * 1.8 + index + Double(side)) * 6,
                     length: 8 + growth * 8, color: side == 0 ? foliage : Color(red: 0.34, green: 0.65, blue: 0.39))
            }
            let bloom = min(1, max(0, (growth - [0.18, 0.38, 0.60][i]) / 0.4))
            var head = plant
            head.translateBy(x: 0, y: -height)
            if bloom > 0 {
                blossom(&head, bloom: bloom, index: i)
            } else {
                ellipse(&head, x: -3, y: -6, w: 6, h: 8, color: foliage)
            }
        }
        if part == .all || part == .base {
            c.fill(Path(roundedRect: CGRect(x: 12, y: 117, width: 77, height: 7), cornerRadius: 3), with: .color(.brown.opacity(0.5)))
        }
    }
    private func blossom(_ c: inout GraphicsContext, bloom: Double, index: Int) {
        var head = c
        head.scaleBy(x: bloom, y: bloom)
        switch recipe {
        case .teaBell:
            // Three hanging bell blossoms branch from the stem.
            for bell in 0..<3 {
                let x = Double(bell - 1) * 11
                let y = bell == 1 ? -18.0 : -8.0
                stroke(&head, [CGPoint(x: 0, y: 2), CGPoint(x: x, y: y - 7)], color: foliage, width: 1.4)
                var shape = Path()
                shape.move(to: CGPoint(x: x, y: y - 8))
                shape.addCurve(to: CGPoint(x: x + 7, y: y + 4), control1: CGPoint(x: x + 6, y: y - 8), control2: CGPoint(x: x + 4, y: y + 2))
                shape.addQuadCurve(to: CGPoint(x: x - 7, y: y + 4), control: CGPoint(x: x, y: y + 8))
                shape.addCurve(to: CGPoint(x: x, y: y - 8), control1: CGPoint(x: x - 4, y: y + 2), control2: CGPoint(x: x - 6, y: y - 8))
                head.fill(shape, with: .color(Color(red: 0.7, green: 0.9, blue: 0.74)))
                head.stroke(shape, with: .color(recipe.tint.opacity(0.6)), lineWidth: 0.7)
            }
        case .milkLily, .matcha:
            let petals = recipe == .milkLily ? 6 : 5
            for n in 0..<petals {
                var p = head
                p.rotate(by: .degrees(Double(n) * 360 / Double(petals)))
                var petal = Path()
                petal.move(to: .zero)
                petal.addQuadCurve(to: CGPoint(x: 0, y: -22), control: CGPoint(x: -12, y: -14))
                petal.addQuadCurve(to: .zero, control: CGPoint(x: 12, y: -14))
                p.fill(petal, with: .color(recipe == .milkLily ? Color(red: 1, green: 0.97, blue: 0.82) : Color(red: 0.70, green: 0.87, blue: 0.49)))
                p.stroke(petal, with: .color(recipe.tint.opacity(0.6)), lineWidth: 0.6)
            }
            ellipse(&head, x: -4, y: -4, w: 8, h: 8, color: recipe == .milkLily ? .orange : .pink)
        case .creamDahlia:
            for ring in 0..<3 {
                let r = 21.0 - Double(ring) * 5
                for n in 0..<12 {
                    var p = head
                    p.rotate(by: .degrees(Double(n) * 30 + Double(ring) * 15))
                    ellipse(&p, x: -3.5, y: -r, w: 7, h: r * 0.7,
                            color: [Color(red: 0.93, green: 0.68, blue: 0.43), Color(red: 1, green: 0.83, blue: 0.55), Color(red: 1, green: 0.95, blue: 0.75)][ring])
                }
            }
            ellipse(&head, x: -3, y: -3, w: 6, h: 6, color: .orange)
        case .velvet, .peach:
            // Upright, three-point cup silhouette, distinct from radial flowers.
            var cup = Path()
            cup.move(to: CGPoint(x: -12, y: -19))
            cup.addLine(to: CGPoint(x: -5, y: -12))
            cup.addLine(to: CGPoint(x: 0, y: -22))
            cup.addLine(to: CGPoint(x: 5, y: -12))
            cup.addLine(to: CGPoint(x: 12, y: -19))
            cup.addCurve(to: CGPoint(x: 0, y: 3), control1: CGPoint(x: 16, y: -2), control2: CGPoint(x: 8, y: 3))
            cup.addCurve(to: CGPoint(x: -12, y: -19), control1: CGPoint(x: -8, y: 3), control2: CGPoint(x: -16, y: -2))
            head.fill(cup, with: .color(recipe == .peach ? .pink.opacity(0.8) : Color(red: 0.86, green: 0.65, blue: 0.84)))
            stroke(&head, [CGPoint(x: 0, y: -14), CGPoint(x: 0, y: 0)], color: .white.opacity(0.55), width: 1)
        case .latte:
            for ring in 0..<3 {
                let radius = 17.0 - Double(ring) * 4
                for petal in 0..<5 {
                    var p = head
                    p.rotate(by: .degrees(Double(petal) * 72 + Double(ring) * 36))
                    ellipse(&p, x: -radius * 0.42, y: -radius, w: radius * 0.84, h: radius,
                            color: [recipe.tint, Color.pink.opacity(0.72), Color(red: 0.96, green: 0.75, blue: 0.7)][ring])
                }
            }
        default:
            let petals = recipe == .sunshine || recipe == .morning ? 14 : recipe == .starlight ? 8 : 10
            let palette: [Color] = [.pink, .orange, .yellow, .mint, .cyan, .indigo, .purple]
            for petal in 0..<petals {
                var p = head
                p.rotate(by: .degrees(Double(petal) * 360 / Double(petals) + Double(index) * 8))
                let color: Color = recipe == .rainbow ? palette[petal % palette.count]
                    : recipe == .dew ? Color(red: 0.88, green: 0.95, blue: 1)
                    : recipe == .sunshine ? .yellow : recipe == .morning ? .orange : .purple.opacity(0.7)
                let width = recipe == .sunshine || recipe == .morning ? 6.0 : 9.0
                ellipse(&p, x: -width / 2, y: -18, w: width, h: 15, color: color)
            }
            let center = recipe == .sunshine ? Color.brown : Color(red: 1, green: 0.77, blue: 0.23)
            let diameter = recipe == .sunshine ? 13.0 : 8.0
            ellipse(&head, x: -diameter / 2, y: -diameter / 2, w: diameter, h: diameter, color: center)
        }
    }
}
