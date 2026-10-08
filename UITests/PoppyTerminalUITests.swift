import XCTest

final class PoppyTerminalUITests: XCTestCase {
    @MainActor
    func testScreenshotDaTelaInicial() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["title"].waitForExistence(timeout: 15))
        sleep(2) // deixa o terminal desenhar
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "tela-inicial"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
