import SwiftUI
import PoppyKit

/// Aba Sessoes: lista de sessoes do PC com contadores de agentes.
struct SessionsView: View {
    @Environment(ServerStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var showNewSession = false

    var body: some View {
        NavigationStack {
            content
                .background(Theme.Palette.base)
                .navigationTitle("Sessões")
                .toolbar {
                    if store.hasLoaded {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showNewSession = true } label: {
                                Label("Nova sessão", systemImage: "plus")
                            }
                            .accessibilityIdentifier("btn-nova-sessao")
                        }
                    }
                }
                .navigationDestination(for: String.self) { SessionDetailView(session: $0) }
        }
        .sheet(isPresented: $showNewSession) { NewSessionSheet() }
    }

    @ViewBuilder private var content: some View {
        if !store.hasLoaded {
            ConnectionGateView()
        } else if store.sessions.isEmpty && store.connection.isOnline {
            EmptyStateView(.noSessions, primary: { showNewSession = true })
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if !store.connection.isOnline {
                Section {
                    Label("Sem conexão com o PC. Mostrando o último estado.", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(AgentTone.needsYou.color)
                        .listRowBackground(Theme.Palette.surface)
                }
            }
            Section {
                ForEach(store.sessions) { session in
                    NavigationLink(value: session.name) {
                        SessionRow(session: session)
                    }
                    .listRowBackground(Theme.Palette.surface)
                    .contextMenu {
                        Button {
                            router.openTerminal(session: session.name, window: store.windowToOpen(in: session.name))
                        } label: {
                            Label("Abrir terminal", systemImage: "terminal")
                        }
                        Button {
                            Task { await store.refreshAll() }
                        } label: {
                            Label("Atualizar", systemImage: "arrow.clockwise")
                        }
                    }
                }
            } footer: {
                if let warning = store.sessionWarnings.first {
                    Text(warning)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await store.refreshAll() }
    }
}

/// Linha de sessao: selo do estado mais urgente, nome, janelas e pastilhas de contagem.
private struct SessionRow: View {
    let session: SessionSummary

    private var tone: AgentTone {
        if session.needsYou > 0 { return .needsYou }
        if session.agents.errored > 0 { return .error }
        if session.agents.working > 0 { return .working }
        if session.agents.done > 0 { return .done }
        return .idle
    }

    private var windowsText: String {
        session.windows == 1 ? "1 janela" : "\(session.windows) janelas"
    }

    private var pillItems: [PillItem] {
        [PillItem(tone: .needsYou, count: session.needsYou),
         PillItem(tone: .error, count: session.agents.errored),
         PillItem(tone: .working, count: session.agents.working),
         PillItem(tone: .done, count: session.agents.done)].filter { $0.count > 0 }
    }

    var body: some View {
        HStack(spacing: 12) {
            AgentStateBadge(tone)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Palette.text)
                Text(windowsText)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if !pillItems.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { pills }
                        VStack(alignment: .leading, spacing: 6) { pills }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var pills: some View {
        ForEach(pillItems) { StatusPill($0.tone, count: $0.count) }
    }

    private struct PillItem: Identifiable {
        let tone: AgentTone
        let count: Int
        var id: AgentTone { tone }
    }
}

/// Estado antes da primeira carga (ou sem dados): conectando, Tailscale, acesso negado...
struct ConnectionGateView: View {
    @Environment(ServerStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        switch store.connection {
        case .unconfigured, .connecting, .online:
            EmptyStateView(.connecting)
        case .tailscaleOff:
            EmptyStateView(.tailscaleOff,
                           primary: { store.start() },
                           secondary: {
                               if let url = URL(string: "tailscale://") { UIApplication.shared.open(url) }
                           })
        case .accessDenied:
            EmptyStateView(.accessDenied, primary: { router.tab = .settings })
        case .daemonOld(let missing):
            problem(missing.isEmpty
                    ? "O servidor do PC é antigo demais para este app. Atualize o PC."
                    : "O servidor do PC não tem: \(missing.joined(separator: ", ")). Atualize o PC.")
        case .daemonDown:
            problem("O servidor responde, mas o daemon do terminal está fora do ar.")
        case .failed(let message):
            problem(message)
        }
    }

    private func problem(_ message: String) -> some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                PoppyView(.lost, size: 128)
                Text("Servidor fora do ar")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Palette.text)
            }
        } description: {
            Text(message).foregroundStyle(Theme.Palette.textSecondary)
        } actions: {
            Button("Tentar de novo") { store.start() }
                .buttonStyle(.poppyProminent)
            Button("Ajustes") { router.tab = .settings }
                .buttonStyle(.poppyNeutral)
        }
    }
}

/// Sheet "Nova sessao".
private struct NewSessionSheet: View {
    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    private var normalized: String { SessionName.normalize(name) }
    private var valid: Bool { SessionName.isValid(normalized) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("nome", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(create)
                        .listRowBackground(Theme.Palette.surface)
                        .accessibilityIdentifier("field-nome-sessao")
                } header: {
                    Text("Nome da sessão")
                } footer: {
                    if let errorText {
                        Text(errorText).foregroundStyle(AgentTone.error.color)
                    } else {
                        Text("1 a 32 caracteres: letras, números, _ e -.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.base)
            .navigationTitle("Nova sessão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Criar", action: create).disabled(!valid)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func create() {
        guard valid, !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                try await store.createSession(name: normalized)
                dismiss()
            } catch {
                errorText = APIError.from(error).userMessage
                store.actionError = nil
                busy = false
            }
        }
    }
}
