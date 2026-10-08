import Observation

enum AppTab: Hashable { case sessions, agents, settings }

/// Destino do terminal: sessao + janela (nil = foco do daemon / ultima janela).
struct TerminalRoute: Identifiable, Hashable {
    let session: String
    let window: String?
    var id: String { session + "|" + (window ?? "") }
}

/// Navegacao raiz: aba atual e terminal em tela cheia. O terminal e sempre aberto
/// com foco proprio do celular (nunca muda o foco do PC).
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .sessions
    var terminal: TerminalRoute?

    func openTerminal(session: String, window: String?) {
        terminal = TerminalRoute(session: session, window: window)
    }
}
