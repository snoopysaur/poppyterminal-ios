import SwiftUI

/// Tipos de moldura Guild: cantos retos, camadas de traco reto, sem sombra, desfoque nem material.
/// Camadas (de fora para dentro): 1 pt escuro (crust) + 2 pt do meio (ouro velho ou cor do estado)
/// + 1 pt interno bronze. A cor vem sempre dos tokens.
enum GuildFrameKind: Equatable, Sendable {
    case panel          // painel normal
    case alert          // precisa de voce (pessego)
    case danger         // risco/erro (vermelho)
    case seal           // selo escuro quadrado
    case button         // botao principal (ouro, com bisel)
    case neutralButton  // botao neutro
}

/// Fundo emoldurado. Decorativo: fica escondido do VoiceOver e nao recebe toque.
struct GuildFrameBackground: View {
    let kind: GuildFrameKind
    var pressed = false
    var tone: Color?

    @Environment(\.colorSchemeContrast) var contrast

    private var fill: Color {
        switch kind {
        case .panel: Theme.Palette.surface
        case .alert: Theme.Palette.tintAlert
        case .danger: Theme.Palette.tintDanger
        case .seal: Theme.Palette.seal
        case .button: Theme.Palette.accent
        case .neutralButton: Theme.Palette.surfaceStrong
        }
    }

    private var middle: Color {
        switch kind {
        case .panel, .seal, .button: tone ?? Theme.Palette.borderStrong
        case .alert: tone ?? Color(uiColor: Theme.peach)
        case .danger: tone ?? Color(uiColor: Theme.red)
        case .neutralButton: tone ?? Theme.Palette.border
        }
    }

    private var hasInner: Bool {
        switch kind {
        case .panel, .alert, .danger, .seal: true
        case .button, .neutralButton: false
        }
    }

    private var middleWidth: CGFloat { contrast == .increased ? 3 : 2 }

    var body: some View {
        ZStack {
            Rectangle().fill(fill)
            Rectangle().strokeBorder(Theme.Palette.sunken, lineWidth: 1)
            Rectangle().strokeBorder(middle, lineWidth: middleWidth).padding(1)
            if hasInner {
                Rectangle().strokeBorder(Theme.Palette.border, lineWidth: 1).padding(1 + middleWidth)
            }
            if kind == .button {
                // bisel: faixa escura embaixo
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle().fill(Theme.Palette.borderStrong).frame(height: 3)
                }
                .padding(.horizontal, 1 + middleWidth)
                .padding(.bottom, 1 + middleWidth)
            }
            if pressed { Rectangle().fill(Theme.Palette.sunken.opacity(0.25)) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Poe a moldura Guild no fundo. Quem usa deve dar o recuo interno (>= 6 pt).
    func guildFrame(_ kind: GuildFrameKind, pressed: Bool = false, tone: Color? = nil) -> some View {
        background(GuildFrameBackground(kind: kind, pressed: pressed, tone: tone))
    }
}

#Preview("GuildFrame") {
    VStack(spacing: 16) {
        ForEach(Array([GuildFrameKind.panel, .alert, .danger, .seal, .button, .neutralButton].enumerated()), id: \.offset) { _, kind in
            Text(kind.previewName)
                .foregroundStyle(kind == .button ? Theme.Palette.onAccent : Theme.Palette.text)
                .padding(12)
                .frame(maxWidth: .infinity)
                .guildFrame(kind)
        }
    }
    .padding()
    .background(Theme.Palette.base)
    .preferredColorScheme(.dark)
}

private extension GuildFrameKind {
    var previewName: String {
        switch self {
        case .panel: "painel"
        case .alert: "alerta"
        case .danger: "perigo"
        case .seal: "selo"
        case .button: "botao"
        case .neutralButton: "botao neutro"
        }
    }
}
