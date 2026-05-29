import AppKit

/// A terminal cell color: default, a 0–255 palette index, or 24-bit truecolor.
enum TermColor: Equatable {
    case defaultFg
    case defaultBg
    case indexed(Int)
    case rgb(UInt8, UInt8, UInt8)
}

struct CellAttrs: OptionSet {
    let rawValue: UInt8
    static let bold      = CellAttrs(rawValue: 1 << 0)
    static let dim       = CellAttrs(rawValue: 1 << 1)
    static let italic    = CellAttrs(rawValue: 1 << 2)
    static let underline = CellAttrs(rawValue: 1 << 3)
    static let inverse   = CellAttrs(rawValue: 1 << 4)
}

struct Cell {
    var scalar: UnicodeScalar = " "
    var fg: TermColor = .defaultFg
    var bg: TermColor = .defaultBg
    var attrs: CellAttrs = []
}

/// xterm 256-color palette + default fg/bg, resolved to NSColor.
enum TerminalPalette {
    static let defaultForeground = NSColor(hex: 0xD4D4D4)
    static let defaultBackground = NSColor(hex: 0x1E1E1E)
    static let cursor            = NSColor(hex: 0xAEAFAD)

    /// 256-entry table: 16 ANSI + 6×6×6 cube + 24 grays.
    static let table: [NSColor] = {
        var colors: [NSColor] = []

        // 0–15: standard ANSI (xterm defaults).
        let base: [UInt32] = [
            0x000000, 0xCD3131, 0x0DBC79, 0xE5E510, 0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
            0x666666, 0xF14C4C, 0x23D18B, 0xF5F543, 0x3B8EEA, 0xD670D6, 0x29B8DB, 0xFFFFFF,
        ]
        for hex in base { colors.append(NSColor(hex: hex)) }

        // 16–231: 6×6×6 color cube.
        let levels: [Int] = [0, 95, 135, 175, 215, 255]
        for r in 0..<6 {
            for g in 0..<6 {
                for b in 0..<6 {
                    colors.append(NSColor(srgbRed: CGFloat(levels[r]) / 255,
                                          green: CGFloat(levels[g]) / 255,
                                          blue: CGFloat(levels[b]) / 255, alpha: 1))
                }
            }
        }

        // 232–255: grayscale ramp.
        for i in 0..<24 {
            let v = CGFloat(8 + i * 10) / 255
            colors.append(NSColor(srgbRed: v, green: v, blue: v, alpha: 1))
        }
        return colors
    }()

    static func resolve(_ color: TermColor, attrs: CellAttrs, isForeground: Bool) -> NSColor {
        switch color {
        case .defaultFg: return defaultForeground
        case .defaultBg: return defaultBackground
        case .rgb(let r, let g, let b):
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        case .indexed(let i):
            // Bold often brightens the low 8 ANSI colors.
            var idx = i
            if isForeground, attrs.contains(.bold), idx < 8 { idx += 8 }
            return table[min(max(idx, 0), 255)]
        }
    }
}
