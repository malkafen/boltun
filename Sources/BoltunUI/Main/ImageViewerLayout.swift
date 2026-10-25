import AppKit
import BoltunKit
import Foundation

struct ImageViewerDisplay: Equatable, Sendable {
    var size: CGSize
    var scale: CGFloat

    static let fallback = ImageViewerDisplay(size: CGSize(width: 1440, height: 900), scale: 2)

    @MainActor
    static func of(_ screen: NSScreen?) -> ImageViewerDisplay {
        guard let screen else { return fallback }
        return ImageViewerDisplay(size: screen.frame.size, scale: screen.backingScaleFactor)
    }
}

enum ImageViewerLayout {
    static let screenFraction: CGFloat = 0.9
    static let headerHeight: CGFloat = 46
    static let minimumContent = CGSize(width: 520, height: 360)
    static let fallbackContent = CGSize(width: 900, height: 700)
    static let maximumDecodePixel: CGFloat = 8192
    static let upgradeTolerance: CGFloat = 1.05

    static func available(visible: CGSize, titlebar: CGFloat, fraction: CGFloat = screenFraction) -> CGSize {
        CGSize(width: max(0, visible.width * fraction), height: max(0, visible.height * fraction - titlebar))
    }

    static func contentSize(image: CGSize, available: CGSize, header: CGFloat = headerHeight, minimum: CGSize = minimumContent) -> CGSize {
        let floor = CGSize(width: min(minimum.width, available.width), height: min(minimum.height, available.height))
        guard image.width > 0, image.height > 0 else {
            return CGSize(width: max(floor.width, min(fallbackContent.width, available.width)), height: max(floor.height, min(fallbackContent.height, available.height)))
        }
        let room = CGSize(width: available.width, height: max(1, available.height - header))
        let scale = min(1, room.width / image.width, room.height / image.height)
        let fitted = CGSize(width: (image.width * scale).rounded(), height: (image.height * scale).rounded())
        return CGSize(width: max(floor.width, fitted.width), height: max(floor.height, fitted.height + header))
    }

    static func centered(size: CGSize, in visible: CGRect) -> CGRect {
        CGRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    static func decodePixel(image: CGSize, display: ImageViewerDisplay) -> CGFloat {
        let screen = CGSize(width: display.size.width * display.scale, height: display.size.height * display.scale)
        guard image.width > 0, image.height > 0 else { return min(maximumDecodePixel, max(screen.width, screen.height)).rounded(.up) }
        let scale = min(1, screen.width / image.width, screen.height / image.height)
        return min(maximumDecodePixel, (max(image.width, image.height) * scale).rounded(.up))
    }

    static func upgradePixel(magnification: CGFloat, document: CGSize, scale: CGFloat, decoded: CGFloat, original: CGFloat) -> CGFloat? {
        let ceiling = min(original, maximumDecodePixel)
        guard decoded > 0, decoded < ceiling else { return nil }
        let needed = max(document.width, document.height) * magnification * scale
        guard needed > decoded * upgradeTolerance else { return nil }
        return ceiling
    }
}

enum ImageZoomCommand: Equatable {
    case zoomIn
    case zoomOut
    case fit
    case actualSize
    case toggle
}

enum ImageZoomTarget: Equatable {
    case fit
    case scale(CGFloat)
}

struct ImageZoomState: Equatable {
    var magnification: CGFloat = 1
    var fit: CGFloat = 1
    var isFitting = true

