import XCTest
@testable import PoppyKit

/// v0.3.2 r3: decisao pura dos botoes da sheet da caixa de entrada.
final class InboxSheetLogicTests: XCTestCase {
    private func approval(options: [String], requestId: String? = "r1", answerable: Bool? = true,
                          scope: [String] = []) -> InboxItem {
        InboxItem(id: "1", kind: "approval", summary: "Bash: ls", options: options, requestId: requestId,
                  alwaysScope: scope, answerable: answerable)
    }

    private func plan(_ item: InboxItem?, prompt: SheetPromptSnapshot? = nil, human: Bool = true) -> InboxSheetPlan {
        InboxSheetLogic.plan(item: item, prompt: prompt, humanActions: human, needsAnswer: true)
    }

    func testSempreOcultoSemAlwaysNasOptions() {
        let p = plan(approval(options: ["once", "deny"], scope: ["Bash(ls:*)"]))
        XCTAssertTrue(p.showApprove)
        XCTAssertFalse(p.showAlways, "sem always em options")
        XCTAssertFalse(p.showAlwaysScope)
        XCTAssertTrue(p.showDeny)
        XCTAssertFalse(p.showNotice)
    }

    func testControlePositivoComAlways() {
        let p = plan(approval(options: ["once", "always", "deny"], scope: ["Bash(ls:*)"]))
        XCTAssertTrue(p.showApprove)
        XCTAssertTrue(p.showAlways)
        XCTAssertTrue(p.showAlwaysScope)
        XCTAssertTrue(p.showDeny)
    }

    func testServidorNovoComOptionsVaziasNaoOfereceSempre() {
        XCTAssertFalse(approval(options: []).offersAlways)
        // servidor antigo (campo ausente) com options vazia continua oferecendo
        XCTAssertTrue(approval(options: [], answerable: nil).offersAlways)
        XCTAssertFalse(plan(approval(options: [])).showAlways)
    }

    func testNegarContinuaComRequestIdQuandoNaoRespondivel() {
        let p = plan(approval(options: ["once", "always", "deny"], answerable: false))
        XCTAssertFalse(p.canAnswer)
        XCTAssertTrue(p.showNotice)
        XCTAssertFalse(p.showApprove)
        XCTAssertFalse(p.showAlways)
        XCTAssertTrue(p.showDeny, "Negar vale com request_id")
        let sem = plan(approval(options: ["once", "deny"], requestId: nil, answerable: false))
        XCTAssertFalse(sem.showDeny, "sem request_id nao ha o que negar")
        XCTAssertTrue(sem.showNotice)
    }

    func testPlanoNuncaAprovavelMasNegaComRequestId() {
        let plano = InboxItem(id: "p", kind: "plan", requestId: "r", answerable: true)
        let p = plan(plano)
        XCTAssertFalse(p.canAnswer)
        XCTAssertFalse(p.showApprove)
        XCTAssertFalse(p.showAlways)
        XCTAssertTrue(p.showDeny)
        XCTAssertTrue(p.showNotice)
    }

    func testAnswerableFalseSemRequestIdSoAviso() {
        let p = plan(InboxItem(id: "1", kind: "approval", answerable: false))
        XCTAssertTrue(p.showNotice)
        XCTAssertFalse(p.showApprove)
        XCTAssertFalse(p.showDeny)
    }

    func testPromptBlocksAnswerValeParaAprovacaoAskEQuestion() {
        let bloqueia = SheetPromptSnapshot(found: true, answerable: false)
        for k in [InboxKind.approval, .ask, .question] {
            XCTAssertTrue(InboxSheetLogic.promptBlocksAnswer(kind: k, prompt: bloqueia), "\(k)")
        }
        XCTAssertFalse(InboxSheetLogic.promptBlocksAnswer(kind: .plan, prompt: bloqueia))
        XCTAssertFalse(InboxSheetLogic.promptBlocksAnswer(kind: .approval, prompt: nil))
        XCTAssertFalse(InboxSheetLogic.promptBlocksAnswer(kind: .approval, prompt: SheetPromptSnapshot(found: false, answerable: false)))
        XCTAssertFalse(InboxSheetLogic.promptBlocksAnswer(kind: .ask, prompt: SheetPromptSnapshot(found: true, answerable: true)))
    }

    func testPromptRedigidoBloqueiaAprovacaoMasNegarFica() {
        let p = plan(approval(options: ["once", "always", "deny"]),
                     prompt: SheetPromptSnapshot(found: true, answerable: false))
        XCTAssertTrue(p.promptBlocksAnswer)
        XCTAssertFalse(p.canAnswer)
        XCTAssertFalse(p.showApprove)
        XCTAssertFalse(p.showAlways)
        XCTAssertTrue(p.showNotice)
        XCTAssertTrue(p.showDeny)
    }

