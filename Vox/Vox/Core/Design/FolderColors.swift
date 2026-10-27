import SwiftUI
import UIKit

/// Folder colors. Presets come from the scenery; any other color can be picked too.
/// Saved as hex text ("#F7AD52"), so the web app can read it later.
enum FolderPalette {
    struct Preset: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
        var color: Color { Color(hex: hex) ?? .gray }
    }

    static let presets: [Preset] = [
        Preset(name: "Slate", hex: "#94ADD1"),
        Preset(name: "Amber", hex: "#F7AD52"),
        Preset(name: "Sage", hex: "#8CD1B3"),
        Preset(name: "Rose", hex: "#E8919B"),
        Preset(name: "Lavender", hex: "#B4A3E0"),
        Preset(name: "Sky", hex: "#7EC8E3"),
        Preset(name: "Sand", hex: "#D9C3A0"),
        Preset(name: "Stone", hex: "#A6A6AE"),
    ]

    /// Preset for the next new folder, so neighbours get different colors.
    static func preset(after count: Int) -> Preset {
        presets[count % presets.count]
    }
}

extension Color {
    /// Reads "#RRGGBB".
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Writes "#RRGGBB".
    var hex: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

extension Node {
    /// The folder's color, or Slate if none was picked.
    var tint: Color {
        color.flatMap(Color.init(hex:)) ?? FolderPalette.presets[0].color
    }
}
