import SwiftUI
import PoppyKit

/// Sheet de um item da inbox: aprovar/negar, responder, abrir no terminal ou dispensar.
/// Abrir a sheet nao marca nada como visto e nao mexe no foco do PC.
struct InboxActionSheet: View {
    let item: InboxItem
    /// `true` quando a pessoa aprovou (dispara o haptic de sucesso na tela de fora).
    let onResolved: (Bool) -> Void

    @Environment(ServerStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var prompt: PromptInfo?
    @State private var promptLoading = false
    @State private var promptError: String?
    @State private var busy = false
    @State private var pendingRisk: ReplyDecision?
    @State private var errorText: String?
    @State private var detent: PresentationDetent = .large

    private static let mono = Font.custom(Theme.fontRegular, size: 15, relativeTo: .callout)

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

    private var header: some View {
        HStack(spacing: 12) {
            AgentStateBadge(item.group.tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.text)
                Text(item.location)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 0)
            StatusPill(item.group.tone)
        }
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

    private var commandText: String {
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
            if store.humanActions, !item.answerable, item.group.needsAnswer {
                notAnswerableNotice
                if item.kind == .approval, item.requestId != nil {
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
                .buttonStyle(.poppyNeutral)
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
                Text("O app não consegue responder este pedido. Abra o terminal desta janela para aprovar ou negar.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
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
        switch item.kind {
        case .approval:
            Button { start(.once) } label: { Label("Uma vez", systemImage: "checkmark") }
                .disabled(!commandVisible)
                .buttonStyle(.poppyProminent)
            Button { start(.always) } label: { Label("Sempre", systemImage: "checkmark.seal") }
                .disabled(!commandVisible)
                .buttonStyle(.poppyNeutral)
            if !item.alwaysScope.isEmpty {
                Text("Sempre vale para: \(item.alwaysScope.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { reply(.deny, ack: nil) } label: { Label("Negar", systemImage: "xmark") }
                .buttonStyle(.poppyNeutral)
        case .ask, .question:
            ForEach(Array(questionOptions.enumerated()), id: \.offset) { index, option in
                Button {
                    resolve({ try await store.answer(item, with: option) }, approved: false)
                } label: {
                    Text(option)
                }
                .buttonStyle(index == 0 ? .poppyProminent : .poppyNeutral)
            }
        default:
            EmptyView()
        }
    }

    private var questionOptions: [String] {
        if !item.options.isEmpty { return item.options }
        return prompt?.options.map(\.label) ?? []
    }

    // MARK: logica

    private var riskDialogBinding: Binding<Bool> {
        Binding(get: { pendingRisk != nil }, set: { if !$0 { pendingRisk = nil } })
    }

    /// Aprovar com risco pede confirmacao explicita antes de mandar `risk_ack`.
    private func start(_ decision: ReplyDecision) {
        if item.hasRisk {
            pendingRisk = decision
        } else {
            reply(decision, ack: nil)
        }
    }

    private func reply(_ decision: ReplyDecision, ack: [String]?) {
        pendingRisk = nil
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
                errorText = APIError.from(error).userMessage
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
