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

    /// Confirmar o risco continua pedindo confirmacao explicita (so o estilo mudou).
    func testRiscoAindaPedeConfirmacao() throws {
        let app = launch(["-fixture-sheet-risco"])
        let uma = app.buttons["inbox-uma-vez"]
        XCTAssertTrue(uma.waitForExistence(timeout: 20))
        uma.tap()
        XCTAssertTrue(app.buttons["Aprovar mesmo assim"].waitForExistence(timeout: 10), "dialogo de risco")
        shot(app, "guild-dialogo-risco")
        app.buttons["Cancelar"].tap()
    }
}
