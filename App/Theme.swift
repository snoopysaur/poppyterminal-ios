import SwiftUI
import UIKit

/// Cores e fonte do app. Os valores vem de `ThemeTokens` (gerado de `design/tokens.json`);
/// aqui so ficam os NOMES de papel. Tema ativo: Guild (acento = ouro).
/// Contrastes (Guild): text sobre base 14,5 / sobre surface 12,8; textSecondary sobre base 9,0 / surface 7,9;
/// onAccent sobre accent 9,2. `idle` e so para icone/contorno (4,4 sobre base), nunca texto.
enum Theme {
    // Papeis de superficie e texto
    static let base      = hex(ThemeTokens.base)
    static let mantle    = hex(ThemeTokens.mantle)
    static let crust     = hex(ThemeTokens.crust)
    static let surface0  = hex(ThemeTokens.surface)
    static let surface1  = hex(ThemeTokens.surfaceStrong)
    static let text      = hex(ThemeTokens.text)
    static let subtext0  = hex(ThemeTokens.textSecondary)
    static let accent    = hex(ThemeTokens.accent)
    static let onAccent  = hex(ThemeTokens.onAccent)
    static let border       = hex(ThemeTokens.border)
    static let borderStrong = hex(ThemeTokens.borderStrong)

    // Estados (tabela unica)
    static let peach     = hex(ThemeTokens.peach)
    static let red       = hex(ThemeTokens.red)
    static let blue      = hex(ThemeTokens.blue)
    static let green     = hex(ThemeTokens.green)
    static let lavender  = hex(ThemeTokens.lavender)
    static let overlay1  = hex(ThemeTokens.idle)      // ocioso: so icone/contorno
    static let overlay0  = hex(ThemeTokens.gameMode)  // modo jogo (mesa)

    // Derivados (cor misturada sobre o cartao, ja calculada pelo gerador)
    static let tintAlert  = hex(ThemeTokens.tintAlert)
    static let tintDanger = hex(ThemeTokens.tintDanger)
    static let riskBlock  = hex(ThemeTokens.riskBlock)
    static let riskButton = hex(ThemeTokens.riskButton)
    static let seal       = hex(ThemeTokens.seal)
    static let onBadge    = hex(ThemeTokens.onBadge)
    static let terminalSelection = hex(ThemeTokens.terminalSelection)

    /// As 16 cores do terminal (0-7 normais, 8-15 brilhantes).
    static let terminalAnsi: [UIColor] = ThemeTokens.terminalAnsi.map { Theme.hex($0) }

    // Papeis semanticos
    static let background = base
    static let foreground = text

    /// Papeis semanticos em SwiftUI `Color` (use estes em views novas).
    /// Nunca use `idle` como cor de texto. Cor so por estes papeis: nada de `Color(red:)` em tela.
    enum Palette {
        static let base          = Color(uiColor: Theme.base)      // fundo de tela
        static let mantle        = Color(uiColor: Theme.mantle)    // barras
        static let surface       = Color(uiColor: Theme.surface0)  // cartoes, listas
        static let surfaceStrong = Color(uiColor: Theme.surface1)  // divisores, botao neutro
        static let sunken        = Color(uiColor: Theme.crust)     // terminal, blocos de comando, selo
        static let text          = Color(uiColor: Theme.text)
        static let textSecondary = Color(uiColor: Theme.subtext0)
        static let accent        = Color(uiColor: Theme.accent)    // acento unico (ouro)
        static let onAccent      = Color(uiColor: Theme.onAccent)  // texto sobre o acento
        static let border        = Color(uiColor: Theme.border)    // moldura interna (bronze)
        static let borderStrong  = Color(uiColor: Theme.borderStrong) // moldura externa (ouro velho)
        static let tintAlert     = Color(uiColor: Theme.tintAlert)
        static let tintDanger    = Color(uiColor: Theme.tintDanger)
        static let riskBlock     = Color(uiColor: Theme.riskBlock)
        static let riskButton    = Color(uiColor: Theme.riskButton)
        static let seal          = Color(uiColor: Theme.seal)
        static let onBadge       = Color(uiColor: Theme.onBadge)   // texto escuro sobre o contador vermelho
    }

    static let fontRegular = "JetBrainsMonoNFM-Regular"

    static func terminalFont(size: CGFloat) -> UIFont {
        UIFont(name: fontRegular, size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func hex(_ rgb: UInt32) -> UIColor {
        UIColor(cgColor: CGColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        ))
    }
}
