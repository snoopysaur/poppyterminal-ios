#if DEBUG
import SwiftUI
import PoppyKit

/// Tela catalogo (so Debug) com cada componente de `App/Design`, para revisar e capturar.
/// Para abrir: o app raiz pode mostrar `DesignCatalogView()` quando `DesignCatalog.isRequested`
/// (argumento de lancamento `-design-catalog`).
enum DesignCatalog {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-design-catalog")
    }

    /// `-fixture-sheet-risco`: abre a sheet REAL de aprovacao com um pedido de risco fixo (sem servidor).
    static var isRiskSheetRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-fixture-sheet-risco")
    }

    /// `-fixture-inbox`: abre a aba Agentes REAL com pedidos fixos (um com risco, um comum), sem servidor.
    static var isInboxFixtureRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-fixture-inbox")
    }

    /// O comando exato do pedido de teste: o que aparece na tela tem que ser identico a isto.
    static let riskCommand = "Bash: git push --force origin wip/v04-n3b"
    /// Explicacao do risco do pedido de teste (aparece na linha da caixa de entrada).
    static let riskExplanation = "Reescreve o histórico no repositório remoto (force push)."
}

/// Hospedeiro da aba Agentes real com pedidos fixos. So Debug.
struct InboxFixtureHost: View {
    @Environment(ServerStore.self) private var store
    @State private var ready = false

    private static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1_000_000_000) }

    private var items: [InboxItem] {
        [
            InboxItem(id: "fix-linha-risco", kind: "approval", session: "e2e", window: "w1", name: "Claude",
                      summary: DesignCatalog.riskCommand, options: ["once", "deny"], requestId: "req-a",
                      risk: [DesignCatalog.riskExplanation, "Pode apagar commits de outras pessoas."],
                      since: Self.now - 180_000_000_000, answerable: true),
            InboxItem(id: "fix-linha-comum", kind: "approval", session: "e2e", window: "w2", name: "Codex",
                      summary: "Bash: ls -la", options: ["once", "deny"], requestId: "req-b",
                      since: Self.now - 60_000_000_000, answerable: true),
        ]
    }

    var body: some View {
        Group {
            if ready {
                InboxView()
            } else {
                Theme.Palette.base.ignoresSafeArea()
            }
        }
        .task {
            store.installFixture(info: ServerInfo(humanActions: true), inbox: items)
            ready = true
        }
    }
}

/// Hospedeiro da sheet real com o pedido de risco fixo. So Debug.
struct RiskSheetHost: View {
    @Environment(ServerStore.self) private var store
    @State private var shown = false

    private var item: InboxItem {
        InboxItem(id: "fix-risco", kind: "approval", session: "e2e", window: "w1", name: "Claude",
                  summary: DesignCatalog.riskCommand, options: ["once", "deny"], requestId: "req-fix",
                  risk: [DesignCatalog.riskExplanation], answerable: true)
    }

    var body: some View {
        Theme.Palette.base.ignoresSafeArea()
            .task {
                store.installFixture(info: ServerInfo(humanActions: true), inbox: [item])
                shown = true
            }
            .sheet(isPresented: $shown) {
                InboxActionSheet(item: item) { _ in }
            }
    }
}