    var limits: ClosedRange<CGFloat> { ImageZoom.limits(fit: fit) }
    var canZoomIn: Bool { magnification < limits.upperBound - ImageZoom.epsilon }
    var canZoomOut: Bool { magnification > limits.lowerBound + ImageZoom.epsilon }
    var percent: String { ImageZoom.percent(magnification) }
}

enum ImageZoom {
    static let epsilon: CGFloat = 0.001
    static let maximum: CGFloat = 8
    static let minimumFloor: CGFloat = 0.25
    static let steps: [CGFloat] = [0.05, 0.1, 0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

    static func fit(document: CGSize, viewport: CGSize) -> CGFloat {
        guard document.width > 0, document.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        return min(1, viewport.width / document.width, viewport.height / document.height)
    }

    static func limits(fit: CGFloat) -> ClosedRange<CGFloat> {
        let lower = max(0.01, min(fit, minimumFloor))
        return lower...max(lower, maximum)
    }

    static func clamp(_ value: CGFloat, to limits: ClosedRange<CGFloat>) -> CGFloat {
        min(limits.upperBound, max(limits.lowerBound, value))
    }

    static func zoomIn(from current: CGFloat, limits: ClosedRange<CGFloat>) -> CGFloat {
        let next = steps.first { $0 > current * (1 + epsilon) } ?? limits.upperBound
        return clamp(next, to: limits)
    }

    static func zoomOut(from current: CGFloat, limits: ClosedRange<CGFloat>) -> CGFloat {
        let previous = steps.last { $0 < current * (1 - epsilon) } ?? limits.lowerBound
        return clamp(previous, to: limits)
    }

    static func scrolled(from current: CGFloat, delta: CGFloat, precise: Bool, limits: ClosedRange<CGFloat>) -> CGFloat {
        let sensitivity: CGFloat = precise ? 0.01 : 0.1
        return clamp(current * exp(delta * sensitivity), to: limits)
    }

    static func target(for command: ImageZoomCommand, state: ImageZoomState) -> ImageZoomTarget {
        switch command {
        case .zoomIn: return .scale(zoomIn(from: state.magnification, limits: state.limits))
        case .zoomOut: return .scale(zoomOut(from: state.magnification, limits: state.limits))
        case .fit: return .fit
        case .actualSize: return .scale(1)
        case .toggle: return state.isFitting ? .scale(1) : .fit
        }
    }

    static func isFit(_ magnification: CGFloat, fit: CGFloat) -> Bool {
        abs(magnification - fit) < epsilon
    }

    static func percent(_ magnification: CGFloat) -> String {
        "\(Int((magnification * 100).rounded()))%"
    }
}

enum ImageCanvasGeometry {
    static func centered(bounds: CGRect, document: CGSize) -> CGRect {
        var rect = bounds
        if rect.width > document.width { rect.origin.x = ((document.width - rect.width) / 2).rounded() }
        if rect.height > document.height { rect.origin.y = ((document.height - rect.height) / 2).rounded() }
        return rect
    }

    static func panned(origin: CGPoint, delta: CGSize, magnification: CGFloat, flipped: Bool) -> CGPoint {
        let scale = max(magnification, ImageZoom.epsilon)
        return CGPoint(x: origin.x - delta.width / scale, y: origin.y + (flipped ? -delta.height : delta.height) / scale)
    }

    static func canPan(document: CGSize, magnification: CGFloat, viewport: CGSize) -> Bool {
        document.width * magnification > viewport.width + 0.5 || document.height * magnification > viewport.height + 0.5
    }
}

enum ImageGallery {
    static func images(_ files: [FileInfo]) -> [FileInfo] {
        files.filter { $0.isImage && $0.kind != .svg }
    }

    static func normalized(_ gallery: [FileInfo], selecting file: FileInfo) -> [FileInfo] {
        gallery.contains { $0.id == file.id } ? gallery : [file]
    }

    static func index(of file: FileInfo, in gallery: [FileInfo]) -> Int {
        gallery.firstIndex { $0.id == file.id } ?? 0
    }

    static func index(from current: Int, offset: Int, count: Int) -> Int? {
        let target = current + offset
        guard offset != 0, (0..<count).contains(target) else { return nil }
        return target
    }

    static func position(index: Int, count: Int) -> String? {
        count > 1 ? "\(index + 1) of \(count)" : nil
    }
}

enum ImageViewerAction: Equatable {
    case close
    case zoom(ImageZoomCommand)
    case navigate(Int)
    case copy
    case download
}

enum ImageViewerKey {
    static let escape: UInt16 = 53
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124

    static func action(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) -> ImageViewerAction? {
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        if flags.isEmpty {
            switch keyCode {
            case escape: return .close
            case leftArrow: return .navigate(-1)
            case rightArrow: return .navigate(1)
            default: return nil
            }
        }
        guard flags.subtracting(.shift) == .command else { return nil }
        switch characters.lowercased() {
        case "w": return .close
        case "=", "+": return .zoom(.zoomIn)
        case "-", "_": return .zoom(.zoomOut)
        case "0": return .zoom(.fit)
        case "1": return .zoom(.actualSize)
        case "c": return flags == .command ? .copy : nil
        case "s": return flags == .command ? .download : nil
        default: return nil
        }
    }
}

enum ImageViewerFormat {
    static func dimensions(_ size: CGSize) -> String? {
        guard size.width > 0, size.height > 0 else { return nil }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    static func details(file: FileInfo, pixelSize: CGSize) -> String {
        [file.size > 0 ? FileSizeText.text(file.size) : nil, dimensions(pixelSize)].compactMap(\.self).joined(separator: " · ")
    }
}
