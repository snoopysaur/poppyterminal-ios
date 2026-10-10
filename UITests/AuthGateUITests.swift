import XCTest

// Face ID (v0.4, S2). Os testes ficam como EXTENSOES de CatalogSmokeTests e E2ETests de proposito:
// o ios.yml so seleciona essas duas classes (-only-testing) e nao pode ser editado sem o escopo
// `workflow` do gh. Assim o CI executa estes testes sem mexer no workflow.
//
// O stub do autenticador existe so em Debug e entra pelo argumento `-auth-stub` (allow, deny,
// unavailable, unlock-only). O endereco entra por `-serverURL` (dominio de argumentos do
// UserDefaults, nada persiste entre testes).

private let configured = ["-serverURL", "https://poppy-teste.example"]

extension CatalogSmokeTests {
    private func launchGate(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-auth-stub", mode] + configured
        app.launch()
        return app
    }

    private func byID(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Face ID falhando: o app abre travado, fica travado e nao mostra as abas.
    func testAuthGate_FalhaMantemTravado() throws {
        let app = launchGate("deny")
        XCTAssertTrue(byID(app, "lock-view").waitForExistence(timeout: 15), "tela de trava")
        XCTAssertTrue(app.buttons["lock-desbloquear"].exists, "botao Desbloquear")
        XCTAssertTrue(byID(app, "lock-mensagem").waitForExistence(timeout: 10), "mensagem de falha")
        app.buttons["lock-desbloquear"].tap()
        XCTAssertTrue(byID(app, "lock-view").exists, "continua travado")
        XCTAssertFalse(app.tabBars.buttons["Sessões"].exists, "as abas nao aparecem travado")
    }

    /// Controle: com o Face ID aceito, a mesma abertura mostra as abas (o teste enxerga a diferenca).
    func testAuthGate_SucessoMostraAsAbas() throws {
        let app = launchGate("allow")
        XCTAssertTrue(app.tabBars.buttons["Sessões"].waitForExistence(timeout: 15), "abas depois de desbloquear")
        XCTAssertFalse(byID(app, "lock-view").exists, "trava some")
    }

    /// Sem Face ID nem senha: abre so para leitura e avisa que as ordens estao bloqueadas.
    func testAuthGate_SemBiometriaNemSenhaAvisa() throws {
        let app = launchGate("unavailable")
        XCTAssertTrue(app.tabBars.buttons["Sessões"].waitForExistence(timeout: 15), "abre para leitura")
        XCTAssertTrue(byID(app, "aviso-ordens-bloqueadas").waitForExistence(timeout: 10), "aviso de ordens bloqueadas")
    }
}

extension E2ETests {
    /// LAContext falhando bloqueia Aprovar: o pedido continua no servidor; Negar nao pede Face ID.
    func test13_FaceIDNegadoNaoAprovaMasNegarFunciona() async throws {
        let seeded = await E2E.seed("approval", tag: "e2e13")
        XCTAssertTrue(seeded, "semear aprovacao")
        let app = try launchConnected(extraArgs: ["-auth-stub", "unlock-only"])
        app.tabBars.buttons["Agentes"].tap()
        let row = element(app, containing: "e2e13")
        XCTAssertTrue(row.waitForExistence(timeout: 20), "pedido na aba Agentes")
        row.tap()
        let once = app.buttons["Uma vez"]
        XCTAssertTrue(once.waitForExistence(timeout: 10), "botao Uma vez")
        once.tap()
        attach(app, "e2e-13-faceid-negado")
        let stillThere = await E2E.holds(4) {
            await E2E.inboxSummaries().contains(where: { $0.contains("e2e13") })
        }
        XCTAssertTrue(stillThere, "sem Face ID o pedido NAO pode ser aprovado")
        // Negar nao pede Face ID (o stub recusa qualquer ordem depois do desbloqueio).
        let deny = app.buttons["Negar"]
        XCTAssertTrue(deny.waitForExistence(timeout: 10), "botao Negar")
        deny.tap()
        let gone = await E2E.eventually { !(await E2E.inboxSummaries().contains(where: { $0.contains("e2e13") })) }
        XCTAssertTrue(gone, "Negar deve valer sem Face ID")
    }
}
