import XCTest
import UserNotifications
import PoppyKit
@testable import PoppyTerminal

/// v0.4 S4: notificacao local com texto fixo, aviso de regra permanente e a decisao de "quando tratar o link".
@MainActor
final class DeepLinkAppTests: XCTestCase {
    private let hex = "0123456789abcdef0123456789abcdef"

    // MARK: notificacao local (BAIXA 6: summary na tela bloqueada)

    private func secretItem() -> InboxItem {
        InboxItem(id: "17", kind: "approval", session: "sessao-secreta", window: "janela-7", name: "agente-fulano",
                  harness: "claude-code", summary: "Bash: rm -rf /home/gobby/segredo-token-123",
                  options: ["once", "deny"], requestId: "req-abc")
    }

    /// O que a tela bloqueada mostra (titulo, subtitulo, corpo, grupo e o userInfo) e FIXO: nada do item vaza.
    /// Controle negativo: se o corpo voltar a ser `item.summary`, este teste falha.
    func testNotificacaoLocalTemTextoFixoSemSummary() {
        let item = secretItem()
        let content = AttentionNotifier.content(for: item)
        XCTAssertEqual(content.title, "PoppyTerminal")
        XCTAssertEqual(content.body, "Poppy precisa de você")
        XCTAssertEqual(content.subtitle, "")
        var everything = [content.title, content.subtitle, content.body, content.threadIdentifier, content.categoryIdentifier]
        everything += content.userInfo.map { "\($0.key)=\($0.value)" }
        let joined = everything.joined(separator: "|")
        for forbidden in [item.summary, "rm -rf", "segredo", "token", item.name, item.session, item.window, item.harness, "req-abc"] {
            XCTAssertFalse(joined.contains(forbidden), "a notificacao vazou: \(forbidden)")
        }
    }

    func testNotificacaoIgualParaQualquerItem() {
        let a = AttentionNotifier.content(for: secretItem())
        let b = AttentionNotifier.content(for: InboxItem(id: "99", kind: "ask", summary: "Fazer deploy?", options: ["Sim", "Nao"]))
        XCTAssertEqual(a.title, b.title)
        XCTAssertEqual(a.body, b.body)
        XCTAssertEqual(a.threadIdentifier, b.threadIdentifier)
        // Controle: o unico dado variavel e o id do item (para limpar a notificacao), que a tela nao mostra.
        XCTAssertEqual(a.userInfo["inboxID"] as? String, "17")
        XCTAssertEqual(b.userInfo["inboxID"] as? String, "99")
        XCTAssertEqual(a.userInfo.count, 1)
    }

    // MARK: "Regras permanentes: so no PC"

    func testTextoDasRegrasPermanentes() {
        XCTAssertEqual(InboxCopy.permanentRules, "Regras permanentes: só no PC")
        XCTAssertFalse(InboxCopy.permanentRules.contains("Sempre"))
    }

    // MARK: quando tratar o link

    func testLinkSoEhTratadoDestravadoEConectado() {
        // Controle positivo: tudo pronto.
        XCTAssertTrue(DeepLinkFlow.isReady(configured: true, locked: false, connection: .connecting))
        XCTAssertTrue(DeepLinkFlow.isReady(configured: true, locked: false, connection: .online))
        // Travado pelo Face ID: espera.
        XCTAssertFalse(DeepLinkFlow.isReady(configured: true, locked: true, connection: .online))
        // Sem endereco ou sem cliente: espera.
        XCTAssertFalse(DeepLinkFlow.isReady(configured: false, locked: false, connection: .online))
        XCTAssertFalse(DeepLinkFlow.isReady(configured: true, locked: false, connection: .unconfigured))
    }

    func testAlvoDaNavegacao() {
        XCTAssertEqual(DeepLinkFlow.focusTarget(resolved: .item("17"), inboxIDs: ["17", "18"]), "17")
        // Item que nao esta (mais) na Inbox: so a aba Agentes.
        XCTAssertNil(DeepLinkFlow.focusTarget(resolved: .item("99"), inboxIDs: ["17"]))
        // 404 / erro: so a aba Agentes.
        XCTAssertNil(DeepLinkFlow.focusTarget(resolved: .inboxOnly, inboxIDs: ["17"]))
    }

    func testRouterSoGuardaLinkValido() {
        let router = AppRouter()
        router.receive(URL(string: "poppyterminal://inbox/../../x")!)
        XCTAssertNil(router.pendingLink)
        router.receive(URL(string: "poppyterminal://inbox/\(hex.uppercased())")!)
        XCTAssertNil(router.pendingLink)
        router.receive(URL(string: "poppyterminal://inbox/" + String(repeating: "a", count: 300))!)
        XCTAssertNil(router.pendingLink)
        XCTAssertEqual(router.tab, .sessions, "receber nao navega")
        // Controle positivo.
        router.receive(URL(string: "poppyterminal://inbox/\(hex)")!)
        XCTAssertEqual(router.pendingLink, .inbox(pushID: hex))
        XCTAssertEqual(router.tab, .sessions, "receber so guarda; navegar e depois do Face ID")
        XCTAssertNil(router.focusInboxID)
    }
}

@MainActor
final class AlwaysBloqueadoNoAppTests: XCTestCase {
    /// `reply(.always)` nao pede Face ID e nao chega ao servidor: erro local `always_disabled`.
    /// Controle negativo: sem a guarda em ServerStore.reply, o erro seria outro (Face ID/servidor) e o teste falha.
    func testReplyAlwaysEhRecusadoLocalmente() async {
        let auth = FakeAuthenticator(.success)
        let store = ServerStore(gate: AuthGate(authenticator: auth, startLocked: false))
        let item = InboxItem(id: "1", kind: "approval", options: ["once", "always", "deny"], requestId: "r1", answerable: true)
        do {
            try await store.reply(to: item, decision: .always)
            XCTFail("always deveria falhar")
        } catch let error as APIError {
            guard case .api(_, let code, _, _, _) = error else { return XCTFail("erro inesperado: \(error)") }
            XCTAssertEqual(code, "always_disabled")
        } catch {
            XCTFail("erro inesperado: \(error)")
        }
        XCTAssertEqual(auth.calls, 0, "nem Face ID foi pedido")
    }
}
