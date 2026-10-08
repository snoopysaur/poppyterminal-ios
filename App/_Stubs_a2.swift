import SwiftUI
import Observation

// STUB da frente A2 (assinaturas exatas do contrato da Onda 3). A1 entrega os tipos reais
// em App/Navigation/AppRouter.swift: APAGAR este arquivo na integracao.

enum AppTab: Hashable { case sessions, agents, settings }

struct TerminalRoute: Identifiable, Hashable {
    let session: String
    let window: String?
    var id: String { session + "|" + (window ?? "") }
}

@MainActor @Observable
final class AppRouter {
    var tab: AppTab = .sessions
    var terminal: TerminalRoute?
    func openTerminal(session: String, window: String?) {
        tab = .sessions
        terminal = TerminalRoute(session: session, window: window)
    }
}
