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
        png(of: window, overlays: [], overlayFill: .clear)
    }

    public static func png(of window: NSWindow, overlays: [NSWindow], overlayFill: NSColor) -> Data? {
        guard let view = window.contentView?.superview ?? window.contentView, let layer = cachedDisplay(of: view) else { return nil }
        let bounds = view.bounds
        let placed = overlays.compactMap { overlay in overlayContent(overlay, over: window) }
        let area = placed.reduce(NSRect(origin: .zero, size: bounds.size)) { $0.union($1.rect) }
        let scale = CGFloat(layer.pixelsWide) / max(bounds.width, 1)
        guard let canvas = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(area.width * scale), pixelsHigh: Int(area.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        canvas.size = area.size
        guard let context = NSGraphicsContext(bitmapImageRep: canvas) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let base = NSRect(origin: NSPoint(x: -area.minX, y: -area.minY), size: bounds.size)
        (window.effectiveAppearance).performAsCurrentDrawingAppearance {
            window.backgroundColor.setFill()
            base.fill()
        }
        layer.draw(in: base, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        for (rect, rep) in placed {
            let target = rect.offsetBy(dx: -area.minX, dy: -area.minY)
            overlayFill.setFill()
            NSBezierPath(roundedRect: target, xRadius: 10, yRadius: 10).fill()
            rep.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        return canvas.representation(using: .png, properties: [:])
    }

    static func cachedDisplay(of view: NSView) -> NSBitmapImageRep? {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0, let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    static func overlayContent(_ overlay: NSWindow, over window: NSWindow) -> (rect: NSRect, rep: NSBitmapImageRep)? {
        guard let view = overlay.contentView, let rep = cachedDisplay(of: view) else { return nil }
        let screen = overlay.convertToScreen(view.convert(view.bounds, to: nil))
        let rect = NSRect(x: screen.minX - window.frame.minX, y: screen.minY - window.frame.minY, width: screen.width, height: screen.height)
        return (rect, rep)
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
