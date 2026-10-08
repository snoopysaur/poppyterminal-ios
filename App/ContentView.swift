import SwiftUI

/// Raiz: TabView (Sessoes, Agentes, Ajustes) e o terminal em tela cheia.
/// Sem endereco configurado, mostra a tela de primeira conexao.
struct ContentView: View {
    @Environment(ServerStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = AppSettings()

    var body: some View {
        @Bindable var router = router
        ZStack {
            Theme.Palette.base.ignoresSafeArea()
            if settings.isConfigured {
                tabs(selection: $router.tab)
            } else {
                ConfigView(settings: settings) { settings.apply(to: store) }
            }
        }
        .fullScreenCover(item: $router.terminal) { route in
            TerminalScreen(route: route)
                .environment(store)
                .environment(self.router)
        }
        .task { settings.apply(to: store) }
        .onChange(of: scenePhase) { _, phase in store.scenePhaseChanged(phase) }
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
