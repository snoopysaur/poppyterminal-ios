import XCTest

/// Capturas de tela para a critica de design (A6): percorre as telas SEM agir (so olha) contra o
/// servidor semeado. O CI roda isto uma vez por variante (SE, 16 Pro, escuro, AX3, paisagem),
/// passando `TEST_RUNNER_CAPTURE_TAG` e, para paisagem, `TEST_RUNNER_CAPTURE_ORIENTATION=landscape`.
/// Sem `E2E_URL` o teste e pulado.
@MainActor
final class CapturesTests: XCTestCase {
    private var tag: String { ProcessInfo.processInfo.environment["CAPTURE_TAG"] ?? "local" }

    private func shot(_ app: XCUIApplication, _ name: String) {
        sleep(1)
        attach(app, "\(tag)-\(name)")
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
                shot(app, "04-terminal")
                app.buttons["btn-voltar-terminal"].tap()
            }
        }

        // Agentes
        app.tabBars.buttons["Agentes"].tap()
        sleep(1)
        shot(app, "05-agentes")
        let approval = element(app, containing: "go test")
        if approval.waitForExistence(timeout: 10) {
            approval.tap()
            if app.buttons["Uma vez"].waitForExistence(timeout: 10) {
                shot(app, "06-sheet-aprovacao")
            }
            // Fecha sem agir.
            if app.buttons["Fechar"].exists { app.buttons["Fechar"].tap() }
        }

        // Ajustes
        app.tabBars.buttons["Ajustes"].tap()
        shot(app, "07-ajustes")
    }
}
