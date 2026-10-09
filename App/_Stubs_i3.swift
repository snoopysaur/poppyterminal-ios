import SwiftUI

// STUB da Onda 2 (frente I3): a integracao apaga este arquivo quando o ChatView real (I2) entrar.
// Assinatura fixa de contrato §8.4.
struct ChatView: View {
    let session: String
    let window: String
    let onShowTerminal: () -> Void

    init(session: String, window: String, onShowTerminal: @escaping () -> Void) {
        self.session = session
        self.window = window
        self.onShowTerminal = onShowTerminal
    }

    var body: some View {
        ContentUnavailableView {
            Label("Chat", systemImage: "bubble.left.and.text.bubble.right")
        } actions: {
            Button("Abrir terminal", action: onShowTerminal)
                .buttonStyle(.poppyProminent)
        }
        .background(Theme.Palette.base)
    }
}
