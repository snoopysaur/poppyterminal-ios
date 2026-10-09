import XCTest

/// Testes que nao precisam de servidor: catalogo de design (Debug) e a primeira conexao.
@MainActor
final class CatalogSmokeTests: XCTestCase {
    func testCatalogoDeDesignAbre() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-design-catalog"]
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 15), "catalogo de design nao renderizou")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "catalogo-design"
        shot.lifetime = .keepAlways
        add(shot)
    }


    /// v0.3.2: item que o app nao consegue responder (sem request_id) vira cartao informativo:
    /// "Responda no terminal" + "Abrir terminal", sem Aprovar/Uma vez/Sempre/Negar. O catalogo
    /// mostra o cartao respondivel, o informativo e o banner "Atualizar" lado a lado.
    func testItemSemRequestIdNaoMostraAprovar() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-design-catalog"]
        app.launch()
        let info = app.descendants(matching: .any)["chat-pending-info-card"]
        XCTAssertTrue(info.waitForExistence(timeout: 15), "cartao informativo")
        XCTAssertTrue(info.staticTexts["Responda no terminal"].exists, "titulo do cartao informativo")
        XCTAssertFalse(info.staticTexts["Toque para responder"].exists, "nao convida a responder pelo app")
        XCTAssertEqual(info.buttons.count, 1, "so o botao Abrir terminal")
        XCTAssertTrue(info.buttons["chat-pending-abrir-terminal"].exists, "botao Abrir terminal")
        for label in ["Aprovar", "Uma vez", "Sempre", "Negar"] {
            XCTAssertFalse(info.buttons[label].exists, "\(label) nao pode aparecer num item sem request_id")
        }
        // O cartao respondivel continua existindo (controle: o teste enxerga a diferenca).
        XCTAssertTrue(app.descendants(matching: .any)["chat-pending-card"].exists, "cartao respondivel")
        let shot = XCTAttachment(screenshot: info.screenshot())
        shot.name = "cartao-informativo-responda-no-terminal"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// v0.3.2: 409 pending_prompt sem cartao respondivel mostra "Atualizar" e o aviso certo.
    func testBannerAtualizarDoPendingPrompt() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-design-catalog"]
        app.launch()
        let banner = app.descendants(matching: .any)["chat-pending-stale-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "banner do pending_prompt")
        XCTAssertTrue(banner.buttons["chat-erro-atualizar"].exists, "botao Atualizar")
        XCTAssertTrue(banner.buttons["chat-erro-abrir-terminal"].exists, "botao Abrir terminal")
        XCTAssertTrue(banner.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Atualize")).firstMatch.exists,
                      "aviso diz para atualizar")
        XCTAssertFalse(banner.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "expir")).firstMatch.exists,
                       "nunca diz expirou")
        let shot = XCTAttachment(screenshot: banner.screenshot())
        shot.name = "banner-atualizar-pending-prompt"
        shot.lifetime = .keepAlways
        add(shot)
        let tela = XCTAttachment(screenshot: app.screenshot())
        tela.name = "catalogo-pedido-pendente"
        tela.lifetime = .keepAlways
        add(tela)
    }

    func testPrimeiraConexaoSemServidor() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textFields["field-url"].waitForExistence(timeout: 15), "campo de URL na primeira conexao")
        XCTAssertTrue(app.secureTextFields["field-senha"].exists, "campo de senha")
        XCTAssertTrue(app.buttons["btn-conectar"].exists, "botao Conectar")
        XCTAssertFalse(app.buttons["btn-conectar"].isEnabled, "Conectar desligado sem URL valida")
    }
}
