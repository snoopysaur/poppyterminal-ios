import XCTest

/// E2E no Simulator contra o tuios-web REAL (scripts/e2e-server.sh). Cada teste reabre o app e,
/// se preciso, refaz a primeira conexao. Sem `E2E_URL` os testes sao PULADOS (nunca "passam").
/// Nenhum teste depende do anterior alem do servidor semeado; os nomes test01... so ordenam a leitura.
@MainActor
final class E2ETests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
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
        let seeded = await E2E.seed("approval", tag: "e2e05")
        XCTAssertTrue(seeded, "semear aprovacao")
        let app = try launchConnected()
        app.tabBars.buttons["Agentes"].tap()
        let row = element(app, containing: "e2e05")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "pedido de aprovacao (go test) na aba Agentes")
        attach(app, "e2e-05-agentes-aprovacao")
        row.tap()
        let once = app.buttons["Uma vez"]
        XCTAssertTrue(once.waitForExistence(timeout: 10), "botao Uma vez (human_actions ligado)")
        attach(app, "e2e-05-sheet-aprovacao")
        once.tap()
        let gone = await E2E.eventually { !(await E2E.inboxSummaries().contains(where: { $0.contains("e2e05") })) }
        XCTAssertTrue(gone, "o servidor ainda lista o pedido depois de aprovar")
        await waitGone(app, "e2e05")
        XCTAssertFalse(element(app, containing: "e2e05").exists, "o pedido continua na tela depois de aprovar")
    }

    // 6. Pergunta do agente respondida pelo celular
    func test06_ResponderPergunta() async throws {
        let seeded = await E2E.seed("ask", tag: "e2e06")
        XCTAssertTrue(seeded, "semear pergunta")
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

    // MARK: - v0.3.0: chat

    private func openChat(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        openSession(app)
        let row = element(app, containing: E2E.chatWindow)
        XCTAssertTrue(row.waitForExistence(timeout: 15), "linha da janela \(E2E.chatWindow)", file: file, line: line)
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chat-field"].waitForExistence(timeout: 20),
                      "janela com Claude abre no chat (compositor)", file: file, line: line)
    }

    // 8. Abrir a janela com Claude mostra os baloes; linha nova chega ao vivo
    func test08_AbrirJanelaComClaudeMostraBaloes() async throws {
        let app = try launchConnected()
        openChat(app)
        XCTAssertTrue(bubble(app, containing: "como posso ajudar").waitForExistence(timeout: 15), "balao do Claude")
        XCTAssertTrue(bubble(app, containing: "ola, Claude").exists, "balao da pessoa")
        XCTAssertTrue(app.buttons["chat-show-terminal"].exists, "atalho para o terminal")
        XCTAssertFalse(app.descendants(matching: .any)["seletor-modo"].exists, "o seletor segmentado saiu (v0.5): ficam as pilulas Chat/Terminal")
        XCTAssertTrue(app.buttons["ditado-botao"].exists, "botao de ditado ao lado do campo do chat")
        attach(app, "e2e-08-chat")
        let seeded = await E2E.seed("chatline", tag: "e2ech08")
        XCTAssertTrue(seeded, "semear linha nova no transcript")
        XCTAssertTrue(bubble(app, containing: "resposta ao vivo e2ech08").waitForExistence(timeout: 15),
                      "a linha nova do transcript chega ao celular pelo stream")
        attach(app, "e2e-08-chat-ao-vivo")
    }

    /// Semeia respostas longas (30 linhas) e espera cada uma chegar.
    private func seedLong(_ app: XCUIApplication, _ tags: [String]) async {
        for tag in tags {
            let ok = await E2E.seed("chatlong", tag: tag)
            XCTAssertTrue(ok, "semear resposta longa \(tag)")
            XCTAssertTrue(bubble(app, containing: "fim \(tag)").waitForExistence(timeout: 15), "resposta longa \(tag) chegou")
        }
    }

    /// A ULTIMA linha da bolha esta na area da conversa: o fim da bolha fica acima do compositor e dentro da janela.
    /// (isHittable usa o centro; uma bolha alta pode ter o centro na tela e o fim fora.)
    private func assertFimVisivel(_ app: XCUIApplication, _ bubbleEl: XCUIElement, _ msg: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let field = app.descendants(matching: .any)["chat-field"]
        let window = app.windows.firstMatch.frame
        let f = bubbleEl.frame
        XCTAssertTrue(field.exists, "compositor", file: file, line: line)
        XCTAssertLessThanOrEqual(f.maxY, field.frame.minY + 2, "\(msg): o fim da bolha esta acima do compositor (maxY=\(f.maxY), compositor=\(field.frame.minY))", file: file, line: line)
        XCTAssertGreaterThan(f.maxY, window.minY + 40, "\(msg): o fim da bolha esta dentro da janela", file: file, line: line)
        XCTAssertLessThanOrEqual(f.maxY, window.maxY, "\(msg): o fim da bolha nao passa da janela", file: file, line: line)
    }

    // 8b. Regressao v0.4.x: resposta longa chegando no fim nao deixa a tela vazia nem liga "Ir para o fim"
    func test08b_MensagemLongaNovaFicaVisivelSemBotaoIrParaOFim() async throws {
        let app = try launchConnected()
        openChat(app)
        XCTAssertTrue(bubble(app, containing: "como posso ajudar").waitForExistence(timeout: 15), "balao inicial")
        await seedLong(app, ["e2elongb1", "e2elongb2", "e2elongb3", "e2elongb4"])
        let last = bubble(app, containing: "fim e2elongb4")
        // Sem tocar em rolagem: a ULTIMA linha precisa estar na tela (espera o seguimento pos-layout).
        let deadline = Date().addingTimeInterval(10)
        let field = app.descendants(matching: .any)["chat-field"]
        while Date() < deadline, last.frame.maxY > field.frame.minY + 2 { try await Task.sleep(nanoseconds: 250_000_000) }
        assertFimVisivel(app, last, "mensagem nova no fim")
        XCTAssertFalse(app.buttons["Ir para o fim"].exists, "botao Ir para o fim nao deve aparecer")
        attach(app, "e2e-08b-chat-longo")
    }

    // 8c. Quem rolou para cima de proposito nao e puxado de volta por mensagem nova; a seta aparece
    func test08c_RolouParaCimaNaoEPuxadoDeVoltaPorMensagemNova() async throws {
        let app = try launchConnected()
        openChat(app)
        XCTAssertTrue(bubble(app, containing: "como posso ajudar").waitForExistence(timeout: 15), "balao inicial")
        await seedLong(app, ["e2elongc1", "e2elongc2", "e2elongc3"])
        let arrow = app.buttons["Ir para o fim"]
        for _ in 0..<4 where !arrow.exists {
            app.swipeDown()
        }
        XCTAssertTrue(arrow.waitForExistence(timeout: 5), "seta Ir para o fim aparece depois de rolar para cima")
        let ref = bubble(app, containing: "fim e2elongc2")
        let before = ref.frame.minY
        await seedLong(app, ["e2elongc5"])
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(ref.frame.minY, before, accuracy: 3, "a posicao da conversa nao muda com mensagem nova")
        XCTAssertTrue(arrow.exists, "a seta continua visivel")
        attach(app, "e2e-08c-rolou-para-cima")
    }

    // 8d. Teclado aberto estando no fim: a ultima mensagem continua visivel
    func test08d_TecladoAbertoNoFimMantemUltimaMensagemVisivel() async throws {
        let app = try launchConnected()
        openChat(app)
        XCTAssertTrue(bubble(app, containing: "como posso ajudar").waitForExistence(timeout: 15), "balao inicial")
        await seedLong(app, ["e2elongd1", "e2elongd2"])
        let last = bubble(app, containing: "fim e2elongd2")
        let field = app.descendants(matching: .any)["chat-field"]
        let settle = Date().addingTimeInterval(10)
        while Date() < settle, last.frame.maxY > field.frame.minY + 2 { try await Task.sleep(nanoseconds: 250_000_000) }
        field.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 8) else {
            throw XCTSkip("SKIP EXPLICITO: simulador com teclado de hardware conectado (sem teclado de software); a rolagem com teclado so e validada em simulador/iPhone com teclado de software")
        }
        let until = Date().addingTimeInterval(8)
        while Date() < until, !(last.frame.maxY <= field.frame.minY + 2 && last.frame.maxY > 40) {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        attach(app, "e2e-08d-teclado")
        assertFimVisivel(app, last, "com o teclado aberto")
    }

    // 9. Enviar pelo compositor: aparece no chat e chega ao PTY (conferido no verify do servidor)
    func test09_EnviarPeloChat() async throws {
        let app = try launchConnected()
        openChat(app)
        let field = app.descendants(matching: .any)["chat-field"]
        field.tap()
        field.typeText("echo E2ESEND")
        let send = app.buttons["chat-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5) && send.isEnabled, "botao Enviar habilitado")
        send.tap()
        XCTAssertTrue(bubble(app, containing: "E2ESEND").waitForExistence(timeout: 15), "a mensagem aparece no chat")
        attach(app, "e2e-09-chat-enviado")
    }

    // 10. O cartao do pedido pendente abre o sheet e responde (o hook de aprovacao do molde troca o harness da janela
    //     para qwen e tira o chat; a pergunta ask-human nao mexe nisso)
    func test10_CartaoPendenteAbreSheetEAprova() async throws {
        let seeded = await E2E.seed("ask", tag: "e2echat10")
        XCTAssertTrue(seeded, "semear pergunta pendente na janela \(E2E.chatWindow)")
        let app = try launchConnected()
        openChat(app)
        let card = app.descendants(matching: .any)["chat-pending-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 25), "cartao do pedido pendente no chat")
        attach(app, "e2e-10-chat-cartao")
        card.tap()
        let once = app.buttons["Sim"]
        XCTAssertTrue(once.waitForExistence(timeout: 10), "sheet com a opcao Sim")
        attach(app, "e2e-10-chat-sheet")
        once.tap()
        let gone = await E2E.eventually { !(await E2E.inboxSummaries().contains(where: { $0.contains("e2echat10") })) }
        XCTAssertTrue(gone, "o servidor ainda lista a pergunta depois de responder")
        let cardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: card)
        await fulfillment(of: [cardGone], timeout: 20)
        XCTAssertFalse(card.exists, "o cartao some depois de aprovar")
    }

    // 11. Servidor sem `features` (antigo): a mesma janela abre direto no terminal de hoje.
    //     Troca o endereco pelos Ajustes e volta ao normal no fim.
    func test11_ServidorSemFeaturesMostraOTerminal() async throws {
        guard let legacy = E2E.legacyURL, let normal = E2E.baseURL?.absoluteString else {
            throw XCTSkip("E2E_LEGACY_URL ausente")
        }
        let app = try launchConnected()
        func setServer(_ url: String) {
            app.tabBars.buttons["Ajustes"].tap()
            let field = app.textFields["field-url"]
            XCTAssertTrue(field.waitForExistence(timeout: 10), "campo de endereco em Ajustes")
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            let current = (field.value as? String) ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
            field.typeText(url + "\n") // o Return fecha o teclado (ele cobre a barra de abas)
            let save = app.buttons["btn-salvar"]
            XCTAssertTrue(save.waitForExistence(timeout: 5), "botao Salvar")
            save.tap()
        }
        setServer(legacy)
        defer { setServer(normal) }
        openSession(app)
        let row = element(app, containing: E2E.chatWindow)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "janela \(E2E.chatWindow) no servidor antigo")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["terminal"].waitForExistence(timeout: 20), "abre o terminal")
        XCTAssertFalse(app.descendants(matching: .any)["seletor-modo"].exists, "sem seletor Chat/Terminal")
        XCTAssertFalse(app.descendants(matching: .any)["chat-field"].exists, "sem chat")
        XCTAssertTrue(app.descendants(matching: .any)["poppy-companheira"].exists, "Poppy companheira no cabecalho do terminal")
        attach(app, "e2e-11-servidor-antigo-terminal")
        app.buttons["btn-voltar-terminal"].tap()
    }

    // 12. v0.3.2 r2: aprovacao com trecho redigido vem answerable:false. O sheet nao oferece
    //     Uma vez/Sempre e mostra o aviso.
    func test12_ItemRedigidoNaoOfereceAprovar() async throws {
        let seeded = await E2E.seed("approval", tag: "esec12")
        XCTAssertTrue(seeded, "semear aprovacao com segredo falso")
        // O servidor real diz answerable:false para o comando com trecho redigido.
        let ok = await E2E.eventually {
            guard let (code, json) = await E2E.call("GET", "/api/v1/inbox"), code == 200,
                  let items = json["items"] as? [[String: Any]],
                  let it = items.first(where: { ($0["summary"] as? String)?.contains("esec12") == true }) else { return false }
            return (it["answerable"] as? Bool) == false
        }
        XCTAssertTrue(ok, "servidor deveria marcar o item redigido como answerable:false")
        let app = try launchConnected()
        app.tabBars.buttons["Agentes"].tap()
        let row = element(app, containing: "esec12")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "pedido redigido na aba Agentes")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["inbox-nao-respondivel"].waitForExistence(timeout: 10), "aviso Responda no terminal")
        attach(app, "e2e-12-sheet-nao-respondivel")
        XCTAssertFalse(app.buttons["Uma vez"].exists, "Uma vez nao pode aparecer")
        XCTAssertFalse(app.buttons["Sempre"].exists, "Sempre nao pode aparecer")
        // Neste hook (qwen) o item nao tem request_id: sem Negar tambem. Nada a aprovar.
        XCTAssertFalse(app.buttons["Aprovar"].exists)
    }
}
