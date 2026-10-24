import AppKit
import SwiftUI

@MainActor
public enum Snapshot {
    public static func png(of view: NSView) -> Data? {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0, let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    public static func png(of window: NSWindow) -> Data? {
        guard let view = window.contentView?.superview ?? window.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0, let layer = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: layer)
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: layer.pixelsWide, pixelsHigh: layer.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        canvas.size = bounds.size
        guard let context = NSGraphicsContext(bitmapImageRep: canvas) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        (window.effectiveAppearance).performAsCurrentDrawingAppearance {
            window.backgroundColor.setFill()
            NSRect(origin: .zero, size: bounds.size).fill()
        }
        layer.draw(in: NSRect(origin: .zero, size: bounds.size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        return canvas.representation(using: .png, properties: [:])
    }

    public static func png<Content: View>(_ content: Content, size: CGSize) -> Data? {
        let host = NSHostingView(rootView: content.preferredColorScheme(.dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return png(of: host)
    }

    public static func write(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path), attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
