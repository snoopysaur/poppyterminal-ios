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

    func testPrimeiraConexaoSemServidor() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textFields["field-url"].waitForExistence(timeout: 15), "campo de URL na primeira conexao")
        XCTAssertTrue(app.secureTextFields["field-senha"].exists, "campo de senha")
        XCTAssertTrue(app.buttons["btn-conectar"].exists, "botao Conectar")
        XCTAssertFalse(app.buttons["btn-conectar"].isEnabled, "Conectar desligado sem URL valida")
    }
}
