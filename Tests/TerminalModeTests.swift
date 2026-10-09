import XCTest
@testable import PoppyTerminal

@MainActor
final class TerminalModeTests: XCTestCase {
    /// Matriz completa: so (chat, humanActions, janela.chat) todos verdadeiros abre em Chat.
    func testMatrizDeCondicoes() {
        for supports in [false, true] {
            for human in [false, true] {
                for windowChat in [false, true] {
                    let expected: TerminalViewMode = (supports && human && windowChat) ? .chat : .terminal
                    XCTAssertEqual(
                        TerminalPolicy.defaultMode(supportsChat: supports, humanActions: human, windowChat: windowChat),
                        expected, "supports=\(supports) human=\(human) windowChat=\(windowChat)")
                    XCTAssertEqual(
                        TerminalPolicy.mode(choice: nil, supportsChat: supports, humanActions: human, windowChat: windowChat),
                        expected)
                }
            }
        }
    }

    /// A escolha da pessoa vale com chat disponivel; sem chat, nunca forca o Chat.
    func testEscolhaDaPessoa() {
        XCTAssertEqual(TerminalPolicy.mode(choice: .terminal, supportsChat: true, humanActions: true, windowChat: true), .terminal)
        XCTAssertEqual(TerminalPolicy.mode(choice: .chat, supportsChat: true, humanActions: true, windowChat: true), .chat)
        XCTAssertEqual(TerminalPolicy.mode(choice: .chat, supportsChat: false, humanActions: true, windowChat: true), .terminal)
        XCTAssertEqual(TerminalPolicy.mode(choice: .chat, supportsChat: true, humanActions: false, windowChat: true), .terminal)
        XCTAssertEqual(TerminalPolicy.mode(choice: .chat, supportsChat: true, humanActions: true, windowChat: false), .terminal)
    }

    func testMemoriaPorJanela() {
        let memory = TerminalModeMemory()
        XCTAssertNil(memory.choice(session: "poppy", window: "1"))
        memory.set(.terminal, session: "poppy", window: "1")
        XCTAssertEqual(memory.choice(session: "poppy", window: "1"), .terminal)
        XCTAssertNil(memory.choice(session: "poppy", window: "2"))
        XCTAssertNil(memory.choice(session: "outra", window: "1"))
    }

    func testFonteCabeNasColunas() {
        // 360 pt, 100 colunas: 360 / 60 = 6 exato.
        XCTAssertEqual(TerminalFit.fontSize(width: 360, cols: 100), 6)
        // 390 pt, 40 colunas: 390 / 24 = 16,25 -> teto 14.
        XCTAssertEqual(TerminalFit.fontSize(width: 390, cols: 40), 14)
        // 390 pt, 50 colunas: 390 / 30 = 13 exato.
        XCTAssertEqual(TerminalFit.fontSize(width: 390, cols: 50), 13)
        // 390 pt, 60 colunas: 390 / 36 = 10,83 -> floor 10.
        XCTAssertEqual(TerminalFit.fontSize(width: 390, cols: 60), 10)
        // Muitas colunas: piso 6.
        XCTAssertEqual(TerminalFit.fontSize(width: 390, cols: 200), 6)
        // Girado (paisagem): mais largura, fonte maior.
        XCTAssertEqual(TerminalFit.fontSize(width: 844, cols: 100), 14)
        XCTAssertEqual(TerminalFit.fontSize(width: 844, cols: 120), 11)
    }

    func testFonteSemColunasFicaComoHoje() {
        XCTAssertNil(TerminalFit.fontSize(width: 390, cols: 0))
        XCTAssertNil(TerminalFit.fontSize(width: 390, cols: -3))
        XCTAssertNil(TerminalFit.fontSize(width: 0, cols: 80))
    }
}
