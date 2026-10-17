import SwiftUI

/// Estado vazio / de conexao com a Poppy, sobre `ContentUnavailableView` (nativo).
/// Os botoes so aparecem se o closure correspondente for passado:
/// `primary` = acao principal (ouro), `secondary` = acao neutra.
struct EmptyStateView: View {
    enum Kind: Hashable {
        case allCaughtUp
        case noSessions
        case connecting
        case tailscaleOff
        case accessDenied
        case serverUnreachable

        var mood: PoppyMood {
            switch self {
            case .allCaughtUp: .sleeping
            case .noSessions, .connecting: .waving
            case .tailscaleOff, .serverUnreachable: .lost
            case .accessDenied: .failed
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .allCaughtUp: "Tudo em dia"
            case .noSessions: "Nenhuma sessão ainda"
            case .connecting: "Conectando..."
            case .tailscaleOff: "Tailscale desligado"
            case .accessDenied: "Acesso negado"
            case .serverUnreachable: "Servidor fora do ar"
            }
        }

        var message: LocalizedStringKey {
            switch self {
            case .allCaughtUp: "Nenhum agente precisa de você agora. A Poppy avisa quando algo chegar."
            case .noSessions: "Crie a primeira sessão para abrir um terminal no PC."
            case .connecting: "Falando com o PC pela rede Tailscale."
            case .tailscaleOff: "Ligue o Tailscale para alcançar o PC. Reconecto sozinha quando voltar."
            case .accessDenied: "O servidor recusou a conexão. Confira a senha e o endereço em Ajustes."
            case .serverUnreachable: "O PC não respondeu. Veja se ele está ligado e tente de novo."
            }
        }

        var primaryTitle: LocalizedStringKey {
            switch self {
            case .noSessions: "Nova sessão"
            case .accessDenied: "Abrir Ajustes"
            default: "Tentar de novo"
            }
        }

        var secondaryTitle: LocalizedStringKey {
            switch self {
            case .tailscaleOff: "Abrir Tailscale"
            default: "Ajustes"
            }
        }
    }

    let kind: Kind
    var primary: (() -> Void)?
    var secondary: (() -> Void)?

    init(_ kind: Kind, primary: (() -> Void)? = nil, secondary: (() -> Void)? = nil) {
        self.kind = kind
        self.primary = primary
        self.secondary = secondary
    }

    var body: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                PoppyView(kind.mood, size: 128)
                Text(kind.title)
                    .guildText(.screenTitle)
                    .foregroundStyle(Theme.Palette.text)
            }
        } description: {
            Text(kind.message)
                .foregroundStyle(Theme.Palette.textSecondary)
        } actions: {
            if let primary {
                Button(kind.primaryTitle, action: primary)
                    .buttonStyle(.poppyProminent)
            }
            if let secondary {
                Button(kind.secondaryTitle, action: secondary)
                    .buttonStyle(.poppyNeutral)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Botao de acao Guild: min. 44 pt, canto reto, moldura em camadas. `prominent` = ouro com bisel e texto
/// escuro (9,2:1); `neutral` = fundo surface1 com borda bronze. Rotulo em letra de pixel (decisao do Gobby),
/// que volta para SF em tamanhos de acessibilidade e na paisagem compacta.
struct PoppyActionStyle: ButtonStyle {
    enum Role { case prominent, neutral }
    let role: Role
    @Environment(\.isEnabled) private var isEnabled

    private var frameKind: GuildFrameKind {
        role == .prominent && isEnabled ? .button : .neutralButton
    }

    /// Desabilitado: o prominent vira o neutro com texto secundario (nao some).
    private var textColor: Color {
        if !isEnabled { return Theme.Palette.textSecondary }
        return role == .prominent ? Theme.Palette.onAccent : Theme.Palette.text
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .guildText(.button)
            .foregroundStyle(textColor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280, minHeight: 44)
            .padding(.horizontal, 16)
            .guildFrame(frameKind, pressed: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PoppyActionStyle {
    static var poppyProminent: PoppyActionStyle { PoppyActionStyle(role: .prominent) }
    static var poppyNeutral: PoppyActionStyle { PoppyActionStyle(role: .neutral) }
}

#Preview("EmptyStateView") {
    EmptyStateView(.tailscaleOff, primary: {}, secondary: {})
        .background(Theme.Palette.base)
        .preferredColorScheme(.dark)
}
