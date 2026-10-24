import AppKit
import SwiftUI

extension Theme {
    public static let windowBackground = NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1)
    public static let panel = Color(red: 0.15, green: 0.16, blue: 0.20)
    public static let fieldBackground = Color.white.opacity(0.06)
    public static let error = Color(red: 1.0, green: 0.45, blue: 0.45)
    public static let warningBanner = Color(red: 0.55, green: 0.38, blue: 0.10)
    public static let brandGradient = LinearGradient(
        colors: [Color(red: 0.16, green: 0.20, blue: 0.55), Color(red: 0.36, green: 0.22, blue: 0.70)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
