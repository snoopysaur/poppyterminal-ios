import SwiftUI
import PoppyKit

/// Uma chamada de ferramenta: nome e resumo (ja redigido pelo servidor) em JetBrains Mono, numa linha,
/// e o estado: rodando, ok com o numero de linhas, erro ou sem retorno.
struct ToolCallRow: View {
    let tool: ChatToolCall
    let result: ChatToolResult?
    /// A ferramenta ainda nao devolveu e o agente segue trabalhando.
    let running: Bool

    private static let mono = Font.custom(Theme.fontRegular, size: 13, relativeTo: .footnote)

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 20)
            Text(label)
                .font(Self.mono)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Palette.sunken))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(tool.name) \(tool.summary), \(statusText)"))
    }

    private var label: AttributedString {
        var name = AttributedString(tool.name)
        name.foregroundColor = Theme.Palette.text
        guard !tool.summary.isEmpty else { return name }
        var summary = AttributedString("  " + tool.summary)
        summary.foregroundColor = Theme.Palette.textSecondary
        return name + summary
    }

    @ViewBuilder private var statusIcon: some View {
        if let result {
            if result.ok {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(AgentTone.done.color)
            } else {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(AgentTone.error.color)
            }
        } else if running {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "minus.circle").foregroundStyle(AgentTone.idle.color)
        }
    }

    private var statusText: String {
        if let result {
            if !result.ok { return String(localized: "erro") }
            return result.lines == 1 ? String(localized: "1 linha") : String(localized: "\(result.lines) linhas")
        }
        return running ? String(localized: "rodando") : String(localized: "sem retorno")
    }
}
