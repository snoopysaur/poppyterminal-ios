import SwiftUI

/// Estados de um agente/sessao e seus papeis visuais. Cor nunca e o unico sinal:
/// cada estado tem simbolo e rotulo proprios.
enum AgentTone: String, CaseIterable, Identifiable, Equatable, Sendable {
    case needsYou, error, working, done, idle

    var id: String { rawValue }

    /// 0 = mais urgente. Use para ordenar listas.
    var priority: Int {
        switch self {
        case .needsYou: 0
        case .error: 1
        case .working: 2
        case .done: 3
        case .idle: 4
        }
    }

    var color: Color {
        switch self {
        case .needsYou: Color(uiColor: Theme.peach)
        case .error: Color(uiColor: Theme.red)
        case .working: Color(uiColor: Theme.blue)
        case .done: Color(uiColor: Theme.green)
        case .idle: Color(uiColor: Theme.overlay1)
        }
    }

    var symbol: String {
        switch self {
        case .needsYou: "exclamationmark.bubble.fill"
        case .error: "xmark.octagon.fill"
        case .working: "gearshape.2.fill"
        case .done: "checkmark.circle.fill"
        case .idle: "moon.zzz.fill"
        }
    }

    /// Texto do estado (rotulo visivel e VoiceOver).
    var labelText: String {
        switch self {
        case .needsYou: String(localized: "precisa de você")
        case .error: String(localized: "erro")
        case .working: String(localized: "trabalhando")
        case .done: String(localized: "terminou")
        case .idle: String(localized: "ocioso")
        }
    }

    /// Haptic ao ENTRAR neste estado (nil = silencioso).
    var feedback: SensoryFeedback? {
        switch self {
        case .needsYou: .warning
        case .error: .error
        case .done: .success
        case .working, .idle: nil
        }
    }
}
