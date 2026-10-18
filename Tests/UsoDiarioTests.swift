import XCTest
import UIKit
@testable import PoppyTerminal

/// Onda de uso diario da v0.5: segurar para aprovar, ditado e esmaecido da barra de teclas.
@MainActor
final class UsoDiarioTests: XCTestCase {
    // MARK: segurar 0,8 s

    func testSegurarMenosDeOitoDecimosNaoAprova() {
        XCTAssertFalse(HoldPolicy.completes(elapsed: 0))
        XCTAssertFalse(HoldPolicy.completes(elapsed: 0.3))
        XCTAssertFalse(HoldPolicy.completes(elapsed: 0.79))
        XCTAssertFalse(HoldPolicy.completes(elapsed: 0.799))
    }

    func testSegurarOitoDecimosOuMaisAprova() {
        XCTAssertTrue(HoldPolicy.completes(elapsed: 0.8))
        XCTAssertTrue(HoldPolicy.completes(elapsed: 1.5))
    }

    func testTempoDeSegurarEFixoEmOitoDecimos() {
        XCTAssertEqual(Motion.holdToApproveSeconds, 0.8)
        XCTAssertEqual(Motion.holdToApprove, .milliseconds(800))
    }

    func testProgressoVaiDeZeroAUmSemPassar() {
        XCTAssertEqual(HoldPolicy.progress(elapsed: -1), 0)
        XCTAssertEqual(HoldPolicy.progress(elapsed: 0), 0)
        XCTAssertEqual(HoldPolicy.progress(elapsed: 0.4), 0.5, accuracy: 0.0001)
        XCTAssertEqual(HoldPolicy.progress(elapsed: 0.8), 1)
        XCTAssertEqual(HoldPolicy.progress(elapsed: 5), 1)
    }

    func testSoPedidoComRiscoPedeParaSegurar() {
        XCTAssertTrue(HoldPolicy.requiresHold(hasRisk: true))
        XCTAssertFalse(HoldPolicy.requiresHold(hasRisk: false))
    }

    // MARK: ditado

    /// As duas permissoes do ditado precisam existir no Info.plist, em portugues e nao vazias.
    func testPlistTemTextosDeMicrofoneEFala() {
        let info = Bundle.main.infoDictionary
        let mic = info?["NSMicrophoneUsageDescription"] as? String ?? ""
        let fala = info?["NSSpeechRecognitionUsageDescription"] as? String ?? ""
        XCTAssertFalse(mic.isEmpty, "falta NSMicrophoneUsageDescription")
        XCTAssertFalse(fala.isEmpty, "falta NSSpeechRecognitionUsageDescription")
        XCTAssertTrue(mic.localizedCaseInsensitiveContains("microfone"), "texto do microfone em portugues")
        XCTAssertTrue(fala.localizedCaseInsensitiveContains("fala"), "texto da fala em portugues")
    }

    func testDitadoSomaAoTextoSemColarPalavras() {
        XCTAssertEqual(DictationText.merge(base: "", dictated: "ola mundo"), "ola mundo")
        XCTAssertEqual(DictationText.merge(base: "rode", dictated: "os testes"), "rode os testes")
        XCTAssertEqual(DictationText.merge(base: "rode ", dictated: "os testes"), "rode os testes")
        XCTAssertEqual(DictationText.merge(base: "rode", dictated: "  "), "rode")
    }

    /// No terminal o texto ditado vai numa linha so e sem Enter.
    func testDitadoNoTerminalNaoTemQuebraDeLinha() {
        let out = DictationText.forTerminal("ls -la\nrm -rf build\r\n")
        XCTAssertFalse(out.contains("\n"))
        XCTAssertFalse(out.contains("\r"))
        XCTAssertEqual(out, "ls -la rm -rf build")
    }

    func testDitadoComecaParado() {
        let dictation = DictationController()
        XCTAssertEqual(dictation.state, .idle)
        XCTAssertFalse(dictation.isListening)
        XCTAssertEqual(dictation.transcript, "")
    }

    // MARK: barra de teclas

    /// O esmaecido da borda existe, nao recebe toque e vai do fundo transparente ao fundo da barra.
    func testBarraDeTeclasTemEsmaecidoNaBorda() {
        let bar = KeyBarView(send: { _ in })
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: 44)
        bar.layoutIfNeeded()
        let fade = bar.fadeEdge
        XCTAssertNotNil(fade.superview, "esmaecido fora da barra")
        XCTAssertFalse(fade.isUserInteractionEnabled, "o esmaecido nao pode roubar toque")
        let colors = fade.gradientColors
        XCTAssertEqual(colors.count, 2)
        XCTAssertEqual(colors.first?.alpha ?? 1, 0, "comeca transparente")
        XCTAssertEqual(colors.last?.alpha ?? 0, 1, "termina no fundo da barra")
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(cgColor: colors.last!).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        Theme.mantle.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        XCTAssertEqual(r1, r2, accuracy: 0.01, "mesma cor do fundo da barra")
        XCTAssertEqual(g1, g2, accuracy: 0.01)
        XCTAssertEqual(b1, b2, accuracy: 0.01)
        XCTAssertGreaterThan(EdgeFadeView.width, 0)
    }
}
