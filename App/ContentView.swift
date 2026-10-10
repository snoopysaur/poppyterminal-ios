import SwiftUI
import PoppyKit

/// Raiz: TabView (Sessoes, Agentes, Ajustes) e o terminal em tela cheia.
/// Sem endereco configurado, mostra a tela de primeira conexao.
struct ContentView: View {
    @Environment(ServerStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var settings = AppSettings()

    var body: some View {
        @Bindable var router = router
        ZStack {
            Theme.Palette.base.ignoresSafeArea()
            if !settings.isConfigured {
                ConfigView(settings: settings) { settings.apply(to: store) }
            } else if store.gate.isLocked {
                // Travado: a arvore das abas SAI da tela (sheets abertas fecham junto) ate o Face ID.
                LockView(gate: store.gate)
                    .transition(.opacity)
            } else {
                tabs(selection: $router.tab)
                    .safeAreaInset(edge: .top, spacing: 0) { ordersBlockedBanner }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Motion.faceIDToWavingSeconds), value: store.gate.isLocked)
        .fullScreenCover(item: $router.terminal) { route in
            TerminalScreen(route: route)
                .environment(store)
                .environment(self.router)
        }
        .task { settings.apply(to: store) }
        .onOpenURL { router.receive($0) }
        .task(id: DeepLinkTrigger(link: router.pendingLink, ready: deepLinkReady)) { await handlePendingLink() }
        #if DEBUG
        .overlay(alignment: .topLeading) { deepLinkProbe }
        #endif
        .onChange(of: scenePhase) { _, phase in
            store.gate.scenePhaseChanged(phase)
            store.scenePhaseChanged(phase)
        }
        .onChange(of: store.gate.isLocked) { _, locked in
            if locked { router.terminal = nil } // o terminal em tela cheia nao pode ficar por cima da trava
        }
    }

    // MARK: deep link do push (poppyterminal://inbox/<id>)

    private struct DeepLinkTrigger: Hashable {
        let link: DeepLink?
        let ready: Bool
    }

    private var deepLinkReady: Bool {
        DeepLinkFlow.isReady(configured: settings.isConfigured, locked: store.gate.isLocked, connection: store.connection)
    }

    /// O link fica guardado ate o AuthGate desbloquear. Depois: pergunta ao servidor de que item se
    /// trata e SO NAVEGA (aba Agentes + sheet do item). 404/erro: so a aba Agentes. Nunca aprova nem age.
    /// Se travar no meio (cancelamento), o link continua guardado e roda de novo ao desbloquear.
    private func handlePendingLink() async {
        guard deepLinkReady, let link = router.pendingLink else { return }
        guard case .inbox(let pushID) = link else { return }
        let started = ContinuousClock.now
        let resolved = await store.resolvePush(pushID)
        guard !Task.isCancelled else { return }
        if case .item(let id) = resolved, !store.inbox.contains(where: { $0.id == id }) {
            await store.refreshAll() // o item pode ser mais novo que a ultima leitura da Inbox
            guard !Task.isCancelled else { return }
        }
        router.terminal = nil // o terminal em tela cheia taparia a Inbox
        router.tab = .agents
        router.focusInboxID = DeepLinkFlow.focusTarget(resolved: resolved, inboxIDs: Set(store.inbox.map(\.id)))
        let elapsed = ContinuousClock.now - started
        router.deepLinkMillis = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
        router.pendingLink = nil
    }

    #if DEBUG
    /// Sonda de teste (so Debug): expoe quanto o tratamento do link levou depois de pronto.
    @ViewBuilder private var deepLinkProbe: some View {
        if let ms = router.deepLinkMillis {
            Color.clear.frame(width: 2, height: 2)
                .accessibilityElement()
                .accessibilityIdentifier("deeplink-ms")
                .accessibilityValue("\(ms)")
        }
    }
    #endif

    /// Sem Face ID nem senha no iPhone: o app abre so para leitura e avisa.
    @ViewBuilder private var ordersBlockedBanner: some View {
        if store.gate.ordersBlocked {
            Label("Sem Face ID nem senha no iPhone: ordens bloqueadas. Configure em Ajustes do iPhone.",
                  systemImage: "lock.trianglebadge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.text)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AgentTone.needsYou.color.opacity(0.16))
                .accessibilityIdentifier("aviso-ordens-bloqueadas")
        }
    }

    private func tabs(selection: Binding<AppTab>) -> some View {
        TabView(selection: selection) {
            SessionsView()
                .tabItem { Label("Sessões", systemImage: "terminal") }
                .tag(AppTab.sessions)
            InboxView()
                .tabItem { Label("Agentes", systemImage: "tray.full") }
                .badge(store.needsYouCount)
                .tag(AppTab.agents)
            SettingsView(settings: settings)
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
