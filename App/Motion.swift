import Foundation

/// Tetos de movimento do app (v0.4). Um lugar so para os numeros que os testes cobram.
enum Motion {
    /// Face ID aceito: a Poppy `sleeping` vira `waving` (e a trava some) em no maximo 400 ms.
    static let faceIDToWaving: Duration = .milliseconds(400)
    /// O mesmo teto em segundos, para `Animation`.
    static let faceIDToWavingSeconds: Double = 0.4
    /// Segurar para aprovar um pedido com risco: 0,8 s (v0.5). Mesmo teto na tela e nos testes.
    static let holdToApprove: Duration = .milliseconds(800)
    static let holdToApproveSeconds: Double = 0.8
}

/// Regra pura do "segurar para aprovar" (testada sem tela).
enum HoldPolicy {
    /// Quanto da barra de progresso ja encheu (0 a 1) depois de `elapsed` segundos segurando.
    static func progress(elapsed: Double) -> Double {
        min(1, max(0, elapsed / Motion.holdToApproveSeconds))
    }

    /// Segurou o bastante para aprovar? Menos de 0,8 s nunca aprova.
    static func completes(elapsed: Double) -> Bool {
        elapsed >= Motion.holdToApproveSeconds
    }

    /// So pedido com risco pede para segurar; pedido comum aprova com um toque.
    static func requiresHold(hasRisk: Bool) -> Bool { hasRisk }
}
