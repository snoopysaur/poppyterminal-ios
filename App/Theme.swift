import SwiftUI
import UIKit

/// Paleta Catppuccin Mocha (MIT). Todas as cores do app vem daqui.
enum Theme {
    static let rosewater = hex(0xF5E0DC)
    static let flamingo  = hex(0xF2CDCD)
    static let pink      = hex(0xF5C2E7)
    static let mauve     = hex(0xCBA6F7)
    static let red       = hex(0xF38BA8)
    static let maroon    = hex(0xEBA0AC)
    static let peach     = hex(0xFAB387)
    static let yellow    = hex(0xF9E2AF)
    static let green     = hex(0xA6E3A1)
    static let teal      = hex(0x94E2D5)
    static let sky       = hex(0x89DCEB)
    static let sapphire  = hex(0x74C7EC)
    static let blue      = hex(0x89B4FA)
    static let lavender  = hex(0xB4BEFE)
    static let text      = hex(0xCDD6F4)
    static let subtext1  = hex(0xBAC2DE)
    static let subtext0  = hex(0xA6ADC8)
    static let overlay2  = hex(0x9399B2)
    static let overlay1  = hex(0x7F849C)
    static let overlay0  = hex(0x6C7086)
    static let surface2  = hex(0x585B70)
    static let surface1  = hex(0x45475A)
    static let surface0  = hex(0x313244)
    static let base      = hex(0x1E1E2E)
    static let mantle    = hex(0x181825)
    static let crust     = hex(0x11111B)

    // Papeis semanticos
    static let background = base
    static let foreground = text
    static let accent = mauve

    /// Papeis semanticos em SwiftUI `Color` (use estes em views novas).
    /// Contrastes sobre `base`: text 11,3 / subtext0 7,4 / mauve 8,1; sobre `surface`: text 8,7 / subtext0 5,7.
    /// Nunca use `subtext0` sobre `surfaceStrong` (4,1) nem `overlay1` como cor de texto (4,4 na base).
    enum Palette {
        static let base          = Color(uiColor: Theme.base)      // fundo de tela
        static let surface       = Color(uiColor: Theme.surface0)  // cartoes, listas
        static let surfaceStrong = Color(uiColor: Theme.surface1)  // divisores, botao neutro
        static let sunken        = Color(uiColor: Theme.crust)     // terminal, blocos de comando
        static let text          = Color(uiColor: Theme.text)
        static let textSecondary = Color(uiColor: Theme.subtext0)
        static let accent        = Color(uiColor: Theme.mauve)     // acento unico
        static let onAccent      = Color(uiColor: Theme.crust)     // texto sobre o acento (9,2)
    }

    static let fontRegular = "JetBrainsMonoNFM-Regular"

    static func terminalFont(size: CGFloat) -> UIFont {
        UIFont(name: fontRegular, size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func hex(_ rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
