import SwiftUI
import PoppyKit

/// Botoes de resposta da sheet da caixa de entrada, desenhados a partir do `InboxSheetPlan`
/// (decisao pura em PoppyKit). Usado pela sheet real e pelo catalogo de design.
/// Rodape do polegar: Negar e Aprovar lado a lado, 56 pt de altura (empilhados em tamanhos de
/// acessibilidade). Com `hold`, aprovar exige segurar 0,8 s; Negar e sempre um toque.
struct InboxActionButtons: View {
    let plan: InboxSheetPlan
    var alwaysScope: [String] = []
    var commandVisible = true
    /// Pedido com risco: o botao de aprovar vira "segurar" (nil = toque comum).
    var hold: HoldConfig?
    var onStart: (ReplyDecision) -> Void = { _ in }
    var onDeny: () -> Void = {}
    var onOption: (String) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 10) {
            decisionRow
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
            ForEach(Array(plan.optionButtons.enumerated()), id: \.offset) { index, option in
                Button { onOption(option) } label: { Text(option) }
                    .buttonStyle(index == 0 ? .poppyThumbProminent : .poppyThumbNeutral)
            }
        }
    }

    @ViewBuilder private var decisionRow: some View {
        if plan.showApprove || plan.showDeny {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                if plan.showDeny {
                    Button(action: onDeny) { Label("Negar", systemImage: "xmark") }
                        .buttonStyle(.poppyThumbNeutral)
                        .accessibilityIdentifier("inbox-negar")
                }
                if plan.showApprove {
                    approve
                }
            }
        }
    }

    @ViewBuilder private var approve: some View {
        if let hold {
            HoldToApproveButton(token: hold.token, onHoldComplete: hold.onComplete,
                                onAssistiveApprove: hold.onAssistive)
                .id(hold.token)
                .disabled(!commandVisible)
        } else {
            Button { onStart(.once) } label: { Label("Uma vez", systemImage: "checkmark") }
                .disabled(!commandVisible)
                .buttonStyle(.poppyThumbProminent)
                .accessibilityIdentifier("inbox-uma-vez")
        }
    }
}

/// Textos fixos da sheet da caixa de entrada.
enum InboxCopy {
    static let permanentRules = "Regras permanentes: só no PC"
}
