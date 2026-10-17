// GERADO por scripts/gen_theme.py a partir de design/tokens.json. NAO EDITE A MAO.
// Para mudar uma cor: edite design/tokens.json e rode `python -I scripts/gen_theme.py`.

/// Guild (identidade C)
enum ThemeTokensGuild {
    static let base: UInt32 = 0x1B1612
    static let mantle: UInt32 = 0x15110D
    static let crust: UInt32 = 0x0E0B08
    static let surface: UInt32 = 0x2A2119
    static let surfaceStrong: UInt32 = 0x3A2D20
    static let text: UInt32 = 0xF3E6CC
    static let textSecondary: UInt32 = 0xC7B596
    static let accent: UInt32 = 0xE8B04A
    static let onAccent: UInt32 = 0x1B1612
    static let border: UInt32 = 0x9A6B2F
    static let borderStrong: UInt32 = 0xC8923F
    static let peach: UInt32 = 0xF29A4B
    static let red: UInt32 = 0xE5575B
    static let blue: UInt32 = 0x7FB2E5
    static let green: UInt32 = 0x93C96B
    static let lavender: UInt32 = 0xBBA9E8
    static let idle: UInt32 = 0x8C7B66
    static let gameMode: UInt32 = 0x6E604F
    static let tintAlert: UInt32 = 0x463220
    static let tintDanger: UInt32 = 0x442922
    static let riskBlock: UInt32 = 0x482A24
    static let riskButton: UInt32 = 0x532D28
    static let seal: UInt32 = 0x0E0B08
    static let onBadge: UInt32 = 0x0E0B08
    static let terminalSelection: UInt32 = 0x4F3C1C
    static let terminalAnsi: [UInt32] = [0x3A2D20, 0xE5575B, 0x93C96B, 0xE8B04A, 0x7FB2E5, 0xD08FD0, 0x6FC7B5, 0xE0D2B4, 0x8C7B66, 0xE87B77, 0xABD083, 0xEBBE6A, 0x9CBFDF, 0xD9A5CF, 0x90CFBB, 0xE5D7BA]
}

/// Catppuccin Mocha (reserva, identidade A)
enum ThemeTokensMocha {
    static let base: UInt32 = 0x1E1E2E
    static let mantle: UInt32 = 0x181825
    static let crust: UInt32 = 0x11111B
    static let surface: UInt32 = 0x313244
    static let surfaceStrong: UInt32 = 0x45475A
    static let text: UInt32 = 0xCDD6F4
    static let textSecondary: UInt32 = 0xA6ADC8
    static let accent: UInt32 = 0xCBA6F7
    static let onAccent: UInt32 = 0x11111B
    static let border: UInt32 = 0x45475A
    static let borderStrong: UInt32 = 0x585B70
    static let peach: UInt32 = 0xFAB387
    static let red: UInt32 = 0xF38BA8
    static let blue: UInt32 = 0x89B4FA
    static let green: UInt32 = 0xA6E3A1
    static let lavender: UInt32 = 0xB4BEFE
    static let idle: UInt32 = 0x7F849C
    static let gameMode: UInt32 = 0x6C7086
    static let tintAlert: UInt32 = 0x4D444D
    static let tintDanger: UInt32 = 0x4C3E52
    static let riskBlock: UInt32 = 0x504054
    static let riskButton: UInt32 = 0x5C465A
    static let seal: UInt32 = 0x11111B
    static let onBadge: UInt32 = 0x11111B
    static let terminalSelection: UInt32 = 0x493E5D
    static let terminalAnsi: [UInt32] = [0x45475A, 0xF38BA8, 0xA6E3A1, 0xF9E2AF, 0x89B4FA, 0xF5C2E7, 0x94E2D5, 0xBAC2DE, 0x7F849C, 0xEA9EBB, 0xB0E0B6, 0xEEDFC0, 0x9ABCF8, 0xEBC7EA, 0xA2DFDD, 0xBFC7E4]
}

/// Tema ativo do app.
typealias ThemeTokens = ThemeTokensGuild
