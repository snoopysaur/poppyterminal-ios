import Foundation

// STUB da A3 (apagar na integracao: AppRouter.swift da A1 define estes tipos).
// Assinatura exata do contrato da Onda 3.
struct TerminalRoute: Identifiable, Hashable {
    let session: String
    let window: String?
    var id: String { session + "|" + (window ?? "") }
}
