import SwiftUI

/// Botao de microfone (liga e desliga o ditado). 48 pt, moldura Guild; ouro enquanto ouve.
struct DictationButton: View {
    let dictation: DictationController
    var enabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { dictation.toggle() } label: {
            Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(dictation.isListening ? Theme.Palette.onAccent : Theme.Palette.text)
                .symbolEffect(.pulse, isActive: dictation.isListening && !reduceMotion)
                .frame(width: 48, height: 48)
                .guildFrame(dictation.isListening ? .button : .neutralButton)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityLabel(Text(dictation.isListening ? "Parar o ditado" : "Ditar por voz"))
        .accessibilityIdentifier("ditado-botao")
    }
}

/// Aviso curto sobre o estado do ditado (ouvindo, sem permissao, indisponivel). Texto em SF.
struct DictationNotice: View {
    let dictation: DictationController

    var body: some View {
        if let text {
            Label {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: dictation.isListening ? "waveform" : "mic.slash")
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ditado-aviso")
        }
    }

    private var text: LocalizedStringKey? {
        switch dictation.state {
        case .listening, .starting:
            if dictation.onDevice {
                return LocalizedStringKey("Ouvindo. O texto aparece no campo para você revisar; nada é enviado sozinho.")
            }
            return LocalizedStringKey("Ouvindo. O ditado do iOS pode passar pela Apple. O texto aparece no campo para você revisar; nada é enviado sozinho.")
        case .denied:
            return LocalizedStringKey("Sem permissão. Libere o microfone e o reconhecimento de fala em Ajustes do iPhone.")
        case .unavailable:
            return LocalizedStringKey("Ditado indisponível agora em português.")
        case .idle:
            return nil
        }
    }
}

/// Ditado para o terminal: fala, revisa e so entao insere o texto (sem Enter). Nunca manda direto.
struct DictationSheet: View {
    let onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dictation = DictationController()
    @State private var text = ""
    @State private var base = ""

    private var cleaned: String { DictationText.forTerminal(text) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fale, revise o texto e toque em Inserir. O texto entra no terminal sem Enter.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.text)
                    .padding(12)
                    .frame(minHeight: 120)
                    .guildFrame(.seal)
                    .accessibilityIdentifier("ditado-campo")
                HStack(spacing: 12) {
                    DictationButton(dictation: dictation)
                    Spacer(minLength: 0)
                }
                DictationNotice(dictation: dictation)
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Theme.Palette.base)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .navigationTitle("Ditado")
            .guildNavTitle("Ditado")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { close() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: dictation.isListening) { _, listening in
            if listening { base = text }
        }
        .onChange(of: dictation.transcript) { _, spoken in
            if !spoken.isEmpty { text = DictationText.merge(base: base, dictated: spoken) }
        }
        .onDisappear { dictation.stop() }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button { insert() } label: { Label("Inserir no terminal", systemImage: "arrow.down.left") }
                .buttonStyle(.poppyThumbProminent)
                .disabled(cleaned.isEmpty)
                .accessibilityIdentifier("ditado-inserir")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.mantle)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Palette.border).frame(height: 1) }
    }

    private func insert() {
        dictation.stop()
        let out = cleaned
        guard !out.isEmpty else { return }
        onInsert(out)
        dismiss()
    }

    private func close() {
        dictation.stop()
        dismiss()
    }
}
