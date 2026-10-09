import SwiftUI
import PoppyKit

/// Compositor do chat: campo de varias linhas, enviar e (com o agente trabalhando) interromper.
/// Bloqueado com pedido pendente ("responda o pedido acima") e, sem login Tailscale, so leitura.
struct ChatComposer: View {
    enum Lock: Equatable {
        case none
        /// Prompt bloqueante pendente: a resposta vai pelo sheet.
        case pending
        /// Sem `humanActions`: o servidor recusaria enviar.
        case readOnly
    }

    @Bindable var chat: ChatStore
    let lock: Lock

    @FocusState private var focused: Bool

    private var locked: Bool { lock != .none }
    private var canSend: Bool {
        !locked && !chat.sending && !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var showInterrupt: Bool { lock != .readOnly && chat.agentState == "working" }
    private var runeCount: Int { chat.draft.unicodeScalars.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let notice {
                Label(notice.text, systemImage: notice.symbol)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            HStack(alignment: .bottom, spacing: 8) {
                field
                if showInterrupt { interruptButton }
                sendButton
            }
            if runeCount > ChatText.maxRunes * 9 / 10 {
                Text("\(runeCount) / \(ChatText.maxRunes)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(runeCount > ChatText.maxRunes ? AgentTone.error.color : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.Palette.base)
    }

    private var notice: (text: LocalizedStringKey, symbol: String)? {
        switch lock {
        case .none: nil
        case .pending: ("responda o pedido acima", "arrow.up")
        case .readOnly: ("Login sem Tailscale: só leitura. Entre pelo endereço Tailscale para enviar.", "eye")
        }
    }

    private var field: some View {
        TextField("Mensagem para o Claude", text: $chat.draft, axis: .vertical)
            .lineLimit(1...6)
            .font(.body)
            .foregroundStyle(Theme.Palette.text)
            .focused($focused)
            .disabled(locked)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .opacity(locked ? 0.55 : 1)
            .accessibilityIdentifier("chat-field")
    }

    private var sendButton: some View {
        Button {
            Task { await chat.send() }
        } label: {
            Image(systemName: "arrow.up")
                .font(.body.weight(.bold))
                .foregroundStyle(canSend ? Theme.Palette.onAccent : Theme.Palette.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(canSend ? Theme.Palette.accent : Theme.Palette.surfaceStrong))
        }
        .disabled(!canSend)
        .accessibilityLabel(Text("Enviar"))
        .accessibilityIdentifier("chat-send")
        .sensoryFeedback(.impact(weight: .light), trigger: chat.sending) { old, new in !old && new }
    }

    private var interruptButton: some View {
        Button {
            Task { await chat.interrupt() }
        } label: {
            Image(systemName: "stop.fill")
                .font(.body)
                .foregroundStyle(Theme.Palette.text)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.Palette.surfaceStrong))
        }
        .accessibilityLabel(Text("Interromper o Claude"))
        .accessibilityIdentifier("chat-interrupt")
    }
}
