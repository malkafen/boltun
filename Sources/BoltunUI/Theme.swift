import SwiftUI

public enum Theme {
    public static let serverRail = Color(red: 0.07, green: 0.08, blue: 0.10)
    public static let sidebar = Color(red: 0.11, green: 0.12, blue: 0.15)
    public static let sidebarSelected = Color(red: 0.20, green: 0.38, blue: 0.70)
    public static let sidebarText = Color.white.opacity(0.72)
    public static let sidebarTextUnread = Color.white
    public static let content = Color(red: 0.13, green: 0.14, blue: 0.17)
    public static let contentElevated = Color(red: 0.17, green: 0.18, blue: 0.22)
    public static let separator = Color.white.opacity(0.08)
    public static let textPrimary = Color.white.opacity(0.92)
    public static let textSecondary = Color.white.opacity(0.56)
    public static let accent = Color(red: 0.33, green: 0.56, blue: 0.95)
    public static let mention = Color(red: 0.95, green: 0.30, blue: 0.30)
    public static let mentionHighlight = Color(red: 0.98, green: 0.80, blue: 0.30).opacity(0.18)
    public static let codeBackground = Color.white.opacity(0.06)
    public static let inlineCodeBackground = Color.white.opacity(0.11)
    public static let inlineCodeText = Color(red: 0.93, green: 0.62, blue: 0.58)
    public static let online = Color(red: 0.24, green: 0.72, blue: 0.40)
    public static let away = Color(red: 1.0, green: 0.74, blue: 0.20)
    public static let dnd = Color(red: 0.86, green: 0.25, blue: 0.25)
}

extension Theme {
    public static let railTile = Color(red: 0.19, green: 0.20, blue: 0.24)
    public static let railTileSelected = Color(red: 0.27, green: 0.45, blue: 0.78)
    public static let sidebarHeader = Color(red: 0.12, green: 0.13, blue: 0.16)
    public static let sidebarHover = Color.white.opacity(0.06)
    public static let sidebarActive = Color.white.opacity(0.11)
    public static let sidebarSectionTitle = Color.white.opacity(0.52)
    public static let hover = Color.white.opacity(0.035)
    public static let border = Color.white.opacity(0.12)
    public static let inputBackground = Color(red: 0.10, green: 0.11, blue: 0.13)
    public static let newMessages = Color(red: 0.94, green: 0.40, blue: 0.34)
    public static let toastHistory = Color(red: 0.85, green: 0.85, blue: 0.85)
    public static let toastHistoryText = Color(red: 0.24, green: 0.24, blue: 0.25)
    public static let link = Color(red: 0.42, green: 0.62, blue: 1.0)
    public static let linkHover = Color(red: 0.42, green: 0.62, blue: 1.0).opacity(0.16)
    public static let mentionBadge = Color(red: 0.86, green: 0.27, blue: 0.29)
    public static let reactionBackground = Color.white.opacity(0.06)
    public static let reactionMine = Color(red: 0.33, green: 0.56, blue: 0.95).opacity(0.22)
    public static let reactionMineBorder = Color(red: 0.33, green: 0.56, blue: 0.95).opacity(0.75)
    public static let quoteBar = Color.white.opacity(0.24)
    public static let offline = Color.white.opacity(0.38)
    public static let warning = Color(red: 0.95, green: 0.62, blue: 0.20)
    public static let errorBanner = Color(red: 0.62, green: 0.18, blue: 0.20)
    public static let warningBanner = Color(red: 0.50, green: 0.36, blue: 0.10)
    public static let overlayDim = Color.black.opacity(0.45)
    public static let popover = Color(red: 0.16, green: 0.17, blue: 0.21)
    public static let mentionRow = Color(red: 0.98, green: 0.80, blue: 0.30).opacity(0.07)
    public static let mentionRowHover = Color(red: 0.98, green: 0.80, blue: 0.30).opacity(0.11)
    public static let mentionRowBar = Color(red: 0.98, green: 0.78, blue: 0.30).opacity(0.75)
    public static let postHighlight = Color(red: 0.98, green: 0.80, blue: 0.30).opacity(0.22)
    public static let editingHighlight = Color(red: 0.95, green: 0.70, blue: 0.25).opacity(0.10)
    public static let avatarPalette: [Color] = [
        Color(red: 0.36, green: 0.53, blue: 0.86),
        Color(red: 0.55, green: 0.41, blue: 0.80),
        Color(red: 0.20, green: 0.62, blue: 0.55),
        Color(red: 0.82, green: 0.47, blue: 0.27),
        Color(red: 0.75, green: 0.33, blue: 0.48),
        Color(red: 0.42, green: 0.60, blue: 0.30),
    ]

    public static func messageFont(scale: Double = 1) -> Font { .system(size: 13.5 * scale) }
    public static func codeFont(scale: Double = 1) -> Font { .system(size: 12.5 * scale, design: .monospaced) }
}
