import SwiftUI
import PoppyKit

/// Cartao no fim da conversa quando o Claude espera uma resposta (aprovacao, plano, pergunta).
/// Tocar abre o sheet de acao da caixa de entrada. O resumo e so para mostrar.
struct PendingPromptCard: View {
    let prompt: PendingPrompt
    let busy: Bool
    let action: () -> Void

    private static let mono = Font.custom(Theme.fontRegular, size: 13, relativeTo: .footnote)

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: AgentTone.needsYou.symbol)
                    .font(.title3)
                    .foregroundStyle(AgentTone.needsYou.color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.text)
                    if !prompt.summary.isEmpty {
                        Text(prompt.summary)
                            .font(prompt.kind == "approval" ? Self.mono : .subheadline)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text("Toque para responder")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.text)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AgentTone.needsYou.color.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AgentTone.needsYou.color.opacity(0.5), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Abre o pedido para responder"))
        .accessibilityIdentifier("chat-pending-card")
    }

    private var title: LocalizedStringKey {
        switch prompt.kind {
        case "approval": "Pedido de aprovação"
        case "plan": "Plano para revisar"
        default: "Pergunta do Claude"
        }
    }
}

/// Cartao informativo: o Claude espera algo, mas o app nao consegue responder (sem `request_id`
/// nem opcoes, ou `answerable == false`). Sem Aprovar/Negar: so manda ir ao terminal.
struct PendingInfoCard: View {
    let prompt: PendingPrompt
    let onOpenTerminal: () -> Void
    /// Negar pelo app (so com request_id); `nil` esconde o botao.
    var onDeny: (() -> Void)? = nil

    private static let mono = Font.custom(Theme.fontRegular, size: 13, relativeTo: .footnote)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "terminal")
                    .font(.title3)
                    .foregroundStyle(AgentTone.needsYou.color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Responda no terminal")
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.text)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !prompt.summary.isEmpty {
                        Text(prompt.summary)
                            .font(prompt.kind == "approval" ? Self.mono : .footnote)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onOpenTerminal) {
                Label("Abrir terminal", systemImage: "terminal")
            }
            .buttonStyle(.poppyProminent)
            .accessibilityIdentifier("chat-pending-abrir-terminal")
            if let onDeny {
                Button(action: onDeny) { Label("Negar", systemImage: "xmark") }
                    .buttonStyle(.poppyNeutral)
                    .accessibilityIdentifier("chat-pending-negar")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AgentTone.needsYou.color.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AgentTone.needsYou.color.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-pending-info-card")
    }

    private var subtitle: LocalizedStringKey {
        switch prompt.kind {
        case "approval": "O Claude pediu uma aprovação que o app não consegue responder."
        case "plan": "O Claude pediu para revisar um plano que o app não consegue responder."
        default: "O Claude fez uma pergunta que o app não consegue responder."
        }
    }
}

/// Aviso do `409 pending_prompt` quando nao ha cartao respondivel: o estado pode estar velho.
/// "Atualizar" recarrega a conversa; "Abrir terminal" leva ao modo terminal da janela.
struct PendingStaleBanner: View {
    let message: String
    let onRefresh: () -> Void
    let onOpenTerminal: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Label {
                    Text(message).foregroundStyle(Theme.Palette.text)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(AgentTone.error.color)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("Dispensar aviso"))
            }
            VStack(spacing: 8) {
                Button(action: onRefresh) {
                    Label("Atualizar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.poppyNeutral)
                .accessibilityIdentifier("chat-erro-atualizar")
                Button(action: onOpenTerminal) {
                    Label("Abrir terminal", systemImage: "terminal")
                }
                .buttonStyle(.poppyNeutral)
                .accessibilityIdentifier("chat-erro-abrir-terminal")
            }
            .padding(.bottom, 10)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AgentTone.error.color.opacity(0.16)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat-pending-stale-banner")
    }
}
