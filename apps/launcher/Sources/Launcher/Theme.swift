import AppKit
import Foundation
import SwiftUI

/// Visual tokens for the launcher panel. Defaults mirror Catppuccin Macchiato.
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
    var selectionBackground: String
    var selectionText: String

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
        case selectionBackground = "selection_background"
        case selectionText = "selection_text"
    }

    /// Catppuccin Macchiato — used when config.json is missing or incomplete.
    static let catppuccinMacchiato = ThemeConfig(
        fontFamily: "SF Pro Text",
        fontSize: 12.5,
        cornerRadius: 12.0,
        borderWidth: 1.5,
        backgroundColor: "#24273a",
        backgroundOpacity: 0.90,
        borderColor: "#b7bdf8",
        textColor: "#cad3f5",
        subtextColor: "#a5adcb",
        selectionBackground: "#363a4f",
        selectionText: "#b7bdf8"
    )
}

struct DimensionsConfig: Codable, Equatable {
    var width: Double
    var maxHeight: Double

    enum CodingKeys: String, CodingKey {
        case width
        case maxHeight = "max_height"
    }

    static let `default` = DimensionsConfig(width: 480, maxHeight: 540)
}

struct BehaviorConfig: Codable, Equatable {
    var hideOnBlur: Bool
    var hotkey: String
    /// Max clipboard-history entries (text + images). Default 100.
    var clipboardMaxItems: Int

    enum CodingKeys: String, CodingKey {
        case hideOnBlur = "hide_on_blur"
        case hotkey
        case clipboardMaxItems = "clipboard_max_items"
    }

    /// Carbon hotkey is opt-in. Rice defaults to skhd (`Alt+R`); set e.g. `cmd+space` for standalone use.
    static let `default` = BehaviorConfig(hideOnBlur: true, hotkey: "off", clipboardMaxItems: 100)

    init(hideOnBlur: Bool, hotkey: String, clipboardMaxItems: Int = 100) {
        self.hideOnBlur = hideOnBlur
        self.hotkey = hotkey
        self.clipboardMaxItems = max(1, clipboardMaxItems)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideOnBlur = try c.decodeIfPresent(Bool.self, forKey: .hideOnBlur) ?? true
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? "off"
        clipboardMaxItems = max(1, try c.decodeIfPresent(Int.self, forKey: .clipboardMaxItems) ?? 100)
    }
}

struct LauncherConfig: Codable, Equatable {
    var theme: ThemeConfig
    var dimensions: DimensionsConfig
    var behavior: BehaviorConfig

    static let `default` = LauncherConfig(
        theme: .catppuccinMacchiato,
        dimensions: .default,
        behavior: .default
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
