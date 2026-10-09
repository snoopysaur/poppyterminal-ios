import XCTest
@testable import PoppyKit

/// v0.3.2: `answerable` no item da inbox, `reason` do hold_ended e o aviso certo do pending_prompt.
/// Os fixtures seguem o contrato do servidor v0.3.2 (mesmos nomes: `answerable`, `reason`).
final class V032Tests: XCTestCase {
    private func parse(_ file: String) throws -> APIError {
        APIError.parse(status: 409, body: try Fixture.data(file), retryAfter: nil)
    }

    // MARK: answerable

    func testItemNaoRespondivelDoServidor() throws {
        let r = try Fixture.decode(InboxResponse.self, "inbox_nao_respondivel.json")
        XCTAssertEqual(r.items.count, 2)
        XCTAssertEqual(r.items[0].answerableRaw, false)
        XCTAssertFalse(r.items[0].answerable)
        XCTAssertNil(r.items[0].requestId)
        XCTAssertEqual(r.items[1].answerableRaw, true)
        XCTAssertTrue(r.items[1].answerable)
    }

    func testServidorAntigoCaiNoFallback() throws {
        // inbox.json (v0.3.0/0.3.1) nao tem `answerable`.
        let r = try Fixture.decode(InboxResponse.self, "inbox.json")
        XCTAssertTrue(r.items.allSatisfy { $0.answerableRaw == nil })
        XCTAssertTrue(r.items[0].answerable, "aprovacao com request_id e opcoes")
        XCTAssertTrue(r.items[1].answerable, "pergunta com request_id e opcoes")
        XCTAssertTrue(r.items[2].answerable, "finished nao pede resposta")
        let semHold = InboxItem(id: "1", kind: "approval", options: [], requestId: nil)
        XCTAssertFalse(semHold.answerable)
        let semOpcoes = InboxItem(id: "2", kind: "approval", options: [], requestId: "abc")
        XCTAssertFalse(semOpcoes.answerable)
        let semRequest = InboxItem(id: "3", kind: "ask", options: ["sim"], requestId: nil)
        XCTAssertFalse(semRequest.answerable)
        XCTAssertTrue(InboxItem(id: "4", kind: "plan").answerable)
    }

    func testCampoDoServidorVenceOFallback() {
        // Servidor diz que da para responder mesmo sem os campos antigos, e o inverso.
        XCTAssertTrue(InboxItem(id: "1", kind: "approval", answerable: true).answerable)
        XCTAssertFalse(InboxItem(id: "2", kind: "approval", options: ["once"], requestId: "r", answerable: false).answerable)
    }

    func testPendenteSegueOCampoOuOItem() {
        let semCampo = PendingPrompt(inboxId: "219", kind: "approval")
        XCTAssertTrue(semCampo.isAnswerable(item: nil), "item ainda nao chegou: vale tentar")
        let item = InboxItem(id: "219", kind: "approval")
        XCTAssertFalse(semCampo.isAnswerable(item: item))
        let doServidor = PendingPrompt(inboxId: "219", kind: "approval", answerable: true)
        XCTAssertTrue(doServidor.isAnswerable(item: item))
        let naoDoServidor = PendingPrompt(inboxId: "219", kind: "approval", answerable: false)
        XCTAssertFalse(naoDoServidor.isAnswerable(item: InboxItem(id: "219", kind: "approval", answerable: true)))
    }

    func testPendenteComAnswerableDecodificaDoChat() throws {
        let json = #"{"inbox_id":"7","kind":"approval","summary":"x","answerable":false}"#
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let p = try d.decode(PendingPrompt.self, from: Data(json.utf8))
        XCTAssertEqual(p.answerable, false)
        // sem o campo (servidor antigo) continua como antes
        let antigo = try Fixture.decode(ChatPage.self, "chat_pendente.json")
        XCTAssertNil(antigo.pending?.answerable)
    }

    // MARK: hold_ended + reason

    func testHoldEndedGuardaOMotivo() throws {
        let casos: [(String, APIError.HoldEndedReason)] = [
            ("erro_hold_ended_disabled.json", .disabled),
            ("erro_hold_ended_timeout.json", .timeout),
            ("erro_hold_ended_answered.json", .answered),
            ("erro_hold_ended_gone.json", .gone),
        ]
        for (file, reason) in casos {
            let e = try parse(file)
            XCTAssertEqual(e.kind, .holdEnded, file)
            XCTAssertEqual(e.holdEndedReason, reason, file)
        }
    }

    func testHoldEndedSemMotivoNaoDizExpirou() throws {
        let e = try parse("erro_hold_ended.json")
        XCTAssertEqual(e.kind, .holdEnded)
        XCTAssertEqual(e.holdEndedReason, .unknown)
        XCTAssertNil(e.reasonRaw)
        XCTAssertFalse(e.userMessage.lowercased().contains("expir"))
        let estranho = APIError.api(status: 409, code: "hold_ended", message: "", retryAfter: nil, reason: "algo-novo")
        XCTAssertEqual(estranho.holdEndedReason, .unknown)
    }

    func testExpirouSoQuandoOMotivoEhTimeout() throws {
        let todos = ["erro_hold_ended_disabled.json", "erro_hold_ended_timeout.json",
                     "erro_hold_ended_answered.json", "erro_hold_ended_gone.json", "erro_hold_ended.json"]
        for file in todos {
            let e = try parse(file)
            let diz = e.userMessage.lowercased().contains("expir")
            XCTAssertEqual(diz, e.holdEndedReason == .timeout, "\(file): \(e.userMessage)")
        }
        XCTAssertTrue(try parse("erro_hold_ended_disabled.json").userMessage.contains("terminal"))
    }

    func testReasonNoTopoDoCorpoTambemVale() {
        let body = Data(#"{"reason":"disabled","error":{"code":"hold_ended","message":"m"}}"#.utf8)
        let e = APIError.parse(status: 409, body: body, retryAfter: nil)
        XCTAssertEqual(e.holdEndedReason, .disabled)
    }

    // MARK: pending_prompt

    func testPendingPromptSemCartaoRespondivelDizOAvisoCerto() throws {
        let e = try parse("erro_pending_prompt.json")
        XCTAssertEqual(e.kind, .pendingPrompt)
        XCTAssertEqual(e.userMessage, "Responda o pedido pendente antes de enviar.")
        XCTAssertEqual(e.pendingMessage(answerable: true), e.userMessage)
        let sem = e.pendingMessage(answerable: false)
        XCTAssertTrue(sem.contains("terminal"))
        XCTAssertTrue(sem.contains("Atualize"))
        XCTAssertFalse(sem.lowercased().contains("cartão"))
        XCTAssertFalse(sem.lowercased().contains("expir"))
    }

    func testOutrosErrosNaoMudamComPendingAnswerable() throws {
        let e = try parse("erro_agent_gone.json")
        XCTAssertEqual(e.pendingMessage(answerable: false), e.userMessage)
    }
}
