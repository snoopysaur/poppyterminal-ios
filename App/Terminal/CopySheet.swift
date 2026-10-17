import PoppyKit
import SwiftUI
import UIKit

struct CopyPayload: Identifiable {
    let id = UUID()
    let text: String
}

/// Folha de copia: texto visivel da tela em UITextView selecionavel (so leitura).
/// O terminal em si nunca tem selecao; os gestos de selecao do SwiftTerm seguem removidos.
struct CopySheet: View {
    let rawText: String
    @State private var showRaw = false
    private var text: String { showRaw ? rawText : CopyText.clean(rawText) }
    @Environment(\.dismiss) private var dismiss
    @State private var selected = NSRange(location: 0, length: 0)
    @State private var copiedNote = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Copiar")
                    .font(.custom(Theme.fontRegular, size: 16))
                    .foregroundStyle(Theme.Palette.accent)
                if copiedNote {
                    Label {
                        Text("copiado").foregroundStyle(Theme.Palette.text)
                    } icon: {
                        Image(systemName: AgentTone.done.symbol).foregroundStyle(AgentTone.done.color)
                    }
                    .font(.custom(Theme.fontRegular, size: 13))
                }
                Spacer()
                pill(showRaw ? "Limpo" : "Bruto", showRaw ? Theme.accent : Theme.surface1, enabled: true) {
                    showRaw.toggle()
                    selected = NSRange(location: 0, length: 0)
                }
                .accessibilityIdentifier("btn-copiar-bruto")
                pill("Selecao", Theme.surface1, enabled: selected.length > 0) {
                    copy((text as NSString).substring(with: selected))
                }
                .accessibilityIdentifier("btn-copiar-selecao")
                pill("Tudo", Theme.accent, enabled: true) { copy(text) }
                    .accessibilityIdentifier("btn-copiar-tudo")
                pill("Fechar", Theme.surface0, enabled: true) { dismiss() }
                    .accessibilityIdentifier("btn-copiar-fechar")
            }
            .padding(12)
            SelectableText(text: text, selected: $selected)
                .id(showRaw)
                .accessibilityIdentifier("copy-text")
        }
        .background(Theme.Palette.sunken.ignoresSafeArea())
    }

    private func copy(_ s: String) {
        UIPasteboard.general.string = s
        copiedNote = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedNote = false }
    }

    private func pill(_ title: String, _ color: UIColor, enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom(Theme.fontRegular, size: 13))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(minHeight: 44)
                .foregroundStyle(color == Theme.accent && enabled ? Theme.Palette.onAccent : Theme.Palette.text)
                .guildFrame(color == Theme.accent && enabled ? .button : .neutralButton)
                .opacity(enabled ? 1 : 0.6)
        }
        .disabled(!enabled)
    }
}

private struct SelectableText: UIViewRepresentable {
    let text: String
    @Binding var selected: NSRange

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.backgroundColor = Theme.crust
        v.textColor = Theme.foreground
        v.font = Theme.terminalFont(size: 13)
        v.text = text
        // Realce da selecao discreto (a cor de selecao do UIKit deriva do tint).
        v.tintColor = Theme.accent
        v.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: SelectableText
        init(_ p: SelectableText) { parent = p }
        func textViewDidChangeSelection(_ textView: UITextView) {
            let r = textView.selectedRange
            DispatchQueue.main.async { self.parent.selected = r }
        }
    }
}
