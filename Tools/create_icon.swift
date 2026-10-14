import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WorkRhythm-icon-\(UUID()).iconset")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
var images: [Int: Data] = [:]
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        NSColor(calibratedRed: 0.06, green: 0.28, blue: 0.29, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 215, yRadius: 215).fill()
        let ring = NSBezierPath()
        ring.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 270, startAngle: 35, endAngle: 325)
        ring.lineWidth = 58; ring.lineCapStyle = .round
        NSColor(calibratedWhite: 0.95, alpha: 1).setStroke(); ring.stroke()
        let hand = NSBezierPath()
        hand.move(to: NSPoint(x: 512, y: 675)); hand.line(to: NSPoint(x: 512, y: 510)); hand.line(to: NSPoint(x: 625, y: 430))
        hand.lineWidth = 58; hand.lineCapStyle = .round; hand.lineJoinStyle = .round; hand.stroke()
        NSColor(calibratedRed: 1, green: 0.7, blue: 0.36, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 724, y: 467, width: 90, height: 90)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let data = bitmap.representation(using: .png, properties: [:])!
        images[pixels] = data
        try data.write(to: temporary.appendingPathComponent(name))
    }
}
func length(_ value: Int) -> Data {
    var encoded = UInt32(value).bigEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}
var elements = Data()
for (size, type) in [(16, "icp4"), (32, "icp5"), (64, "icp6"), (128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
    let png = images[size]!
    elements.append(Data(type.utf8)); elements.append(length(png.count + 8)); elements.append(png)
}
var icon = Data("icns".utf8)
icon.append(length(elements.count + 8)); icon.append(elements)
try icon.write(to: root.appendingPathComponent("Resources/AppIcon.icns"))
