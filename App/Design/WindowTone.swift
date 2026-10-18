import PoppyKit

extension WindowInfo {
    /// Estado do agente da janela como `AgentTone` (nil = janela sem agente, so terminal).
    /// Fonte unica para a linha da janela e para a Poppy do cabecalho do terminal.
    var agentTone: AgentTone? {
        guard let agent else { return nil }
        if agent.needsYou { return .needsYou }
        switch agent.stateKind {
        case .needsInput: return .needsYou
        case .errored: return .error
        case .working: return .working
        case .done: return .done
        case .idle, .unknown: return .idle
        }
    }
}
