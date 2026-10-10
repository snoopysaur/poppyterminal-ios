import SwiftUI
import PoppyKit

/// Aba Agentes: o que os agentes do PC esperam de voce. Olhar nao marca como visto;
/// o app nunca muda o foco do PC.
struct InboxView: View {
    @Environment(ServerStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var selected: InboxItem?
    @State private var approvedTick = 0

    init() {}

    private var groups: [(InboxGroup, [InboxItem])] {
        InboxGroup.allCases.compactMap { g in
            let items = store.inbox.filter { $0.group == g }.sorted { $0.since < $1.since }
            return items.isEmpty ? nil : (g, items)
        }
    }

    private var headerTone: AgentTone {
        if store.inbox.contains(where: { $0.group == .error }) { return .error }
        if store.needsYouCount > 0 { return .needsYou }
        if store.inbox.contains(where: { $0.group == .finished }) { return .done }
        return .idle
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.Palette.base)
                .navigationTitle("Agentes")
                .refreshable { await store.refreshAll() }
        }
        .sheet(item: $selected) { item in
            InboxActionSheet(item: item) { approved in
                if approved { approvedTick += 1 }
            }
        }
        .sensoryFeedback(.success, trigger: approvedTick)
    }

    @ViewBuilder private var content: some View {
        if store.inbox.isEmpty {
            ScrollView {
                emptyContent
                    .frame(maxWidth: .infinity, minHeight: 420)
            }
        } else {
            list
        }
    }

    // MARK: lista

    private var list: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if !store.humanActions {
                    Label("Login sem Tailscale: aqui só dá para ver. Aprovar e responder exigem entrar pelo endereço Tailscale.",
                          systemImage: "eye")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .listRowBackground(Color.clear)
                }
                if !store.connection.isOnline {
                    Label(connectionText, systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(groups, id: \.0) { group, items in
                Section {
                    ForEach(items) { item in
                        InboxRow(item: item) { selected = item }
                            .listRowBackground(Theme.Palette.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if store.humanActions {
                                    Button("Dispensar", systemImage: "xmark.bin") {
                                        Task { try? await store.dismiss(item) }
                                    }
                                    .tint(Theme.Palette.surfaceStrong)
                                }
                            }
                    }
                } header: {
                    Text(group.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var header: some View {
        HStack(spacing: 16) {
            PoppyView(PoppyMood(headerTone), size: 64)
            VStack(alignment: .leading, spacing: 4) {
                if store.needsYouCount > 0 {
                    StatusPill(.needsYou, count: store.needsYouCount)
                } else {
                    StatusPill(headerTone)
                }
                Text(headline)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: LocalizedStringKey {
        switch headerTone {
        case .error: "Algum agente parou com erro."
        case .needsYou: "Toque num item para resolver."
        case .done: "Tudo certo por aqui."
        default: "Nada esperando por você."
        }
    }

    private var connectionText: LocalizedStringKey {
        switch store.connection {
        case .tailscaleOff: "Sem rede: mostrando o último estado. Ligue o Tailscale."
        case .accessDenied: "Acesso negado: confira a senha em Ajustes."
        case .connecting: "Reconectando…"
        default: "Sem conexão com o PC: mostrando o último estado."
        }
    }

    // MARK: vazio e conexao

    @ViewBuilder private var emptyContent: some View {
        switch store.connection {
        case .unconfigured:
            ContentUnavailableView {
                VStack(spacing: 12) {
                    PoppyView(.waving, size: 128)
                    Text("Falta o servidor")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.Palette.text)
                }
            } description: {
                Text("Informe o endereço do PC em Ajustes para ver o que os agentes pedem.")
                    .foregroundStyle(Theme.Palette.textSecondary)
            } actions: {
                Button("Abrir Ajustes") { router.tab = .settings }
                    .buttonStyle(.poppyProminent)
            }
        case .connecting:
            EmptyStateView(.connecting)
        case .tailscaleOff:
            EmptyStateView(.tailscaleOff, primary: retry)
        case .accessDenied:
            EmptyStateView(.accessDenied, primary: { router.tab = .settings })
        case .daemonDown, .daemonOld, .failed:
            EmptyStateView(.serverUnreachable, primary: retry, secondary: { router.tab = .settings })
        case .online:
            if store.hasLoaded {
                EmptyStateView(.allCaughtUp)
            } else {
                EmptyStateView(.connecting)
            }
        }
    }

    private func retry() { Task { await store.refreshAll() } }
}

// MARK: linha

private struct InboxRow: View {
    let item: InboxItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                AgentStateBadge(item.group.tone)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(item.sinceDate, style: .relative)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if item.hasRisk {
                        Label("Com risco", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.text)
                    }
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre as ações deste item")
    }
}
