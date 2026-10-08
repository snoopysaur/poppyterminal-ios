import SwiftUI

// STUBS da frente A1: apagar na integracao (A2 cria InboxView, A3 cria TerminalScreen).

struct InboxView: View {
    init() {}
    var body: some View { EmptyStateView(.allCaughtUp) }
}

struct TerminalScreen: View {
    let route: TerminalRoute
    @Environment(\.dismiss) private var dismiss
    init(route: TerminalRoute) { self.route = route }
    var body: some View {
        Button("Fechar") { dismiss() }
    }
}
