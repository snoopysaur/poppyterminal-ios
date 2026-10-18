import XCTest

/// Acessibilidade do visual Guild (plano v0.5 visual, onda 2). Nao precisa de servidor:
/// usa o catalogo de design e a sheet real de aprovacao com um pedido de risco fixo (Debug).
@MainActor
final class GuildAccessibilityUITests: XCTestCase {
    /// AX3 no iOS = "Accessibility XL" (AX1 = M, AX2 = L, AX3 = XL).
    private static let ax3 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
    /// Mesmo texto de `DesignCatalog.riskCommand`.
    private static let comando = "Bash: git push --force origin wip/v04-n3b"

    private func launch(_ args: [String], ax3: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-skip-notification-prompt", "-auth-stub", "allow"] + args
        if ax3 { app.launchArguments += Self.ax3 }
        app.launch()
        return app
    }

    private func byID(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Tamanho normal: o titulo usa a letra de pixel. AX3: volta para a letra do sistema.
    func testTituloPixelNoNormalESFNoAX3() throws {
        let normal = launch(["-design-catalog"])
        XCTAssertTrue(byID(normal, "titulo-pixel").waitForExistence(timeout: 15), "titulo em pixel no tamanho normal")
        XCTAssertFalse(byID(normal, "titulo-sf").exists, "controle: no tamanho normal nao e SF")
        normal.terminate()

        let grande = launch(["-design-catalog"], ax3: true)
        XCTAssertTrue(byID(grande, "titulo-sf").waitForExistence(timeout: 15), "titulo em SF no AX3")
        XCTAssertFalse(byID(grande, "titulo-pixel").exists, "no AX3 nao fica pixel")
        shot(grande, "guild-titulo-ax3")
    }

    /// Sheet real com pedido de risco: Negar e Uma vez visiveis SEM rolar, no tamanho normal e no AX3.
    func testNegarEAprovarVisiveisSemRolar() throws {
        for ax3 in [false, true] {
            let app = launch(["-fixture-sheet-risco"], ax3: ax3)
            let uma = app.buttons["inbox-uma-vez"]
            let negar = app.buttons["inbox-negar"]
            XCTAssertTrue(uma.waitForExistence(timeout: 20), "Uma vez (ax3=\(ax3))")
            XCTAssertTrue(negar.exists, "Negar (ax3=\(ax3))")
            let tela = app.windows.firstMatch.frame
            for (nome, b) in [("Uma vez", uma), ("Negar", negar)] {
                XCTAssertTrue(b.isHittable, "\(nome) toca sem rolar (ax3=\(ax3))")
                XCTAssertTrue(tela.contains(b.frame), "\(nome) dentro da tela (ax3=\(ax3)): \(b.frame) em \(tela)")
            }
            shot(app, ax3 ? "guild-sheet-risco-ax3" : "guild-sheet-risco")
            app.terminate()
        }
    }

    /// O comando na tela e IGUAL ao do pedido (hifen, barra, quebra): nada de adorno no texto.
    func testComandoFielNaSheet() throws {
        let app = launch(["-fixture-sheet-risco"])
        let cmd = byID(app, "inbox-comando")
        XCTAssertTrue(cmd.waitForExistence(timeout: 20), "bloco do comando")
        XCTAssertEqual(cmd.label, Self.comando)
    }

    /// Alternativa de acessibilidade (VoiceOver / Controle por Botao, simulada por `-assistive-stub`):
    /// o botao de aprovar abre a confirmacao explicita SEM segurar; confirmando, o pedido e aprovado.
    func testRiscoAindaPedeConfirmacao() throws {
        let app = launch(["-fixture-sheet-risco", "-assistive-stub"])
        let uma = app.buttons["inbox-uma-vez"]
        XCTAssertTrue(uma.waitForExistence(timeout: 20))
        uma.tap()
        let confirmar = app.buttons["Aprovar mesmo assim"]
        XCTAssertTrue(confirmar.waitForExistence(timeout: 10), "dialogo de risco")
        shot(app, "guild-dialogo-risco")
        // O botao de cancelar usa o texto do sistema (muda com o idioma do simulador): nao toca nele.
        confirmar.tap()
        XCTAssertTrue(uma.waitForNonExistence(timeout: 15), "a alternativa de acessibilidade aprova sem segurar")
    }

    // MARK: uso diario (v0.5)

    /// Segurar 0,8 s: toque curto nao aprova (a sheet segue aberta); segurar mais de 0,8 s aprova.
    func testSegurarOitoDecimosAprovaECurtoNao() throws {
        let app = launch(["-fixture-sheet-risco"])
        let uma = app.buttons["inbox-uma-vez"]
        XCTAssertTrue(uma.waitForExistence(timeout: 20))
        XCTAssertTrue(uma.label.contains("Aprovar"), "rotulo falado do botao: \(uma.label)")
        uma.press(forDuration: 0.3)
        XCTAssertFalse(uma.waitForNonExistence(timeout: 2.5), "menos de 0,8 s nao pode aprovar")
        XCTAssertFalse(app.buttons["Aprovar mesmo assim"].exists, "toque curto sem tecnologia assistiva nao abre nada")
        uma.press(forDuration: 1.4)
        XCTAssertTrue(uma.waitForNonExistence(timeout: 15), "segurar mais de 0,8 s aprova")
    }

    /// Negar e sempre um toque so, sem segurar, e tem pelo menos 56 pt de altura (rodape do polegar).
    func testNegarUmToqueEAlturaDeRodape() throws {
        for ax3 in [false, true] {
            let app = launch(["-fixture-sheet-risco"], ax3: ax3)
            let negar = app.buttons["inbox-negar"]
            let uma = app.buttons["inbox-uma-vez"]
            XCTAssertTrue(negar.waitForExistence(timeout: 20), "Negar (ax3=\(ax3))")
            XCTAssertGreaterThanOrEqual(negar.frame.height, 55.5, "Negar com 56 pt ou mais (ax3=\(ax3))")
            XCTAssertGreaterThanOrEqual(uma.frame.height, 55.5, "Aprovar com 56 pt ou mais (ax3=\(ax3))")
            let tela = app.windows.firstMatch.frame
            XCTAssertGreaterThan(negar.frame.midY, tela.height * 0.6, "rodape no terco de baixo da tela (ax3=\(ax3))")
            negar.tap()
            XCTAssertTrue(uma.waitForNonExistence(timeout: 15), "Negar com um toque fecha o pedido (ax3=\(ax3))")
            app.terminate()
        }
    }

    /// Captura com o botao de segurar no meio do progresso (progresso congelado em 50%).
    func testCapturaSegurarNoMeio() throws {
        let app = launch(["-fixture-sheet-risco", "-fixture-hold-meio"], ax3: false)
        XCTAssertTrue(app.buttons["inbox-uma-vez"].waitForExistence(timeout: 20))
        shot(app, "uso-diario-segurar-no-meio")
    }

    /// A explicacao do risco aparece na propria linha da aba Agentes (sem abrir nada); pedido comum nao.
    func testRiscoApareceNaLinhaDaCaixa() throws {
        for ax3 in [false, true] {
            let app = launch(["-fixture-inbox"], ax3: ax3)
            let comRisco = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "Reescreve o histórico")).firstMatch
            XCTAssertTrue(comRisco.waitForExistence(timeout: 20), "explicacao do risco na linha (ax3=\(ax3))")
            XCTAssertTrue(comRisco.label.contains("Risco"), "rotulo Risco junto da explicacao: \(comRisco.label)")
            let comum = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "ls -la")).firstMatch
            XCTAssertTrue(comum.exists, "pedido comum na lista")
            XCTAssertFalse(comum.label.contains("Risco"), "pedido comum nao mostra risco")
            shot(app, ax3 ? "uso-diario-linha-risco-ax3" : "uso-diario-linha-risco")
            app.terminate()
        }
    }

    /// Cabecalho unico: toda tela principal tem UM titulo no padrao `guildScreenTitle`
    /// (pixel no tamanho normal; SF em AX3), com o nome da tela.
    func testCabecalhoUnicoNasTelasPrincipais() throws {
        for ax3 in [false, true] {
            let app = launch(["-serverURL", "http://127.0.0.1:9"], ax3: ax3)
            let id = ax3 ? "titulo-sf" : "titulo-pixel"
            XCTAssertTrue(app.tabBars.buttons["Ajustes"].waitForExistence(timeout: 20), "abas (ax3=\(ax3))")
            for aba in ["Sessões", "Agentes", "Ajustes"] {
                app.tabBars.buttons[aba].tap()
                let titulo = app.descendants(matching: .any).matching(identifier: id).firstMatch
                XCTAssertTrue(titulo.waitForExistence(timeout: 10), "titulo de \(aba) no padrao unico (ax3=\(ax3))")
                XCTAssertEqual(titulo.label, aba, "o titulo da tela \(aba) (ax3=\(ax3))")
                shot(app, "uso-diario-cabecalho-\(aba)\(ax3 ? "-ax3" : "")")
            }
            app.terminate()
        }
    }

    /// O botao de ditado existe no catalogo (no chat ele fica ao lado do campo) e o rodape do polegar
    /// mostra Negar e Aprovar (segurar) lado a lado.
    func testCatalogoMostraDitadoERodapeDoPolegar() throws {
        let app = launch(["-design-catalog"])
        let ditado = app.descendants(matching: .any)["catalogo-ditado"]
        var tries = 0
        while !ditado.exists && tries < 12 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(ditado.exists, "secao do ditado no catalogo")
        XCTAssertTrue(app.descendants(matching: .any)["ditado-botao"].exists, "botao de microfone")
        let hold = app.descendants(matching: .any)["catalogo-hold"]
        XCTAssertTrue(hold.exists, "rodape do polegar com segurar")
        XCTAssertTrue(hold.buttons["inbox-negar"].exists, "Negar no rodape")
        XCTAssertTrue(hold.buttons["inbox-uma-vez"].exists, "Aprovar (segurar) no rodape")
        shot(app, "uso-diario-rodape-e-ditado")
    }
}
