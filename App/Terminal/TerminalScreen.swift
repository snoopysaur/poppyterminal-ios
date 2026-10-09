import SwiftUI
import PoppyKit

/// Terminal em tela cheia: `/ws` satelite na janela escolhida (foco so do celular),
/// faixa de janelas no topo, swipe de 2 dedos, pinca, snippets e folha Copiar.
/// Nunca muda o foco do PC: trocar de janela = reconectar com `window=<id>`.
struct TerminalScreen: View {
    let route: TerminalRoute

    @Environment(ServerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var connection = SipConnection()
    @State private var current: String?
    @State private var started = false
    @State private var badURL = false
    @State private var copyPayload: CopyPayload?
    @State private var selectionTick = 0

    @AppStorage("poppy.terminal.fontSize") private var fontSize: Double = 14
    @AppStorage(SnippetStorage.key) private var snippetData: Data?

    init(route: TerminalRoute) { self.route = route }

    private var detail: SessionDetail? { store.details[route.session] }
    private var windows: [WindowInfo] { detail?.allWindows ?? [] }
    /// Janela mostrada como ativa na faixa: a do celular, ou (ainda sem escolha) a do daemon.
    private var shownID: String? { current ?? detail?.pcFocusedWindow?.id }
    private var snippets: [Snippet] { SnippetList.decode(snippetData) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                TerminalContainer(
                    connection: connection,
                    fontSize: CGFloat(fontSize),
                    snippets: snippets,
                    onCopyRequest: { copyPayload = CopyPayload(text: $0) },
                    onWindowSwipe: { swipe($0) },
                    onFontSizeChange: { fontSize = Double($0) }
                )
                .accessibilityIdentifier("terminal")
                overlay
            }
        }
        .background(Theme.Palette.base.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: selectionTick)
        .sheet(item: $copyPayload) { CopySheet(rawText: $0.text) }
        .task { await begin() }
        .onDisappear {
            connection.stop()
            store.stopWatching(route.session)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, started else { return }
            Task { _ = await store.loadDetail(route.session) }
            // Sempre reconecta ao voltar (o socket pode estar morto mesmo com status .connected);
            // sem loop: nao mexe se ja ha reconexao em curso ou acesso negado.
            switch connection.status {
            case .denied, .connecting, .reconnecting: break
            default: connection.reconnectNow()
            }
        }
        .onChange(of: detail) { _, new in
            // Janela do celular fechada (no PC ou pelo app): volta ao foco do daemon.
            guard let id = current, let new, new.window(id: id) == nil else { return }
            store.forgetWindow(in: route.session)
            current = nil
            reconnect()
        }
    }

    // MARK: cabecalho

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(Theme.Palette.text)
            .accessibilityLabel("Voltar às sessões")
            .accessibilityIdentifier("btn-voltar-terminal")

            if windows.count > 1 {
                windowStrip
            } else {
                Text(route.session)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            statusLabel
        }
        .padding(.horizontal, 4)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(Color(uiColor: Theme.mantle))
    }

    private var windowStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(windows) { w in
                        windowChip(w)
                            .id(w.id)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: shownID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .accessibilityIdentifier("faixa-janelas")
    }

    private func windowChip(_ w: WindowInfo) -> some View {
        let active = w.id == shownID
        let needsYou = w.agent?.needsYou == true
        return Button {
            select(w.id)
        } label: {
            HStack(spacing: 6) {
                if needsYou {
                    Circle().fill(Color(uiColor: Theme.peach)).frame(width: 8, height: 8)
                }
                Text(w.displayName)
                    .font(.subheadline.weight(active ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .foregroundStyle(active ? Theme.Palette.onAccent : Theme.Palette.text)
            .background(Capsule().fill(active ? Theme.Palette.accent : Theme.Palette.surface))
        }
        .accessibilityLabel(needsYou ? "\(w.displayName), precisa de você" : w.displayName)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("janela-\(w.id)")
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch connection.status {
        case .connecting:
            statusText("conectando...")
        case .reconnecting(let n):
            statusText("reconectando (\(n))...")
        case .failed(let m):
            statusText(m)
        default:
            EmptyView()
        }
    }

    private func statusText(_ s: String) -> some View {
        Text(s)
            .font(.footnote)
            .foregroundStyle(Theme.Palette.textSecondary)
            .padding(.trailing, 8)
    }

    // MARK: sobreposicoes

    @ViewBuilder
    private var overlay: some View {
        if badURL {
            ContentUnavailableView {
                Label("Endereço inválido", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Não consegui montar o endereço do terminal. Confira o servidor em Ajustes.")
            } actions: {
                Button("Voltar") { dismiss() }.buttonStyle(.poppyProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.base)
        } else if connection.status == .tailscaleOff {
            EmptyStateView(.tailscaleOff, primary: { connection.reconnectNow() }, secondary: {
                if let url = URL(string: "tailscale://") { UIApplication.shared.open(url) }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.base)
        } else if connection.status == .denied {
            ContentUnavailableView {
                VStack(spacing: 12) {
                    PoppyView(.failed, size: 96)
                    Text("Acesso negado").font(.title2.bold()).foregroundStyle(Theme.Palette.text)
                }
            } description: {
                Text("O servidor recusou a conexão. Confira a senha e o endereço em Ajustes.")
                    .foregroundStyle(Theme.Palette.textSecondary)
            } actions: {
                Button("Voltar") { dismiss() }.buttonStyle(.poppyProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Palette.base)
        }
    }

    // MARK: conexao e janelas

    private func begin() async {
        _ = await store.loadDetail(route.session)
        // Ordem: janela da rota, depois a ultima usada (se ainda existe), senao foco do daemon.
        let wanted = route.window ?? store.windowToOpen(in: route.session)
        if let wanted, let d = store.details[route.session], d.window(id: wanted) == nil {
            current = nil
        } else {
            current = wanted
        }
        if let id = current { store.rememberWindow(id, in: route.session) }
        guard let url = store.terminalURL(session: route.session, window: current) else {
            badURL = true
            return
        }
        connection.start(url: url, authHeader: store.authHeader)
        started = true
    }

    private func reconnect() {
        guard let url = store.terminalURL(session: route.session, window: current) else {
            badURL = true
            return
        }
        connection.switchTo(url: url)
    }

    private func select(_ id: String) {
        guard id != current else { return }
        current = id
        store.rememberWindow(id, in: route.session)
        selectionTick += 1
        reconnect()
    }

    /// Swipe de 2 dedos: +1 proxima, -1 anterior (sem dar a volta).
    private func swipe(_ step: Int) {
        guard windows.count > 1 else { return }
        let idx = windows.firstIndex { $0.id == shownID } ?? 0
        let next = idx + step
        guard windows.indices.contains(next) else { return }
        select(windows[next].id)
    }
}
