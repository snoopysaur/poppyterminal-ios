import SwiftUI
import PoppyKit

/// Como a aba Agentes enxerga cada tipo de item da inbox.
enum InboxGroup: Int, CaseIterable, Identifiable {
    case approval, question, plan, error, finished, other

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .approval: "Aprovações"
        case .question: "Perguntas"
        case .plan: "Planos"
        case .error: "Erros"
        case .finished: "Terminaram"
        case .other: "Outros"
        }
    }

    var tone: AgentTone {
        switch self {
        case .approval, .question, .plan: .needsYou
        case .error: .error
        case .finished: .done
        case .other: .idle
        }
    }
}

extension InboxItem {
    var group: InboxGroup {
        switch kind {
        case .approval: .approval
        case .ask, .question: .question
        case .plan: .plan
        case .errored: .error
        case .finished: .finished
        default: .other
        }
    }

    /// Nome para a linha: agente/janela se houver, senao a sessao.
    var displayName: String {
        if !name.isEmpty { return name }
        if !window.isEmpty { return "\(session) · \(window)" }
        return session
    }

    var location: String {
        window.isEmpty ? session : "\(session) · \(window)"
    }

    /// Dispensar so faz sentido para quem tem sessao no PC.
    var canOpenTerminal: Bool { !session.isEmpty }
}
