import SwiftUI
import PoppyKit

/// Aba Agentes: o que os agentes do PC esperam de voce. Olhar nao marca como visto;
/// o app nunca muda o foco do PC.
struct InboxView: View {
    @Environment(ServerStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var selected: InboxItem?
    @State private var approvedTick = 0
    /// Momento "tudo limpo": a Poppy acena uma vez quando a caixa esvazia (nunca com item pendente).
    @State private var justCleared = false
    @State private var cleanedTick = 0

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
                .guildNavTitle("Agentes")
                .refreshable { await store.refreshAll() }
        }
        .sheet(item: $selected) { item in
            InboxActionSheet(item: item) { approved in
                if approved { approvedTick += 1 }
            }
        }
        .sensoryFeedback(.success, trigger: approvedTick)
        .sensoryFeedback(.success, trigger: cleanedTick)
        .onChange(of: store.inbox.isEmpty) { wasEmpty, isEmpty in
            if isEmpty && !wasEmpty {
                justCleared = true
                cleanedTick += 1
            } else if !isEmpty {
                justCleared = false
            }
        }
        .onDisappear { justCleared = false }
    }

    @ViewBuilder private var content: some View {
        if store.inbox.isEmpty {
            ScrollView {
                emptyContent
                    .frame(maxWidth: .infinity, minHeight: 420)
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
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
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                if !store.humanActions {
                    Label("Login sem Tailscale: aqui só dá para ver. Aprovar e responder exigem entrar pelo endereço Tailscale.",
                          systemImage: "eye")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if !store.connection.isOnline {
                    Label(connectionText, systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            ForEach(groups, id: \.0) { group, items in
                Section {
                    ForEach(items) { item in
                        InboxRow(item: item) { selected = item }
                            .guildListRow(item.group.frameKind, tone: item.group.frameTone)
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
                    GuildSectionHeader(group.title)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 24, for: .scrollContent) // folga sob a barra de abas
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
                        .guildText(.screenTitle)
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
                EmptyStateView(.allCaughtUp, mood: justCleared ? .waving : nil)
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
                            .environment(\.locale, Locale(identifier: "pt_BR")) // "11 min 59 s", nunca "sec"
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
                    if item.hasRisk { riskExplanation }
                }
            }
            .guildRowPadding()
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre as ações deste item")
    }

    /// Por que o pedido e arriscado, escrito na propria linha (sem abrir nada). Texto em SF; o
    /// vermelho vai so no icone e no fio da esquerda, e o rotulo "Risco" nunca depende da cor.
    private var riskExplanation: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(AgentTone.error.color)
                .frame(width: 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text("Risco").foregroundStyle(Theme.Palette.text)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(AgentTone.error.color)
                }
                .font(.caption.weight(.semibold))
                ForEach(Array(item.risk.prefix(2).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if item.risk.count > 2 {
                    Text("e mais \(item.risk.count - 2)")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