    func testAskComPromptNaoRespondivelEscondeOpcoes() {
        let ask = InboxItem(id: "a", kind: "ask", options: ["sim", "nao"], requestId: "r", answerable: true)
        XCTAssertEqual(plan(ask).optionButtons, ["sim", "nao"], "controle positivo")
        let p = plan(ask, prompt: SheetPromptSnapshot(found: true, answerable: false, optionLabels: ["sim", "nao"]))
        XCTAssertEqual(p.optionButtons, [])
        XCTAssertTrue(p.showNotice)
        let semOpcoesNoItem = InboxItem(id: "q", kind: "question", requestId: "r", answerable: true)
        let viaPrompt = plan(semOpcoesNoItem, prompt: SheetPromptSnapshot(found: true, answerable: true, optionLabels: ["x"]))
        XCTAssertEqual(viaPrompt.optionButtons, ["x"])
        XCTAssertEqual(plan(ask, human: false).optionButtons, [])
    }

    func testItemForaDaStoreNaoReabreAprovar() {
        let p = plan(nil)
        XCTAssertTrue(p.itemGone)
        XCTAssertTrue(p.showNotice)
        XCTAssertFalse(p.showApprove)
        XCTAssertFalse(p.showDeny)
        XCTAssertFalse(p.canAnswer)
    }

    func testReChecagemNaAcao() {
        XCTAssertFalse(InboxSheetLogic.allows(.once, canAnswer: false))
        XCTAssertFalse(InboxSheetLogic.allows(.always, canAnswer: false))
        XCTAssertFalse(InboxSheetLogic.allows(.ask, canAnswer: false))
        XCTAssertTrue(InboxSheetLogic.allows(.deny, canAnswer: false))
        XCTAssertTrue(InboxSheetLogic.allows(.once, canAnswer: true))
    }

    func testRecargaEmPromptChangedENotAnswerable() {
        XCTAssertTrue(InboxSheetLogic.reloadsAfter(.promptChanged))
        XCTAssertTrue(InboxSheetLogic.reloadsAfter(.notAnswerable))
        XCTAssertFalse(InboxSheetLogic.reloadsAfter(.holdEnded))
        XCTAssertFalse(InboxSheetLogic.reloadsAfter(.rateLimited))
    }

    func testSemTailscaleNaoMostraBotoes() {
        let p = plan(approval(options: ["once", "always", "deny"]), human: false)
        XCTAssertFalse(p.showApprove)
        XCTAssertFalse(p.showDeny)
        XCTAssertFalse(p.showNotice)
    }

    // MARK: cartao informativo do chat

    func testCartaoInformativoOfereceNegarComRequestId() {
        let item = approval(options: ["once", "deny"], answerable: false)
        let pend = PendingPrompt(inboxId: "1", kind: "approval", answerable: false)
        XCTAssertTrue(pend.canDeny(item: item))
        XCTAssertFalse(pend.canDeny(item: approval(options: [], requestId: nil, answerable: false)))
        XCTAssertFalse(pend.canDeny(item: nil))
        XCTAssertFalse(PendingPrompt(inboxId: "1", kind: "ask").canDeny(item: item))
        XCTAssertTrue(PendingPrompt(inboxId: "p", kind: "plan").canDeny(item: InboxItem(id: "p", kind: "plan", requestId: "r")))
    }

    func testItemForaDaStoreNaoEhRespondivelNoCartao() {
        XCTAssertFalse(PendingPrompt(inboxId: "1", kind: "approval").isAnswerable(item: nil))
        XCTAssertFalse(PendingPrompt(inboxId: "1", kind: "approval", answerable: true).isAnswerable(item: nil))
    }
}

/// v0.4 S4: "Sempre" nunca passa pela guarda da sheet, nem com `always` listado em options.
/// Controle negativo: se `allows(.always)` voltar a depender so de `canAnswer`, este teste falha.
final class AlwaysNuncaPassaTests: XCTestCase {
    func testAlwaysNuncaEhPermitido() {
        XCTAssertFalse(InboxSheetLogic.allows(.always, canAnswer: true))
        XCTAssertFalse(InboxSheetLogic.allows(.always, canAnswer: false))
        // controle positivo: Uma vez e Negar continuam
        XCTAssertTrue(InboxSheetLogic.allows(.once, canAnswer: true))
        XCTAssertTrue(InboxSheetLogic.allows(.deny, canAnswer: false))
    }
}
