import XCTest

/// E2E no Simulator contra o tuios-web REAL (scripts/e2e-server.sh). Cada teste reabre o app e,
/// se preciso, refaz a primeira conexao. Sem `E2E_URL` os testes sao PULADOS (nunca "passam").
/// Nenhum teste depende do anterior alem do servidor semeado; os nomes test01... so ordenam a leitura.
@MainActor
final class E2ETests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Janela A = a que tem o foco do dono no PC; B = outra (a "beta" semeada).
    private func aAndB() async throws -> (a: E2E.Window, b: E2E.Window) {
        let ws = await E2E.windows()
        let a = try XCTUnwrap(ws.first(where: \.focused), "o servidor semeado deveria ter foco do PC em A")
        let b = try XCTUnwrap(ws.first(where: { $0.name == "beta" }), "o servidor semeado deveria ter a janela beta")
        return (a, b)
    }

    private func waitGone(_ app: XCUIApplication, _ text: String, timeout: TimeInterval = 15) async {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                            object: element(app, containing: text))
        await fulfillment(of: [exp], timeout: timeout)
    }

    // 1. Primeira conexao + listar sessoes
    func test01_PrimeiraConexaoEListaSessoes() async throws {
        let app = try launchConnected()
        let row = element(app, containing: E2E.session)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "a sessao semeada aparece na aba Sessoes")
        attach(app, "e2e-01-sessoes")
    }

    // 2. Abrir a janela B no terminal; o foco do PC fica em A (criterio 8)
    func test02_TerminalNaJanelaBMantemFocoDoPcEmA() async throws {
        let (a, b) = try await aAndB()
        let app = try launchConnected()
        openSession(app)
        let row = element(app, containing: b.name)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "linha da janela B (\(b.name))")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["terminal"].waitForExistence(timeout: 15), "terminal abriu")
        attach(app, "e2e-02-terminal-janela-b")
        let held = await E2E.holds(5) { await E2E.focusedID() == a.id }
        let now = await E2E.focusedID() ?? "nenhum"
        XCTAssertTrue(held, "o foco do PC saiu de A (\(a.id)) ao abrir B no celular; agora: \(now)")
        app.buttons["btn-voltar-terminal"].tap()
    }

    // 3. "+" cria janela e o foco do PC segue em A (criterio 8)
    func test03_NovaJanelaPeloMaisMantemFocoEmA() async throws {
        let (a, _) = try await aAndB()
        let before = await E2E.windows().count
        let app = try launchConnected()
        openSession(app)
        app.buttons["btn-nova-janela"].tap()
        let name = app.textFields["field-nome-janela"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "sheet Nova janela")
        name.tap()
        name.typeText("criada")
        app.buttons["Criar"].tap()
        let created = await E2E.eventually { await E2E.windows().contains(where: { $0.name == "criada" }) }
        XCTAssertTrue(created, "a janela criada existe no servidor")
        let after = await E2E.windows().count
        XCTAssertEqual(after, before + 1)
        let held = await E2E.holds(3) { await E2E.focusedID() == a.id }
        let now = await E2E.focusedID() ?? "nenhum"
        XCTAssertTrue(held, "criar janela pelo + mexeu no foco do PC; agora: \(now)")
        attach(app, "e2e-03-nova-janela")
    }

    // 4. Fechar janela com confirmacao
    func test04_FecharJanelaComConfirmacao() async throws {
        let (a, _) = try await aAndB()
        // Janela descartavel criada pela API (nao depende do teste 3).
        let made = await E2E.call("POST", "/api/v1/sessions/\(E2E.session)/windows", body: ["name": "descartavel"])
        XCTAssertEqual(made?.0, 201, "criar janela descartavel pela API")
        let app = try launchConnected()
        openSession(app)
        let row = element(app, containing: "descartavel")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "linha da janela descartavel")
        row.swipeLeft()
        let swipeClose = app.buttons["Fechar"]
        XCTAssertTrue(swipeClose.waitForExistence(timeout: 5), "acao Fechar do swipe")
        swipeClose.tap()
        let confirm = app.buttons["Fechar descartavel"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmacao antes de fechar")
        let still = await E2E.windows().contains(where: { $0.name == "descartavel" })
        XCTAssertTrue(still, "a janela nao pode fechar antes da confirmacao")
        attach(app, "e2e-04-confirmacao-fechar")
        confirm.tap()
        let gone = await E2E.eventually { !(await E2E.windows().contains(where: { $0.name == "descartavel" })) }
        XCTAssertTrue(gone, "a janela fechou no servidor depois de confirmar")
        let focus = await E2E.focusedID()
        XCTAssertEqual(focus, a.id, "fechar uma janela pelo celular mexeu no foco do PC")
    }

    // 5. Pedido de aprovacao na aba Agentes: "Uma vez" e ele some
    func test05_AprovarUmaVezPeloCelular() async throws {
        let app = try launchConnected()
        app.tabBars.buttons["Agentes"].tap()
        let row = element(app, containing: "go test")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "pedido de aprovacao (go test) na aba Agentes")
        attach(app, "e2e-05-agentes-aprovacao")
        row.tap()
        let once = app.buttons["Uma vez"]
        XCTAssertTrue(once.waitForExistence(timeout: 10), "botao Uma vez (human_actions ligado)")
        attach(app, "e2e-05-sheet-aprovacao")
        once.tap()
        let gone = await E2E.eventually { !(await E2E.inboxSummaries().contains(where: { $0.contains("go test") })) }
        XCTAssertTrue(gone, "o servidor ainda lista o pedido depois de aprovar")
        await waitGone(app, "go test")
        XCTAssertFalse(element(app, containing: "go test").exists, "o pedido continua na tela depois de aprovar")
    }

    // 6. Pergunta do agente respondida pelo celular
    func test06_ResponderPergunta() async throws {
        let app = try launchConnected()
        app.tabBars.buttons["Agentes"].tap()
        let row = element(app, containing: "Fazer deploy?")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "pergunta na aba Agentes")
        row.tap()
        let yes = app.buttons["Sim"]
        XCTAssertTrue(yes.waitForExistence(timeout: 10), "opcao Sim")
        attach(app, "e2e-06-sheet-pergunta")
        yes.tap()
        let gone = await E2E.eventually { !(await E2E.inboxSummaries().contains(where: { $0.contains("Fazer deploy?") })) }
        XCTAssertTrue(gone, "o servidor ainda lista a pergunta depois de responder")
    }

    // 7. Voltar do segundo plano: o app retoma o SSE com after_seq e recupera o que perdeu
    func test07_RetomarDoSegundoPlanoComAfterSeq() async throws {
        let app = try launchConnected()
        app.tabBars.buttons["Sessões"].tap()
        // Deixa o 1o `ready` chegar (o cursor so existe depois dele).
        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let made = await E2E.call("POST", "/api/v1/sessions/\(E2E.session)/windows", body: ["name": "enquanto-fora"])
        XCTAssertEqual(made?.0, 201, "criar janela com o app em segundo plano")
        let total = await E2E.windows().count
        app.activate()
        XCTAssertTrue(app.tabBars.buttons["Sessões"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Sessões"].tap()
        let expected = "\(total) janelas"
        XCTAssertTrue(element(app, containing: expected).waitForExistence(timeout: 20),
                      "a lista de sessoes mostra \(expected) depois de voltar")
        attach(app, "e2e-07-retomou")
    }
}
