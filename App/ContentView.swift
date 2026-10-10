import SwiftUI

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
        .onChange(of: scenePhase) { _, phase in
            store.gate.scenePhaseChanged(phase)
            store.scenePhaseChanged(phase)
        }
        .onChange(of: store.gate.isLocked) { _, locked in
            if locked { router.terminal = nil } // o terminal em tela cheia nao pode ficar por cima da trava
        }
    }

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
