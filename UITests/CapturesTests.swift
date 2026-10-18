import XCTest

/// Capturas de tela para a critica de design (A6): percorre as telas SEM agir (so olha) contra o
/// servidor semeado. O CI roda isto uma vez por variante (SE, 16 Pro, escuro, AX3, paisagem),
/// passando `TEST_RUNNER_CAPTURE_TAG` e, para paisagem, `TEST_RUNNER_CAPTURE_ORIENTATION=landscape`.
/// Sem `E2E_URL` o teste e pulado.
@MainActor
final class CapturesTests: XCTestCase {
    private var tag: String { ProcessInfo.processInfo.environment["CAPTURE_TAG"] ?? "local" }

    private var landscape: Bool { ProcessInfo.processInfo.environment["CAPTURE_ORIENTATION"] == "landscape" }

    private func shot(_ app: XCUIApplication, _ name: String) {
        sleep(1)
        if landscape && XCUIDevice.shared.orientation.isLandscape {
            // `app.screenshot()` sai girada e cortada em paisagem no Simulator. A da tela inteira vem
            // completa, so girada 90 graus (sufixo "-tela"): scripts/export_shots.sh desgira ao exportar.
            let tela = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            tela.name = "\(tag)-\(name)-tela"
            tela.lifetime = .keepAlways
            add(tela)
        } else {
            attach(app, "\(tag)-\(name)")
        }
    }

    func testCapturaDasTelas() async throws {
        continueAfterFailure = true
        let app = try launchConnected()
        if ProcessInfo.processInfo.environment["CAPTURE_ORIENTATION"] == "landscape" {
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(1)
        }

        // Sessoes
        app.tabBars.buttons["Sessões"].tap()
        XCTAssertTrue(element(app, containing: E2E.session).waitForExistence(timeout: 20))
        shot(app, "01-sessoes")

        // Detalhe da sessao
        element(app, containing: E2E.session).tap()
        XCTAssertTrue(app.buttons["btn-nova-janela"].waitForExistence(timeout: 10))
        shot(app, "02-detalhe-sessao")

        // Nova janela (so abre a sheet e fecha)
        app.buttons["btn-nova-janela"].tap()
        if app.textFields["field-nome-janela"].waitForExistence(timeout: 5) {
            shot(app, "03-nova-janela")
            app.buttons["Cancelar"].tap()
        }

        // Terminal na janela beta (foco so do celular)
        let beta = element(app, containing: "beta")
        if beta.waitForExistence(timeout: 10) {
            beta.tap()
            if app.descendants(matching: .any)["terminal"].waitForExistence(timeout: 15) {
                sleep(3)
                // Aviso de "digitar deslizando" do teclado (so na primeira vez no Simulator) cobre a barra.
                for host in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
                    let continuar = host.buttons["Continue"]
                    if continuar.exists { continuar.tap(); sleep(1) }
                }
                shot(app, "04-terminal")
                app.buttons["btn-voltar-terminal"].tap()
            }
        }

        // Chat da janela com Claude (v0.3.0)
        let chatRow = element(app, containing: E2E.chatWindow)
        if chatRow.waitForExistence(timeout: 10) {
            chatRow.tap()
            if app.descendants(matching: .any)["chat-field"].waitForExistence(timeout: 20) {
                sleep(2)
                shot(app, "04b-chat")
                if app.buttons["chat-show-terminal"].exists {
                    app.buttons["chat-show-terminal"].tap()
                    sleep(3)
                    shot(app, "04c-chat-terminal-celular")
                }
                if app.buttons["btn-voltar-terminal"].exists { app.buttons["btn-voltar-terminal"].tap() }
            }
        }

        _ = await E2E.seed("approval", tag: "ecap7")
        // Agentes
        app.tabBars.buttons["Agentes"].tap()
        sleep(1)
        shot(app, "05-agentes")
        let approval = element(app, containing: "ecap7")
        if approval.waitForExistence(timeout: 20) {
            approval.tap()
            // O pedido "ecap7" fica na janela beta (o motor guarda um item por janela e o seeder zera o
            // estado antes). Se "Uma vez" nao aparecer, a captura sai mesmo assim, como diagnostico.
            let uma = app.buttons["Uma vez"].waitForExistence(timeout: 15)
            shot(app, uma ? "06-sheet-aprovacao" : "06-sheet-aprovacao-SEM-UMA-VEZ")
            XCTAssertTrue(uma, "sheet de aprovacao do ecap7 sem o botao Uma vez")
            // Fecha sem agir.
            if app.buttons["Fechar"].exists { app.buttons["Fechar"].tap() }
        } else {
            XCTFail("pedido ecap7 nao apareceu na aba Agentes")
        }

