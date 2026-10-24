import AppKit
import Foundation

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func squircle(in rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.height * 0.225, transform: nil)
}

func bubblePath() -> CGPath {
    let path = CGMutablePath()
    let body = CGRect(x: 248, y: 330, width: 430, height: 340)
    path.addPath(CGPath(roundedRect: body, cornerWidth: 150, cornerHeight: 150, transform: nil))
    path.move(to: CGPoint(x: 318, y: 372))
    path.addCurve(to: CGPoint(x: 236, y: 262), control1: CGPoint(x: 306, y: 320), control2: CGPoint(x: 276, y: 284))
    path.addCurve(to: CGPoint(x: 420, y: 342), control1: CGPoint(x: 318, y: 266), control2: CGPoint(x: 380, y: 300))
    path.closeSubpath()
    return path
}

func drawIcon(_ context: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.45))
    context.addPath(squircle(in: tile))
    context.setFillColor(color(0x1A1F4A))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(squircle(in: tile))
    context.clip()
    let background = CGGradient(colorsSpace: space, colors: [color(0x2B2F8F), color(0x1B1D5C), color(0x0E1030)] as CFArray, locations: [0, 0.55, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 160, y: 924), end: CGPoint(x: 860, y: 100), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [color(0x7C5CFF, 0.55), color(0x7C5CFF, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 760), startRadius: 0, endCenter: CGPoint(x: 330, y: 760), endRadius: 520, options: [])
    let rim = CGGradient(colorsSpace: space, colors: [color(0x22D3EE, 0.28), color(0x22D3EE, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(rim, startCenter: CGPoint(x: 820, y: 200), startRadius: 0, endCenter: CGPoint(x: 820, y: 200), endRadius: 460, options: [])
    context.restoreGState()

    context.translateBy(x: -34, y: 0)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x05061A, 0.55))
    context.addPath(bubblePath())
    context.clip()
    let bubble = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xDCE3FF)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(bubble, start: CGPoint(x: 300, y: 680), end: CGPoint(x: 600, y: 260), options: [])
    context.restoreGState()

    let barColor = CGGradient(colorsSpace: space, colors: [color(0x6D5BFF), color(0x2A9DF4)] as CFArray, locations: [0, 1])!
    let bars: [(x: CGFloat, height: CGFloat)] = [(330, 90), (400, 170), (470, 230), (540, 150), (610, 80)]
    for bar in bars {
        let rect = CGRect(x: bar.x - 22, y: 500 - bar.height / 2, width: 44, height: bar.height)
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil))
        context.clip()
        context.drawLinearGradient(barColor, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        context.restoreGState()
    }

    context.setLineCap(.round)
    let center = CGPoint(x: 690, y: 510)
    let waves: [(radius: CGFloat, width: CGFloat, alpha: CGFloat)] = [(64, 32, 0.95), (126, 28, 0.7), (188, 24, 0.45)]
    for wave in waves {
        context.setStrokeColor(color(0x67E8F9, wave.alpha))
        context.setLineWidth(wave.width)
        context.addArc(center: center, radius: wave.radius, startAngle: -.pi / 4.2, endAngle: .pi / 4.2, clockwise: false)
        context.strokePath()
    }
}

func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    let context = graphics.cgContext
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(context)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])
}

let directory = URL(fileURLWithPath: outputDirectory)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for entry in entries {
    guard let data = render(pixels: entry.pixels) else {
        FileHandle.standardError.write(Data("failed to render \(entry.name)\n".utf8))
        exit(1)
    }
    try data.write(to: directory.appending(path: "\(entry.name).png"))
}
print("Wrote \(entries.count) images to \(directory.path)")
