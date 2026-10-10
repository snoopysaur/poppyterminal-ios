import Foundation

/// O que a sheet da caixa de entrada sabe do prompt carregado (`/prompt`).
public struct SheetPromptSnapshot: Sendable, Equatable {
    public var found: Bool
    public var answerable: Bool
    public var optionLabels: [String]
    public init(found: Bool = true, answerable: Bool = true, optionLabels: [String] = []) {
        self.found = found; self.answerable = answerable; self.optionLabels = optionLabels
    }
}

/// Quais botoes a sheet mostra. Logica pura (testada em PoppyKit); a View so desenha.
public struct InboxSheetPlan: Sendable, Equatable {
    /// O app pode aprovar/responder agora.
    public var canAnswer: Bool
    /// O prompt carregado diz que nao da (rotulo redigido/cortado), mesmo que o item diga sim.
    public var promptBlocksAnswer: Bool
    /// Aviso "Responda no terminal".
    public var showNotice: Bool
    /// O item sumiu da caixa de entrada: nada a responder.
    public var itemGone: Bool
    public var showApprove: Bool
    public var showAlways: Bool
    public var showAlwaysScope: Bool
    public var showDeny: Bool
    /// Botoes de resposta de ask/question (vazio quando nao da para responder).
    public var optionButtons: [String]
}

public enum InboxSheetLogic {
    /// `item == nil`: o item nao esta mais na store (nao reabre com `answerable` velho).
    public static func plan(item: InboxItem?, prompt: SheetPromptSnapshot?, humanActions: Bool,
                            needsAnswer: Bool) -> InboxSheetPlan {
        guard let item else {
            return InboxSheetPlan(canAnswer: false, promptBlocksAnswer: false, showNotice: true, itemGone: true,
                                  showApprove: false, showAlways: false, showAlwaysScope: false,
                                  showDeny: false, optionButtons: [])
        }
        let blocks = promptBlocksAnswer(kind: item.kind, prompt: prompt)
        let can = item.answerable && !blocks
        let notice = humanActions && !can && needsAnswer
        let isApproval = item.kind == .approval
        let deny = humanActions
            && (can ? isApproval : ((isApproval || item.kind == .plan) && item.requestId != nil))
        let approve = humanActions && can && isApproval
        let always = approve && item.offersAlways
        var options: [String] = []
        if humanActions, can, item.kind == .ask || item.kind == .question {
            options = item.options.isEmpty ? (prompt?.optionLabels ?? []) : item.options
        }
        return InboxSheetPlan(canAnswer: can, promptBlocksAnswer: blocks, showNotice: notice, itemGone: false,
                              showApprove: approve, showAlways: always,
                              showAlwaysScope: always && !item.alwaysScope.isEmpty,
                              showDeny: deny, optionButtons: options)
    }

    /// Aprovacao, ask e question: um prompt com `found && !answerable` bloqueia a resposta.
    public static func promptBlocksAnswer(kind: InboxKind, prompt: SheetPromptSnapshot?) -> Bool {
        guard kind == .approval || kind == .ask || kind == .question else { return false }
        return prompt.map { $0.found && !$0.answerable } == true
    }

    /// Re-checagem no momento da acao: so Negar passa quando nao ha como responder.
    public static func allows(_ decision: ReplyDecision, canAnswer: Bool) -> Bool {
        // v0.4: "Sempre" nao existe no app (o servidor responde 403 always_disabled); nunca passa, nem com `always` em options.
        if decision == .always { return false }
        return canAnswer || decision == .deny
    }

    /// Erros que pedem recarregar caixa + prompt sem fechar a sheet.
    public static func reloadsAfter(_ kind: APIError.Kind) -> Bool {
        kind == .promptChanged || kind == .notAnswerable
    }
}