        // Item REAL nao respondivel (v0.3.2 r2): o comando tem um "segredo" falso, o servidor
        // redige e manda answerable:false. Sem Uma vez/Sempre; Negar segue.
        if await E2E.seed("approval", tag: "esec7") {
            app.tabBars.buttons["Agentes"].tap()
            let sec = element(app, containing: "esec7")
            if sec.waitForExistence(timeout: 15) {
                sec.tap()
                if app.descendants(matching: .any)["inbox-nao-respondivel"].waitForExistence(timeout: 10) {
                    shot(app, "06b-sheet-nao-respondivel-real")
                }
                // Limpa: Negar libera o hold (nao aprova nada).
                if app.buttons["Negar"].exists { app.buttons["Negar"].tap() } else if app.buttons["Fechar"].exists { app.buttons["Fechar"].tap() }
            }
        }

        // Ajustes
        app.tabBars.buttons["Ajustes"].tap()
        shot(app, "07-ajustes")

        // Licencas e icone do app (onda 3)
        for (id, nome) in [("linha-licencas", "07b-licencas"), ("linha-icone", "07c-icone-do-app")] {
            let linha = app.descendants(matching: .any)[id]
            var tries = 0
            while !(linha.exists && linha.isHittable) && tries < 8 { app.swipeUp(); tries += 1 }
            if linha.exists && linha.isHittable {
                linha.tap()
                sleep(1)
                shot(app, nome)
                if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
            }
        }
    }

    // MARK: estados (revisao B, S9f): travado, 404 de deep link, inbox vazia, erro de conexao

    private func byID(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func orient() {
        if ProcessInfo.processInfo.environment["CAPTURE_ORIENTATION"] == "landscape" {
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(1)
        }
    }

    /// App travado (Face ID recusado): so a tela de trava, sem abas.
    func testCapturaEstadoTravado() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-skip-notification-prompt", "-auth-stub", "deny", "-serverURL", "https://poppy-teste.example"]
        app.launch()
        orient()
        XCTAssertTrue(byID(app, "lock-view").waitForExistence(timeout: 15), "tela de trava")
        XCTAssertTrue(byID(app, "lock-mensagem").waitForExistence(timeout: 10), "mensagem de falha")
        shot(app, "08-estado-travado")
    }

    /// Sem servidor (porta recusa na hora): aba Agentes mostra o erro de conexao.
    func testCapturaEstadoErroDeConexao() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-skip-notification-prompt", "-auth-stub", "allow", "-serverURL", "http://127.0.0.1:9"]
        app.launch()
        orient()
        XCTAssertTrue(app.tabBars.buttons["Agentes"].waitForExistence(timeout: 15), "abas")
        app.tabBars.buttons["Agentes"].tap()
        XCTAssertTrue(app.buttons["Tentar de novo"].waitForExistence(timeout: 20), "estado de erro com Tentar de novo")
        shot(app, "09-estado-erro-conexao")
    }

    /// Inbox vazia ("Tudo em dia"): o catalogo de design mostra o EmptyStateView em cada tipo.
    func testCapturaEstadoInboxVazia() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-design-catalog"]
        app.launch()
        orient()
        let title = element(app, containing: "Tudo em dia")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 15), "catalogo")
        var tries = 0
        while !title.isHittable && tries < 25 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(title.exists, "estado Tudo em dia no catalogo")
        shot(app, "10-estado-inbox-vazia")
    }

    /// Deep link para um item que o servidor nao conhece (404): so navega para a aba Agentes.
    func testCapturaEstadoDeepLink404() async throws {
        continueAfterFailure = true
        let app = try launchConnected()
        orient()
        XCTAssertTrue(app.tabBars.buttons["Sessões"].isSelected, "comeca em Sessões")
        app.open(URL(string: "poppyterminal://inbox/00112233445566778899aabbccddeeff")!)
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
        if alert.waitForExistence(timeout: 3) { alert.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["deeplink-ms"].waitForExistence(timeout: 15), "link tratado")
        XCTAssertTrue(app.tabBars.buttons["Agentes"].isSelected, "404 cai na aba Agentes")
        shot(app, "11-estado-deeplink-404")
    }

    /// Paisagem desgirada (plano v0.5 visual, onda 0): gira para paisagem e volta para retrato,
    /// para pegar layout preso em paisagem. So roda na variante de paisagem.
    func testCapturaPaisagemDesgirada() async throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_ORIENTATION"] == "landscape",
                          "so na variante de paisagem")
        let app = try launchConnected()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        app.tabBars.buttons["Agentes"].tap()
        shot(app, "12-agentes-paisagem")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        shot(app, "13-agentes-desgirada")
        app.tabBars.buttons["Ajustes"].tap()
        shot(app, "14-ajustes-desgirada")
    }
}
