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
        // Fixture do servidor (rodada 2): 219 false, 220 true, 221 false, 222 false, 223 true, 224 false.
        let r = try Fixture.decode(InboxResponse.self, "inbox_nao_respondivel.json")
        XCTAssertEqual(r.items.map(\.id), ["219", "220", "221", "222", "223", "224"])
        XCTAssertEqual(r.items.map(\.answerableRaw), [false, true, false, false, true, false])
        XCTAssertEqual(r.items.map(\.answerable), [false, true, false, false, true, false])
        XCTAssertNil(r.items[0].requestId)
    }

    /// Item 221: tem request_id e options (once/deny) mas o servidor diz false (summary redigido).
    /// O fallback request_id+options NAO pode reabrir Aprovar. Controle negativo: se `answerable`
    /// voltar a ignorar `answerableRaw == false`, este teste falha.
    func testRequestIdMaisOptionsNaoReabreQuandoServidorDizFalse() throws {
        let r = try Fixture.decode(InboxResponse.self, "inbox_nao_respondivel.json")
        let i221 = try XCTUnwrap(r.items.first { $0.id == "221" })
        XCTAssertNotNil(i221.requestId)
        XCTAssertFalse(i221.options.isEmpty)
        XCTAssertFalse(i221.answerable)
        XCTAssertTrue(i221.summary.contains("[REDIGIDO]"))
        // O mesmo item sem o campo (servidor antigo) cai no fallback e seria respondivel:
        // prova de que e o `false` do servidor que manda.
        let semCampo = InboxItem(id: "221", kind: "approval", options: ["once", "deny"], requestId: "cc33dd44")
        XCTAssertTrue(semCampo.answerable)
        let comFalse = InboxItem(id: "221", kind: "approval", options: ["once", "deny"], requestId: "cc33dd44", answerable: false)
        XCTAssertFalse(comFalse.answerable)
    }

    func testCartaoPendenteComItemFalseNaoReabre() {
        let item = InboxItem(id: "221", kind: "approval", options: ["once", "deny"], requestId: "cc33dd44", answerable: false)
        // Mesmo que o cartao do chat diga true, o `false` do item (palavra final) vence.
        XCTAssertFalse(PendingPrompt(inboxId: "221", kind: "approval", answerable: true).isAnswerable(item: item))
        XCTAssertFalse(PendingPrompt(inboxId: "221", kind: "approval").isAnswerable(item: item))
        XCTAssertFalse(PendingPrompt(inboxId: "221", kind: "approval", answerable: false)
            .isAnswerable(item: InboxItem(id: "221", kind: "approval", options: ["once"], requestId: "r", answerable: true)))
    }

    /// Rodada 3: plano nunca desenha Aprovar/Sempre, mesmo que o campo diga true ou falte.
    /// Controle negativo: sem a guarda `kind == .plan`, este teste falha.
    func testPlanoNuncaEhRespondivel() {
        XCTAssertFalse(InboxItem(id: "p", kind: "plan", requestId: "r", answerable: true).answerable)
        XCTAssertFalse(InboxItem(id: "p", kind: "plan", options: ["once", "always", "deny"], requestId: "r").answerable)
        XCTAssertFalse(InboxItem(id: "p", kind: "plan", requestId: "r", answerable: false).answerable)
        let item = InboxItem(id: "p", kind: "plan", requestId: "r", answerable: true)
        XCTAssertFalse(PendingPrompt(inboxId: "p", kind: "plan", answerable: true).isAnswerable(item: item))
        XCTAssertFalse(PendingPrompt(inboxId: "p", kind: "plan").isAnswerable(item: nil))
        // pergunta continua respondivel quando o servidor diz true
        XCTAssertTrue(InboxItem(id: "q", kind: "ask", options: ["sim"], requestId: "r", answerable: true).answerable)
    }

    // MARK: Sempre some de options

    /// Controle negativo: se `offersAlways` voltar a ser sempre true, o teste do 221 falha.
    func testSempreSomeQuandoNaoEstaEmOptions() throws {
        let r = try Fixture.decode(InboxResponse.self, "inbox_nao_respondivel.json")
        let i220 = try XCTUnwrap(r.items.first { $0.id == "220" })
        XCTAssertTrue(i220.offersAlways, "220 oferece once/always/deny")
        let i221 = try XCTUnwrap(r.items.first { $0.id == "221" })
        XCTAssertEqual(i221.options, ["once", "deny"])
        XCTAssertFalse(i221.offersAlways, "options sem always: sem botao Sempre")
        let semAlways = InboxItem(id: "1", kind: "approval", options: ["once", "deny"], requestId: "r", answerable: true)
        XCTAssertFalse(semAlways.offersAlways)
        XCTAssertTrue(InboxItem(id: "2", kind: "approval", options: ["once", "always", "deny"], requestId: "r", answerable: true).offersAlways)
    }

    // MARK: SSE redigido

    func testAttentionNaoDependeDaOrdemDasChaves() throws {
        var p = SSEParser()
        var evs = p.feed(try Fixture.data("events_sse.txt"))
        evs += p.finish()
        let a = ServerEvent(evs[1])  // chaves reordenadas pelo servidor
        XCTAssertEqual(a.kind, .attention)
        XCTAssertEqual(a.seq, 44)
        XCTAssertEqual(a.attentionID, "20")
        XCTAssertEqual(a.attentionKind, "approval")
        XCTAssertEqual(a.session, "poppy")
        XCTAssertEqual(a.action, "open")
        // outra ordem, mesmo evento
        var q = SSEParser()
        var outro = q.feed(try Fixture.data("events_sse_attention_unreadable.txt"))
        outro += q.finish()
        let b = ServerEvent(outro[1])
        XCTAssertEqual(b.attentionID, "221")
        XCTAssertEqual(b.attentionKind, "approval")
        XCTAssertEqual(b.seq, 61)
    }

    func testGapAttentionUnreadableMandaRebuscarAInbox() throws {
        var p = SSEParser()
        var evs = p.feed(try Fixture.data("events_sse_attention_unreadable.txt"))
        evs += p.finish()
        XCTAssertEqual(evs.map(\.event), ["ready", "attention", "gap"])
        var cursor = EventCursor()
        XCTAssertEqual(cursor.apply(evs[0]), .ready(replayed: 0))
        XCTAssertEqual(cursor.apply(evs[1]), .event)
        let gap = ServerEvent(evs[2])
        XCTAssertEqual(gap.kind, .gap)
        XCTAssertEqual(gap.reason, "attention_unreadable")
        XCTAssertEqual(cursor.apply(evs[2]), .refetch)
    }

    func testPromptComRotuloRedigidoNaoEhRespondivel() throws {
        let p = try Fixture.decode(PromptInfo.self, "prompt_rotulo_redigido.json")
        XCTAssertTrue(p.found)
        XCTAssertFalse(p.answerable)
        XCTAssertTrue(p.options.contains { $0.label.contains("[REDIGIDO]") })
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
        XCTAssertFalse(InboxItem(id: "4", kind: "plan").answerable, "plano nunca e respondivel pelo app")
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

    func testCodigosNovosDoReply() throws {
        let na = try parse("erro_not_answerable.json")
        XCTAssertEqual(na.kind, .notAnswerable)
        XCTAssertTrue(na.userMessage.contains("aprove no terminal"))
        XCTAssertTrue(na.userMessage.contains("Negar pelo app continua valendo"))
        let na2 = try parse("erro_not_answerable_v032r2.json")
        XCTAssertEqual(na2.kind, .notAnswerable)
        let pc2 = try parse("erro_prompt_changed_v032r2.json")
        XCTAssertEqual(pc2.kind, .promptChanged)
        XCTAssertTrue(pc2.userMessage.contains("Recarreguei"))
        let pc = try parse("erro_prompt_changed_v032.json")
        XCTAssertEqual(pc.kind, .promptChanged)
        XCTAssertTrue(pc.userMessage.contains("mudou"))
        XCTAssertFalse(pc.userMessage.lowercased().contains("expir"))
    }
}