struct DesignCatalogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Catálogo visual")
                    .guildScreenTitle()
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)

                section("Pedido pendente (v0.3.2)") {
                    VStack(spacing: 12) {
                        PendingPromptCard(
                            prompt: PendingPrompt(inboxId: "17", kind: "approval", summary: "Bash: rm -rf build/"),
                            busy: false, action: {})
                        PendingInfoCard(
                            prompt: PendingPrompt(inboxId: "219", kind: "approval", summary: "PowerShell: Get-ChildItem",
                                                  answerable: false),
                            onOpenTerminal: {})
                        PendingStaleBanner(
                            message: APIError.api(status: 409, code: "pending_prompt", message: "", retryAfter: nil)
                                .pendingMessage(answerable: false),
                            onRefresh: {}, onOpenTerminal: {}, onDismiss: {})
                    }
                }

                section("Sheet: botões com e sem Sempre (v0.3.2)") {
                    VStack(spacing: 16) {
                        sheetButtons(options: ["once", "deny"], id: "catalogo-sheet-sem-always")
                        sheetButtons(options: ["once", "always", "deny"], id: "catalogo-sheet-com-always")
                    }
                }

                section("Rodapé do polegar e segurar (v0.5)") {
                    VStack(spacing: 16) {
                        holdFooter
                        HStack(spacing: 12) {
                            DictationButton(dictation: DictationController())
                            Text("Ditado: toque no microfone, fale e revise o texto antes de enviar.")
                                .font(.footnote)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("catalogo-ditado")
                    }
                }

                section("Papéis de cor") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        swatch("base", Theme.Palette.base)
                        swatch("surface", Theme.Palette.surface)
                        swatch("surfaceStrong", Theme.Palette.surfaceStrong)
                        swatch("text", Theme.Palette.text)
                        swatch("textSecondary", Theme.Palette.textSecondary)
                        swatch("accent (ouro)", Theme.Palette.accent)
                        swatch("onAccent", Theme.Palette.onAccent)
                        swatch("border (bronze)", Theme.Palette.border)
                        swatch("borderStrong", Theme.Palette.borderStrong)
                        swatch("tintAlert", Theme.Palette.tintAlert)
                        swatch("tintDanger", Theme.Palette.tintDanger)
                        swatch("seal / sunken", Theme.Palette.seal)
                        ForEach(AgentTone.allCases) { swatch($0.labelText, $0.color) }
                    }
                }

                section("Molduras Guild") {
                    VStack(spacing: 12) {
                        ForEach(Array(GuildFrameKind.catalog.enumerated()), id: \.offset) { _, item in
                            Text(item.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(item.kind == .button ? Theme.Palette.onAccent : Theme.Palette.text)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(.horizontal, 12)
                                .guildFrame(item.kind)
                        }
                    }
                    .accessibilityIdentifier("catalogo-molduras")
                }

                section("Tipos") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Título em pixel").guildText(.screenTitle).foregroundStyle(Theme.Palette.text)
                        Text("Cabeçalho de seção").guildText(.sectionHeader).foregroundStyle(Theme.Palette.textSecondary)
                        Button("Botão em pixel") {}.buttonStyle(.poppyProminent)
                        Button("Botão neutro") {}.buttonStyle(.poppyNeutral)
                        Text("Corpo em SF Pro: explicação do risco e texto longo ficam assim.")
                            .font(.body).foregroundStyle(Theme.Palette.text)
                        Text("git push --force origin main")
                            .font(.custom(Theme.fontRegular, size: 14, relativeTo: .callout))
                            .foregroundStyle(Theme.Palette.text)
                    }
                    .accessibilityIdentifier("catalogo-tipos")
                }

                section("StatusPill") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(AgentTone.allCases) { StatusPill($0) }
                        StatusPill(.needsYou, count: 2)
                    }
                }

                section("AgentStateBadge") {
                    HStack(spacing: 20) {
                        ForEach(AgentTone.allCases) {
                            AgentStateBadge($0, count: $0 == .needsYou ? 3 : nil)
                        }
                    }
                }

                section("Linha de lista") {
                    VStack(spacing: 0) {
                        ForEach(AgentTone.allCases) { tone in
                            HStack(spacing: 12) {
                                AgentStateBadge(tone)
                                VStack(alignment: .leading) {
                                    Text("sessão \(tone.rawValue)").font(.body.weight(.semibold))
                                    Text("2 janelas").font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                                }
                                Spacer()
                                StatusPill(tone)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .foregroundStyle(Theme.Palette.text)
                            if tone != AgentTone.allCases.last { Divider().overlay(Theme.Palette.surfaceStrong) }
                        }
                    }
                    .guildFrame(.panel)
                }

                section("Comando (mono)") {
                    Text("$ xcodebuild test\n~/Desktop/Teste/poppyterminal-ios")
                        .font(.custom(Theme.fontRegular, size: 14, relativeTo: .callout))
                        .foregroundStyle(Theme.Palette.text)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Palette.sunken)
                }

                section("PoppyView") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(PoppyMood.allCases) { mood in
                            VStack(spacing: 4) {
                                PoppyView(mood, size: 64)
                                Text(mood.rawValue).font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                    }
                }

                section("EmptyStateView") {
                    VStack(spacing: 16) {
                        ForEach(kinds, id: \.self) { kind in
                            EmptyStateView(kind, primary: {}, secondary: {})
                                .frame(minHeight: 420)
                                .background(Theme.Palette.base)
                        }
                        EmptyStateView(.allCaughtUp)
                            .frame(minHeight: 320)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.Palette.base)
        .preferredColorScheme(.dark)
    }

    private var kinds: [EmptyStateView.Kind] {
        [.noSessions, .connecting, .tailscaleOff, .accessDenied, .serverUnreachable]
    }

    /// Botoes da sheet para um item de aprovacao respondivel com as `options` dadas.
    private func sheetButtons(options: [String], id: String) -> some View {
        let item = InboxItem(id: "cat", kind: "approval", summary: "Bash: ls", options: options,
                             requestId: "req-cat", alwaysScope: ["Bash(ls:*)"], answerable: true)
        let plan = InboxSheetLogic.plan(item: item, prompt: nil, humanActions: true, needsAnswer: true)
        return VStack(spacing: 10) {
            InboxActionButtons(plan: plan, alwaysScope: item.alwaysScope)
        }
        .padding(16)
        .guildFrame(.panel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    /// Rodape do polegar de um pedido COM risco: Negar de um toque e Aprovar que exige segurar 0,8 s.
    private var holdFooter: some View {
        let item = InboxItem(id: "cat-risco", kind: "approval", summary: "Bash: rm -rf build/", options: ["once", "deny"],
                             requestId: "req-cat-risco", risk: ["Apaga arquivos sem volta."], answerable: true)
        let plan = InboxSheetLogic.plan(item: item, prompt: nil, humanActions: true, needsAnswer: true)
        return InboxActionButtons(plan: plan, hold: HoldConfig(token: "cat-risco", onComplete: {}, onAssistive: {}))
            .padding(16)
            .guildFrame(.panel)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("catalogo-hold")
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(color).frame(height: 28)
                .overlay(Rectangle().strokeBorder(Theme.Palette.border, lineWidth: 1))
            Text(name).font(.footnote).foregroundStyle(Theme.Palette.text)
        }
        .padding(10)
        .guildFrame(.panel)
    }
}

#Preview("Catálogo") {
    DesignCatalogView()
}
private extension GuildFrameKind {
    /// Os seis tipos de moldura, com nome para o catalogo.
    static var catalog: [(kind: GuildFrameKind, name: String)] {
        [(.panel, "Painel"), (.alert, "Alerta (precisa de você)"), (.danger, "Perigo (risco)"),
         (.seal, "Selo"), (.button, "Botão principal"), (.neutralButton, "Botão neutro")]
    }
}
#endif
