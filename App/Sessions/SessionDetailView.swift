import SwiftUI
import PoppyKit

/// Detalhe de uma sessao: janelas por workspace. Tocar abre o terminal NA janela
/// (foco so do celular); o foco do PC nunca muda.
struct SessionDetailView: View {
    let session: String

    @Environment(ServerStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var didLoad = false
    @State private var showNewWindow = false
    @State private var openAfterSheet: String?
    @State private var pendingClose: WindowInfo?
    @State private var errorText: String?

    private var detail: SessionDetail? { store.details[session] }

    var body: some View {
        content
            .background(Theme.Palette.base)
            .navigationTitle(session)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        router.openTerminal(session: session, window: store.windowToOpen(in: session))
                    } label: {
                        Label("Abrir terminal", systemImage: "terminal")
                    }
                    .accessibilityIdentifier("btn-abrir-terminal")
                    Button { showNewWindow = true } label: {
                        Label("Nova janela", systemImage: "plus")
                    }
                    .disabled(detail == nil)
                    .accessibilityIdentifier("btn-nova-janela")
                }
            }
            .task {
                _ = await store.loadDetail(session)
                didLoad = true
            }
            .onDisappear { store.stopWatching(session) }
            .sheet(isPresented: $showNewWindow, onDismiss: openCreatedWindow) {
                NewWindowSheet(session: session, workspaces: detail?.workspaces ?? []) { id in
                    openAfterSheet = id
                }
            }
            .confirmationDialog(
                "Fechar esta janela?",
                isPresented: Binding(get: { pendingClose != nil }, set: { if !$0 { pendingClose = nil } }),
                titleVisibility: .visible,
                presenting: pendingClose
            ) { window in
                Button("Fechar \(window.displayName)", role: .destructive) { close(window) }
            } message: { _ in
                Text("O programa que roda nela será encerrado no PC.")
            }
            .alert("Não foi possível concluir", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        if let detail {
            if detail.allWindows.isEmpty {
                ContentUnavailableView {
                    Label("Nenhuma janela", systemImage: "rectangle.on.rectangle")
                } description: {
                    Text("Crie uma janela para abrir um terminal nesta sessão.")
                } actions: {
                    Button("Nova janela") { showNewWindow = true }
                        .buttonStyle(.poppyProminent)
                }
            } else {
                windowList(detail)
            }
        } else if didLoad {
            EmptyStateView(.serverUnreachable, primary: {
                didLoad = false
                Task {
                    _ = await store.loadDetail(session)
                    didLoad = true
                }
            })
        } else {
            ProgressView("Carregando...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func windowList(_ detail: SessionDetail) -> some View {
        List {
            ForEach(detail.workspaces) { workspace in
                if !workspace.windows.isEmpty {
                    Section(workspace.displayName) {
                        ForEach(workspace.windows) { window in
                            Button {
                                router.openTerminal(session: session, window: window.id)
                            } label: {
                                WindowRow(window: window, isLast: store.lastWindow(for: session) == window.id)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.Palette.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { pendingClose = window } label: {
                                    Label("Fechar", systemImage: "xmark.rectangle")
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { _ = await store.loadDetail(session) }
    }

    private func openCreatedWindow() {
        guard let id = openAfterSheet else { return }
        openAfterSheet = nil
        router.openTerminal(session: session, window: id)
    }

    private func close(_ window: WindowInfo) {
        Task {
            do {
                try await store.closeWindow(session: session, id: window.id)
            } catch {
                errorText = APIError.from(error).userMessage
                store.actionError = nil
            }
        }
    }
}

/// Linha de janela: selo do agente (ou terminal), nome, estado e comando em mono.
private struct WindowRow: View {
    let window: WindowInfo
    let isLast: Bool

    private var tone: AgentTone? {
        guard let agent = window.agent else { return nil }
        if agent.needsYou { return .needsYou }
        switch agent.stateKind {
        case .needsInput: return .needsYou
        case .errored: return .error
        case .working: return .working
        case .done: return .done
        case .idle, .unknown: return .idle
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if let tone {
                AgentStateBadge(tone)
            } else {
                WindowGlyph()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(window.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.text)
                if let agent = window.agent, let tone {
                    Text(agentLine(agent, tone))
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                if let cmd = window.runningCmdline, !cmd.isEmpty {
                    Text(cmd)
                        .font(.custom(Theme.fontRegular, size: 12, relativeTo: .caption))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if window.focused || isLast {
                    Text(markers)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var markers: String {
        var parts: [String] = []
        if window.focused { parts.append(String(localized: "em foco no PC")) }
        if isLast { parts.append(String(localized: "aberta por último")) }
        return parts.joined(separator: " · ")
    }

    private func agentLine(_ agent: AgentInfo, _ tone: AgentTone) -> String {
        var parts: [String] = []
        if !agent.harness.isEmpty { parts.append(agent.harness) }
        parts.append(tone.labelText)
        return parts.joined(separator: " · ")
    }
}

private struct WindowGlyph: View {
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 32

    var body: some View {
        Image(systemName: "terminal")
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Theme.Palette.surfaceStrong))
            .accessibilityHidden(true)
    }
}

/// Sheet "Nova janela": cria SEM tirar o foco do PC; opcionalmente abre no terminal.
private struct NewWindowSheet: View {
    let session: String
    let workspaces: [WorkspaceInfo]
    var onCreated: (String) -> Void

    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var workspace: Int?
    @State private var openAfter = true
    @State private var busy = false
    @State private var errorText: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("opcional", text: $name)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .listRowBackground(Theme.Palette.surface)
                        .accessibilityIdentifier("field-nome-janela")
                } header: {
                    Text("Nome da janela")
                }
                if workspaces.count > 1 {
                    Section {
                        Picker("Workspace", selection: $workspace) {
                            Text("Padrão do servidor").tag(Int?.none)
                            ForEach(workspaces) { Text($0.displayName).tag(Int?.some($0.n)) }
                        }
                        .listRowBackground(Theme.Palette.surface)
                    }
                }
                Section {
                    Toggle("Abrir no terminal", isOn: $openAfter)
                        .listRowBackground(Theme.Palette.surface)
                } footer: {
                    if let errorText {
                        Text(errorText).foregroundStyle(AgentTone.error.color)
                    } else {
                        Text("A janela aparece no PC sem mudar o foco de lá.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.base)
            .navigationTitle("Nova janela")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Criar", action: create)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() {
        guard !busy else { return }
        busy = true
        errorText = nil
        let windowName = trimmed.isEmpty ? nil : trimmed
        Task {
            do {
                let created = try await store.createWindow(in: session, name: windowName, workspace: workspace)
                if openAfter { onCreated(created.id) }
                dismiss()
            } catch {
                errorText = APIError.from(error).userMessage
                store.actionError = nil
                busy = false
            }
        }
    }
}
