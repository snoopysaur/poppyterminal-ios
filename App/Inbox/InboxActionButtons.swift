import SwiftUI
import PoppyKit

/// Botoes de resposta da sheet da caixa de entrada, desenhados a partir do `InboxSheetPlan`
/// (decisao pura em PoppyKit). Usado pela sheet real e pelo catalogo de design.
struct InboxActionButtons: View {
    let plan: InboxSheetPlan
    var alwaysScope: [String] = []
    var commandVisible = true
    var onStart: (ReplyDecision) -> Void = { _ in }
    var onDeny: () -> Void = {}
    var onOption: (String) -> Void = { _ in }

    var body: some View {
        if plan.showApprove {
            Button { onStart(.once) } label: { Label("Uma vez", systemImage: "checkmark") }
                .disabled(!commandVisible)
                .buttonStyle(.poppyProminent)
                .accessibilityIdentifier("inbox-uma-vez")
        }
        // v0.4: "Sempre" saiu do app (regra permanente se decide no PC). Onde havia o botao, so um aviso.
        if plan.showAlways || plan.showAlwaysScope {
            Label(InboxCopy.permanentRules, systemImage: "desktopcomputer")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(InboxCopy.permanentRules)
                .accessibilityIdentifier("inbox-regras-permanentes")
        }
        if plan.showDeny {
            Button(action: onDeny) { Label("Negar", systemImage: "xmark") }
                .buttonStyle(.poppyNeutral)
                .accessibilityIdentifier("inbox-negar")
        }
        ForEach(Array(plan.optionButtons.enumerated()), id: \.offset) { index, option in
            Button { onOption(option) } label: { Text(option) }
                .buttonStyle(index == 0 ? .poppyProminent : .poppyNeutral)
        }
    }
}

/// Textos fixos da sheet da caixa de entrada.
enum InboxCopy {
    static let permanentRules = "Regras permanentes: só no PC"
}
