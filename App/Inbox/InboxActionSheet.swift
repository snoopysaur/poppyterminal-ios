import SwiftUI
import PoppyKit

/// Sheet de um item da inbox: aprovar/negar, responder, abrir no terminal ou dispensar.
/// Abrir a sheet nao marca nada como visto e nao mexe no foco do PC.
struct InboxActionSheet: View {
    /// Item com que a sheet abriu; o vivo (apos recarregar) vem de `item`.
    let seed: InboxItem
    /// `true` quando a pessoa aprovou (dispara o haptic de sucesso na tela de fora).
    let onResolved: (Bool) -> Void

    @Environment(ServerStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var prompt: PromptInfo?
    @State private var promptLoading = false
    @State private var promptError: String?
    @State private var busy = false
    @State private var pendingRisk: ReplyDecision?
    @State private var errorText: String?
    @State private var detent: PresentationDetent = .large

    private static let mono = Font.custom(Theme.fontRegular, size: 15, relativeTo: .callout)

    init(item: InboxItem, onResolved: @escaping (Bool) -> Void) {
        self.seed = item
        self.onResolved = onResolved
    }

    /// O item vivo da store; `nil` quando sumiu da caixa de entrada.
    private var liveItem: InboxItem? { store.inbox.first { $0.id == seed.id } }

    /// Para exibir: o vivo, ou o da abertura se sumiu (os botoes saem de `plan`).
    private var item: InboxItem { liveItem ?? seed }

    private var promptSnapshot: SheetPromptSnapshot? {
        prompt.map { SheetPromptSnapshot(found: $0.found, answerable: $0.answerable,
                                         optionLabels: $0.options.map(\.label)) }
    }

    /// Decisao pura dos botoes (PoppyKit). Enquanto resolve, o item que some nao conta como removido.
    private var plan: InboxSheetPlan {
        InboxSheetLogic.plan(item: busy ? item : liveItem, prompt: promptSnapshot,
                             humanActions: store.humanActions, needsAnswer: item.group.needsAnswer)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    detail
                    if let errorText = errorText ?? promptError {
                        Label(errorText, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.text)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AgentTone.error.color.opacity(0.18)))
                            .accessibilityAddTraits(.isStaticText)
                    }
                    actions
                }
                .padding(16)
            }
            .background(Theme.Palette.base)
            .navigationTitle(item.group.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        #if DEBUG
        .overlay(alignment: .topLeading) { DeepLinkProbe() }
        #endif
        .interactiveDismissDisabled(busy)
        .task { await loadPromptIfNeeded() }
        .confirmationDialog("Este pedido tem risco", isPresented: riskDialogBinding, titleVisibility: .visible) {
            Button("Aprovar mesmo assim", role: .destructive) {
                if let d = pendingRisk { reply(d, ack: item.risk) }
            }
            Button("Cancelar", role: .cancel) { pendingRisk = nil }
        } message: {
            Text(item.risk.joined(separator: "\n"))
        }
    }

    // MARK: partes

    @ViewBuilder private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Tamanhos de acessibilidade: pastilha em linha propria, nome com a largura toda.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    AgentStateBadge(item.group.tone)
                    headerTitles
                }
                StatusPill(item.group.tone)
            }
        } else {
            HStack(spacing: 12) {
                AgentStateBadge(item.group.tone)
                headerTitles
                Spacer(minLength: 0)
                StatusPill(item.group.tone)
            }
        }
    }

    private var headerTitles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.displayName)
                .font(.headline)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.location)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var detail: some View {
        switch item.kind {
        case .approval:
            commandBlock
            if item.hasRisk { riskBlock }
        case .plan:
            if item.planLines.isEmpty {
                summaryText
            } else {
                Text(item.planLines.joined(separator: "\n"))
                    .font(.callout)
                    .foregroundStyle(Theme.Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            summaryText
        }
    }

    @ViewBuilder private var summaryText: some View {
        if !item.summary.isEmpty {
            Text(item.summary)
                .font(.body)
                .foregroundStyle(Theme.Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// O comando precisa estar na tela antes de aprovar (prompt carregado ou resumo do item).
    private var commandVisible: Bool { prompt != nil || !item.summary.isEmpty }

    /// O que o servidor validou (`item.summary`) vence as linhas da tela: e o que a pessoa
    /// aprova. Sem resumo, cai nas linhas do prompt.
    private var commandText: String {
        if !item.summary.isEmpty { return item.summary }
        if let p = prompt {
            let lines = p.lines.joined(separator: "\n")
            if !lines.isEmpty { return lines }
            if !p.message.isEmpty { return p.message }
        }
        return item.summary
    }

    private var commandBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Comando")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            Group {
                if promptLoading && prompt == nil && item.summary.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text(commandText)
                        .font(Self.mono)
                        .foregroundStyle(Theme.Palette.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Palette.sunken))
        }
    }

    private var riskBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Risco", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.text)
            ForEach(item.risk, id: \.self) { r in
                Text("• \(r)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AgentTone.needsYou.color.opacity(0.16)))
        .accessibilityElement(children: .combine)
    }

    // MARK: acoes

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if plan.showNotice {
                notAnswerableNotice
                if plan.showDeny {
                    Button { reply(.deny, ack: nil) } label: { Label("Negar", systemImage: "xmark") }
                        .buttonStyle(.poppyNeutral)
                }
            } else if store.humanActions {
                humanActions
            } else if item.group != .finished && item.group != .other {
                Label("Login sem Tailscale: dá para ver, não para responder. Abra no terminal ou entre pelo endereço Tailscale.",
                      systemImage: "eye")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if item.canOpenTerminal {
                Button {
                    router.openTerminal(session: item.session, window: item.window.isEmpty ? nil : item.window)
                    dismiss()
                } label: {
                    Label("Abrir no terminal", systemImage: "terminal")
                }
                // Item nao respondivel pelo app: abrir o terminal e a acao principal (Mauve).
                .buttonStyle(PoppyActionStyle(role: plan.showNotice ? .prominent : .neutral))
                .accessibilityIdentifier("inbox-abrir-terminal")
            }
            if store.humanActions, item.group != .approval {
                Button {
                    resolve({ try await store.dismiss(item) }, approved: false)
                } label: {
                    Label("Dispensar", systemImage: "xmark.bin")
                }
                .buttonStyle(.poppyNeutral)
                .disabled(busy)
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(busy)
    }

    /// Item que o app nao consegue responder (sem hold): so informa e manda ao terminal.
    private var notAnswerableNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Responda no terminal")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.text)
                Text(plan.itemGone
                     ? "Este item não está mais na caixa de entrada. Feche e confira a lista."
                     : "O app não consegue aprovar este pedido. Abra o terminal desta janela para aprovar; Negar pelo app continua valendo quando aparece abaixo.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.text)
            }
        } icon: {
            Image(systemName: "terminal").foregroundStyle(AgentTone.needsYou.color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AgentTone.needsYou.color.opacity(0.16)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox-nao-respondivel")
    }

    @ViewBuilder private var humanActions: some View {
        InboxActionButtons(plan: plan, alwaysScope: item.alwaysScope, commandVisible: commandVisible,
                           onStart: { start($0) }, onDeny: { reply(.deny, ack: nil) },
                           onOption: { answerOption($0) })
    }

    // MARK: logica

    private var riskDialogBinding: Binding<Bool> {
        Binding(get: { pendingRisk != nil }, set: { if !$0 { pendingRisk = nil } })
    }

    /// Aprovar com risco pede confirmacao explicita antes de mandar `risk_ack`.
    private func start(_ decision: ReplyDecision) {
        guard InboxSheetLogic.allows(decision, canAnswer: plan.canAnswer) else { return }
        if item.hasRisk {
            pendingRisk = decision
        } else {
            reply(decision, ack: nil)
        }
    }

    /// Resposta a ask/question: re-checa `canAnswer` no momento do toque.
    private func answerOption(_ option: String) {
        guard plan.canAnswer else { return }
        resolve({ try await store.answer(item, with: option) }, approved: false)
    }

    private func reply(_ decision: ReplyDecision, ack: [String]?) {
        pendingRisk = nil
        // Re-checa no momento da acao (inclusive vindo do dialogo de risco): so Negar passa sem canAnswer.
        guard InboxSheetLogic.allows(decision, canAnswer: plan.canAnswer) else { return }
        resolve({ try await store.reply(to: item, decision: decision, riskAck: ack) },
                approved: decision == .once || decision == .always)
    }

    private func resolve(_ work: @escaping () async throws -> Void, approved: Bool) {
        guard !busy else { return }
        busy = true
        errorText = nil
        store.actionError = nil
        Task {
            do {
                try await work()
                busy = false
                onResolved(approved)
                dismiss()
            } catch {
                busy = false
                let e = APIError.from(error)
                errorText = e.userMessage
                if InboxSheetLogic.reloadsAfter(e.kind) {
                    // O pedido mudou: recarrega a caixa e o prompt sozinho, sem fechar a sheet.
                    await store.refreshAll()
                    prompt = nil
                    await loadPromptIfNeeded()
                }
            }
        }
    }

    private func loadPromptIfNeeded() async {
        guard item.kind == .approval || ((item.kind == .ask || item.kind == .question) && item.options.isEmpty) else { return }
        promptLoading = true
        promptError = nil
        do { prompt = try await store.prompt(for: item) } catch {
            promptError = "Nao foi possivel carregar o comando: " + APIError.from(error).userMessage
        }
        promptLoading = false
    }
}
