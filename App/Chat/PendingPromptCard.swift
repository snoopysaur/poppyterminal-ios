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
