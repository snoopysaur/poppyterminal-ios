import Foundation
import Observation
import PoppyKit

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

    /// Deep link do push que ainda nao foi tratado (espera o Face ID e a conexao).
    var pendingLink: DeepLink?
    /// Item da Inbox a abrir na aba Agentes (a `InboxView` consome e zera).
    var focusInboxID: String?
    /// So para teste (Debug): milissegundos entre "pronto para tratar" e "navegou".
    var deepLinkMillis: Int?

    func openTerminal(session: String, window: String?) {
        terminal = TerminalRoute(session: session, window: window)
    }

    /// `onOpenURL`: guarda o link se (e so se) for exatamente `poppyterminal://inbox/<32 hex>`.
    /// Qualquer outra coisa e ignorada em silencio. Nada e executado aqui.
    func receive(_ url: URL) {
        guard let link = DeepLink.parse(url) else { return }
        pendingLink = link
    }
}

/// Quando o link guardado pode ser tratado: so com o app configurado, DESTRAVADO pelo Face ID
/// e com cliente da API montado.
enum DeepLinkFlow {
    static func isReady(configured: Bool, locked: Bool, connection: ConnectionState) -> Bool {
        configured && !locked && connection != .unconfigured
    }

    /// O que o link fez: o item existe na Inbox (abre a sheet) ou so a aba Agentes.
    static func focusTarget(resolved: PushResolution, inboxIDs: Set<String>) -> String? {
        if case .item(let id) = resolved, inboxIDs.contains(id) { return id }
        return nil
    }
}

/// Resultado de `GET /api/v1/push/{id}` para o app. Nunca carrega texto do push.
enum PushResolution: Equatable, Sendable {
    /// O servidor disse de que item da Inbox se trata.
    case item(String)
    /// 404 (servidor antigo/expirado) ou erro: abre so a Inbox.
    case inboxOnly
}
