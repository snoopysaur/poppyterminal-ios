import Foundation

/// Tetos de movimento do app (v0.4). Um lugar so para os numeros que os testes cobram.
enum Motion {
    /// Face ID aceito: a Poppy `sleeping` vira `waving` (e a trava some) em no maximo 400 ms.
    static let faceIDToWaving: Duration = .milliseconds(400)
    /// O mesmo teto em segundos, para `Animation`.
    static let faceIDToWavingSeconds: Double = 0.4
}
