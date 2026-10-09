import SwiftUI
import PoppyKit

/// Uma mensagem de texto, imagem ou interrupcao. `tool_use` e desenhado pelo `ToolCallRow`.
/// Usuario: balao com tom do acento, a direita. Claude: balao `surface`, a esquerda.
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.kind {
        case .text: textBubble
        case .image: imageChip
        case .interrupted: interruptedLine
        default: EmptyView()
        }
    }

    private var isUser: Bool { message.role == .user }

    private var textBubble: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.render(message.text, markdown: !isUser))
                    .font(.body)
                    .foregroundStyle(Theme.Palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if message.truncated {
                    Text("(cortado)")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isUser ? Theme.Palette.accent.opacity(0.2) : Theme.Palette.surface)
            )
            .fixedSize(horizontal: false, vertical: true)
            if !isUser { Spacer(minLength: 24) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isUser ? "Você" : "Claude"))
    }

    private var imageChip: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            Label("imagem", systemImage: "photo")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.text)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Capsule().fill(Theme.Palette.surface))
            if !isUser { Spacer(minLength: 24) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isUser ? "Você enviou uma imagem" : "Imagem"))
    }

    private var interruptedLine: some View {
        Label("interrompido", systemImage: "stop.circle")
            .font(.footnote)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
    }

    /// Markdown so em linha (negrito, codigo). Links viram texto: nada no historico e tocavel.
    static func render(_ text: String, markdown: Bool) -> AttributedString {
        guard markdown else { return AttributedString(text) }
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard var parsed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        for run in parsed.runs where run.link != nil {
            parsed[run.range].link = nil
        }
        return parsed
    }
}

/// Bolha local da mensagem enviada, ate o transcript confirmar.
struct OutgoingBubble: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label("enviando", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Palette.accent.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.Palette.accent.opacity(0.4), lineWidth: 1)
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Você, enviando"))
    }
}
