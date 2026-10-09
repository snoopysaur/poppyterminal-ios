import SwiftUI
import PoppyKit

/// Como a janela e mostrada: conversa (Chat) ou terminal.
enum TerminalViewMode: String, Sendable, CaseIterable {
    case chat, terminal

    var label: String {
        switch self {
        case .chat: String(localized: "Chat")
        case .terminal: String(localized: "Terminal")
        }
    }
}

/// Regras puras da escolha de modo (testadas sem UI).
enum TerminalPolicy {
    /// Chat so quando o servidor tem chat, o login Tailscale permite agir e a janela tem Claude.
    /// Qualquer outra combinacao abre no terminal (servidor sem `features` = terminal de hoje).
    static func chatAvailable(supportsChat: Bool, humanActions: Bool, windowChat: Bool) -> Bool {
        supportsChat && humanActions && windowChat
    }

    /// Modo inicial da janela (decisao 1: Chat e o padrao quando disponivel).
    static func defaultMode(supportsChat: Bool, humanActions: Bool, windowChat: Bool) -> TerminalViewMode {
        chatAvailable(supportsChat: supportsChat, humanActions: humanActions, windowChat: windowChat) ? .chat : .terminal
    }

    /// Modo efetivo: a escolha da pessoa vale so se o chat estiver disponivel; senao, terminal.
    static func mode(choice: TerminalViewMode?, supportsChat: Bool, humanActions: Bool, windowChat: Bool) -> TerminalViewMode {
        guard chatAvailable(supportsChat: supportsChat, humanActions: humanActions, windowChat: windowChat) else {
            return .terminal
        }
        return choice ?? .chat
    }
}

/// Escolha "Chat | Terminal" por janela, enquanto o app viver (nao vai para o disco).
@MainActor @Observable
final class TerminalModeMemory {
    static let shared = TerminalModeMemory()
    private var choices: [String: TerminalViewMode] = [:]

    private func key(_ session: String, _ window: String) -> String { session + "|" + window }

    func choice(session: String, window: String) -> TerminalViewMode? {
        choices[key(session, window)]
    }

    func set(_ mode: TerminalViewMode, session: String, window: String) {
        choices[key(session, window)] = mode
    }
}

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
    @State private var detailLoaded = false
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
    private var memory: TerminalModeMemory { TerminalModeMemory.shared }

    private var activeWindow: WindowInfo? {
        guard let id = shownID else { return nil }
        return detail?.window(id: id)
    }
    private var serverSupportsChat: Bool { store.info?.supportsChat == true && store.humanActions }
    private var chatAvailable: Bool {
        TerminalPolicy.chatAvailable(supportsChat: store.info?.supportsChat == true,
                                     humanActions: store.humanActions,
                                     windowChat: activeWindow?.chat == true)
    }
    /// nil = ainda decidindo (servidor com chat e detalhe da sessao nao chegou): evita abrir o socket a toa.
    private var mode: TerminalViewMode? {
        if serverSupportsChat, !detailLoaded { return nil }
        guard let w = activeWindow else { return .terminal }
        return TerminalPolicy.mode(
            choice: memory.choice(session: route.session, window: w.id),
            supportsChat: store.info?.supportsChat == true,
            humanActions: store.humanActions,
            windowChat: w.chat)
    }
    private var phoneView: Bool { store.info?.supportsPhoneView == true }
    /// Colunas do PTY para ajustar a fonte; 0 = como hoje.
    private var fitCols: Int { phoneView ? (activeWindow?.cols ?? 0) : 0 }

    var body: some View {
        VStack(spacing: 0) {
            header
            modePicker
            ZStack {
                switch mode {
                case .chat:
                    if let w = activeWindow {
                        ChatView(session: route.session, window: w.id, onShowTerminal: { setMode(.terminal) })
                            .id(w.id)
                    }
                case .terminal:
                    TerminalContainer(
                        connection: connection,
                        fontSize: CGFloat(fontSize),
                        fitCols: fitCols,
                        snippets: snippets,
                        onCopyRequest: { copyPayload = CopyPayload(text: $0) },
                        onWindowSwipe: { swipe($0) },
                        onFontSizeChange: { fontSize = Double($0) }
                    )
                    .accessibilityIdentifier("terminal")
                case nil:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
            // No Chat o socket fica fechado: nada a reconectar.
            guard mode == .terminal else { return }
            switch connection.status {
            case .denied, .connecting, .reconnecting: break
            case .idle: syncConnection(switching: false)
            default: connection.reconnectNow()
            }
        }
        .onChange(of: detail) { _, new in
            // Janela do celular fechada (no PC ou pelo app): volta ao foco do daemon.
            guard let id = current, let new, new.window(id: id) == nil else { return }
            store.forgetWindow(in: route.session)
            current = nil
            syncConnection(switching: true)
        }
        .onChange(of: mode) { _, _ in syncConnection(switching: false) }
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

    /// "Chat | Terminal": so aparece quando a janela tem chat disponivel.
    @ViewBuilder
    private var modePicker: some View {
        if chatAvailable, let w = activeWindow, let mode {
            Picker("Modo", selection: Binding(get: { mode }, set: { setMode($0) })) {
                ForEach(TerminalViewMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(Color(uiColor: Theme.mantle))
            .accessibilityIdentifier("seletor-modo")
            .id(w.id)
        }
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
        guard terminalURL() != nil else {
            badURL = true
            return
        }
        started = true
        detailLoaded = true
        syncConnection(switching: false)
    }

    /// `/ws` satelite; com `phone_view` o servidor desenha so o painel, no tamanho do PTY.
    private func terminalURL() -> URL? {
        store.endpoints?.wsURL(session: route.session, window: current, phoneView: phoneView)
    }

    /// Liga o socket so no modo terminal; no Chat ele fica fechado.
    private func syncConnection(switching: Bool) {
        guard started else { return }
        switch mode {
        case .terminal:
            if connection.status == .idle {
                startTerminal()
            } else if switching {
                reconnect()
            }
        case .chat:
            if connection.status != .idle { connection.stop() }
        case nil:
            break
        }
    }

    private func startTerminal() {
        guard let url = terminalURL() else {
            badURL = true
            return
        }
        connection.start(url: url, authHeader: store.authHeader)
    }

    private func reconnect() {
        guard let url = terminalURL() else {
            badURL = true
            return
        }
        connection.switchTo(url: url)
    }

    private func setMode(_ new: TerminalViewMode) {
        guard let w = activeWindow else { return }
        memory.set(new, session: route.session, window: w.id)
        selectionTick += 1
    }

    private func select(_ id: String) {
        guard id != current else { return }
        current = id
        store.rememberWindow(id, in: route.session)
        selectionTick += 1
        syncConnection(switching: true)
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
