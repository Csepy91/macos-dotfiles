import AppKit
import Foundation
import SwiftUI

/// Visual tokens for the status bar. Defaults mirror Catppuccin Macchiato.
struct ThemeConfig: Codable, Equatable {
    var fontFamily: String
    var fontSize: Double
    var cornerRadius: Double
    var borderWidth: Double
    var backgroundColor: String
    var backgroundOpacity: Double
    var borderColor: String
    var textColor: String
    var subtextColor: String
    var accentColor: String
    var activeWorkspaceBg: String

    enum CodingKeys: String, CodingKey {
        case fontFamily = "font_family"
        case fontSize = "font_size"
        case cornerRadius = "corner_radius"
        case borderWidth = "border_width"
        case backgroundColor = "background_color"
        case backgroundOpacity = "background_opacity"
        case borderColor = "border_color"
        case textColor = "text_color"
        case subtextColor = "subtext_color"
        case accentColor = "accent_color"
        case activeWorkspaceBg = "active_workspace_bg"
    }

    /// Catppuccin Macchiato — used when config.json is missing or incomplete.
    static let catppuccinMacchiato = ThemeConfig(
        fontFamily: "SF Pro Text",
        fontSize: 13.0,
        cornerRadius: 0.0,
        borderWidth: 0.0,
        backgroundColor: "#24273a",
        backgroundOpacity: 0.85,
        borderColor: "#b7bdf8",
        textColor: "#cad3f5",
        subtextColor: "#a5adcb",
        accentColor: "#f5a97f",
        activeWorkspaceBg: "#363a4f"
    )
}

struct DimensionsConfig: Codable, Equatable {
    var height: Double
    var marginTop: Double
    var paddingHorizontal: Double

    enum CodingKeys: String, CodingKey {
        case height
        case marginTop = "margin_top"
        case paddingHorizontal = "padding_horizontal"
    }

    static let `default` = DimensionsConfig(
        height: 38,
        marginTop: 0,
        paddingHorizontal: 12
    )
}

enum WorkspaceDisplayType: String, Codable, Equatable {
    case pills
    case icons
    case dots
}

struct WorkspacesConfig: Codable, Equatable {
    var displayType: WorkspaceDisplayType
    var showEmpty: Bool
    /// When set, only these raw names (e.g. "1"…"9") are shown.
    var filterRawNames: [String]?

    enum CodingKeys: String, CodingKey {
        case displayType = "display_type"
        case showEmpty = "show_empty"
        case filterRawNames = "filter_raw_names"
    }

    static let `default` = WorkspacesConfig(
        displayType: .pills,
        showEmpty: true,
        filterRawNames: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
    )
}

struct BarConfig: Codable, Equatable {
    var theme: ThemeConfig
    var dimensions: DimensionsConfig
    var workspaces: WorkspacesConfig

    static let `default` = BarConfig(
        theme: .catppuccinMacchiato,
        dimensions: .default,
        workspaces: .default
    )
}

// MARK: - Color helpers

extension Color {
    init(hex: String, opacity: Double = 1.0) {
        let parsed = Color.rgba(from: hex)
        self.init(
            .sRGB,
            red: parsed.r,
            green: parsed.g,
            blue: parsed.b,
            opacity: min(max(opacity, 0), 1) * parsed.a
        )
    }

    static func rgba(from hex: String) -> (r: Double, g: Double, b: Double, a: Double) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        switch cleaned.count {
        case 8:
            return (
                Double((value >> 24) & 0xFF) / 255,
                Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255
            )
        case 6:
            return (
                Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255,
                1
            )
        case 3:
            let r = Double((value >> 8) & 0xF) / 15
            let g = Double((value >> 4) & 0xF) / 15
            let b = Double(value & 0xF) / 15
            return (r, g, b, 1)
        default:
            return (0.14, 0.15, 0.23, 1) // Macchiato base fallback
        }
    }
}

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        let parsed = Color.rgba(from: hex)
        self.init(
            srgbRed: parsed.r,
            green: parsed.g,
            blue: parsed.b,
            alpha: min(max(alpha, 0), 1) * CGFloat(parsed.a)
        )
    }
}

extension ThemeConfig {
    var swiftUIFont: Font {
        .custom(fontFamily, size: fontSize)
    }

    var nsFont: NSFont {
        NSFont(name: fontFamily, size: fontSize) ?? .systemFont(ofSize: fontSize)
    }
}
