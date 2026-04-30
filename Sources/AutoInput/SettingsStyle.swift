import AppKit

@MainActor
enum SettingsStyle {
    static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static var background: NSColor {
        isDark
            ? NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1)
            : NSColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    }

    static var card: NSColor {
        isDark
            ? NSColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1)
            : NSColor.white.withAlphaComponent(0.96)
    }

    static var row: NSColor {
        isDark
            ? NSColor(red: 0.19, green: 0.20, blue: 0.22, alpha: 1)
            : NSColor(white: 0.97, alpha: 1)
    }

    static var rowSelected: NSColor {
        isDark
            ? NSColor.controlAccentColor.withAlphaComponent(0.22)
            : NSColor.controlAccentColor.withAlphaComponent(0.12)
    }

    static var field: NSColor {
        isDark
            ? NSColor(red: 0.19, green: 0.20, blue: 0.22, alpha: 1)
            : NSColor.white
    }

    static var stroke: NSColor {
        isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.10)
    }

    static let selectedStroke = NSColor.controlAccentColor.withAlphaComponent(0.70)
    static var text: NSColor { NSColor.labelColor }
    static var secondaryText: NSColor { NSColor.secondaryLabelColor }
    static var tertiaryText: NSColor { NSColor.tertiaryLabelColor }

    static var emptyIcon: NSColor {
        isDark ? NSColor(white: 0.66, alpha: 1) : NSColor(white: 0.42, alpha: 1)
    }

    static var emptyText: NSColor {
        isDark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.16, alpha: 1)
    }

    static var emptySecondaryText: NSColor {
        isDark ? NSColor(white: 0.66, alpha: 1) : NSColor(white: 0.46, alpha: 1)
    }

    static var pickerBackground: NSColor {
        isDark
            ? NSColor(red: 0.14, green: 0.15, blue: 0.18, alpha: 1)
            : NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
    }

    static var pickerText: NSColor {
        isDark ? NSColor(white: 0.94, alpha: 1) : NSColor(white: 0.14, alpha: 1)
    }

    static var pickerSecondaryText: NSColor {
        isDark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.46, alpha: 1)
    }

    static var runningRowText: NSColor {
        isDark ? NSColor(white: 0.94, alpha: 1) : NSColor(white: 0.12, alpha: 1)
    }
}
