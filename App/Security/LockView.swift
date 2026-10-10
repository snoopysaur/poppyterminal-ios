import SwiftUI

/// Tela de trava ao abrir (e apos 5 min em segundo plano). A Poppy dorme; ao liberar, acena
/// enquanto a tela some (<= 400 ms, `Motion`).
struct LockView: View {
    let gate: AuthGate
    @State private var message: String?
    @State private var started = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            PoppyView(gate.isLocked ? .sleeping : .waving, size: 128)
            Text("PoppyTerminal travado")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Palette.text)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("lock-mensagem")
            }
            Button { Task { await attempt() } } label: {
                Label("Desbloquear", systemImage: "faceid")
            }
            .buttonStyle(.poppyProminent)
            .padding(.horizontal, 48)
            .accessibilityIdentifier("lock-desbloquear")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.base.ignoresSafeArea())
        .accessibilityIdentifier("lock-view")
        .task {
            guard !started else { return }
            started = true
            await attempt()
        }
    }

    private func attempt() async {
        switch await gate.unlock() {
        case .success, .unavailable: message = nil
        case .cancelled: message = "Toque em Desbloquear para entrar."
        case .failed: message = "Não deu para confirmar. Tente de novo (a senha do iPhone também vale)."
        }
    }
}
