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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Ditado: o texto falado entra no campo, a pessoa revisa e envia (nunca sai sozinho).
    @State private var dictation = DictationController()
    @State private var dictationBase = ""

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
            DictationNotice(dictation: dictation)
            HStack(alignment: .bottom, spacing: 8) {
                field
                DictationButton(dictation: dictation, enabled: !locked)
                if showInterrupt { interruptButton }
                sendButton
            }
            if runeCount > ChatText.maxRunes * 9 / 10 {
                Text("\(runeCount) / \(ChatText.maxRunes)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(runeCount > ChatText.maxRunes ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.Palette.base)
        .onChange(of: dictation.isListening) { _, listening in
            if listening { dictationBase = chat.draft } // o ditado soma ao que ja estava escrito
        }
        .onChange(of: dictation.transcript) { _, spoken in
            // Sem checar "ouvindo": o ultimo trecho chega junto com o fim do ditado.
            if !spoken.isEmpty { chat.draft = DictationText.merge(base: dictationBase, dictated: spoken) }
        }
        .onChange(of: locked) { _, isLocked in
            if isLocked { dictation.stop() }
        }
        .onDisappear { dictation.stop() }
    }

    private var notice: (text: LocalizedStringKey, symbol: String)? {
        switch lock {
        case .none: nil
        case .pending: ("responda o pedido acima", "arrow.up")
        case .readOnly: ("Login sem Tailscale: só leitura. Entre pelo endereço Tailscale para enviar.", "eye")
        }
    }

    private var field: some View {
        TextField(typeSize.isAccessibilitySize ? "Mensagem" : "Mensagem para o Claude", text: $chat.draft, axis: .vertical)
            .lineLimit(1...6)
            .font(.body)
            .foregroundStyle(Theme.Palette.text)
            .focused($focused)
            .disabled(locked)
            .accessibilityIdentifier("chat-field")
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .guildFrame(.seal)
            .opacity(locked ? 0.55 : 1)
            
    }

    private var sendButton: some View {
        Button {
            Task { await chat.send() }
        } label: {
            Image(systemName: "arrow.up")
                .font(.body.weight(.bold))
                .foregroundStyle(canSend ? Theme.Palette.onAccent : Theme.Palette.textSecondary)
                .frame(width: 48, height: 48)
                .guildFrame(canSend ? .button : .neutralButton)
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
                .frame(width: 48, height: 48)
                .guildFrame(.neutralButton)
        }
        .accessibilityLabel(Text("Interromper o Claude"))
        .accessibilityIdentifier("chat-interrupt")
    }
}
