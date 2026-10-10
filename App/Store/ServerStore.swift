import Foundation
import Observation
import SwiftUI
import PoppyKit

/// Estado do servidor para toda a UI: sessoes, detalhe (workspaces/janelas), inbox,
/// contadores, estado de conexao e a ultima janela vista por sessao.
///
/// O celular nunca mexe no foco do PC: `WindowInfo.focused` e so informativo. A janela
/// do terminal e escolhida no `/ws` (`wsURL(session:window:)`) e lembrada aqui.
///
/// Ciclo de vida: `configure(...)` ao ter endereco, `scenePhaseChanged(_:)` a cada mudanca
/// de fase. O SSE reconecta sozinho (backoff 1-30 s) com `after_seq` + `boot_id`; ao voltar
/// ao primeiro plano o socket e refeito e tudo e rebuscado.
@MainActor
@Observable
final class ServerStore {
    // MARK: estado publico (somente leitura para as views)

    private(set) var connection: ConnectionState = .unconfigured
    private(set) var info: ServerInfo?
    private(set) var sessions: [SessionSummary] = []
    private(set) var sessionWarnings: [String] = []
    private(set) var details: [String: SessionDetail] = [:]
    private(set) var inbox: [InboxItem] = []
    private(set) var inboxCounts: [String: Int] = [:]
    private(set) var isRefreshing = false
    private(set) var hasLoaded = false
    /// Ultimo erro de uma acao (aprovar, criar janela...), para a UI mostrar e limpar.
    var actionError: APIError?

    /// Aprovar/responder/dispensar so com login Tailscale aceito pelo servidor.
    var humanActions: Bool { info?.humanActions ?? false }
    /// Itens que bloqueiam um agente (badge da aba Agentes).
    var needsYouItems: [InboxItem] { inbox.filter { $0.kind.needsYou } }
    var needsYouCount: Int { needsYouItems.count }
    var endpoints: Endpoints? { client?.endpoints }
    /// Cliente atual da API (o chat monta o proprio backend em cima dele).
    var apiClient: APIClient? { client }
    var defaultSession: String { info?.defaultSession ?? "" }

    // MARK: internos

    @ObservationIgnored private var client: APIClient?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let notifier: AttentionNotifier
    /// Face ID: toda ordem de pessoa (aprovar, responder) passa por aqui antes de ir ao servidor.
    @ObservationIgnored let gate: AuthGate
    @ObservationIgnored private var cursor = EventCursor()
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var watched: Set<String> = []
    @ObservationIgnored private var knownInboxIDs: Set<String> = []
    @ObservationIgnored private var inboxSeeded = false
    @ObservationIgnored private var appActive = true
    @ObservationIgnored private var lastWindows: [String: String]
    @ObservationIgnored private let policy = ReconnectPolicy()

    private static let lastWindowKey = "lastWindowBySession"

    init(defaults: UserDefaults = .standard, notifier: AttentionNotifier = AttentionNotifier(),
         gate: AuthGate = AuthGate.live()) {
        self.defaults = defaults
        self.notifier = notifier
        self.gate = gate
        if let data = defaults.data(forKey: Self.lastWindowKey),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            lastWindows = map.filter { SessionName.isValid($0.key) && Endpoints.isValidWindowID($0.value) }
        } else {
            lastWindows = [:]
        }
        // Abertura do app: apaga cache de chat vencido (7 dias) ou ilegivel, fora da thread principal.
        Task.detached(priority: .utility) { ChatCache.shared.sweep() }
    }

    // MARK: configuracao

    /// Cabecalho Authorization do cliente atual (o mesmo do APIClient); nil sem Basic.
    var authHeader: String? { client?.authHeader }

    /// Chame ao abrir o app e sempre que endereco/usuario/senha mudarem.
    /// `password` vazio = sem Basic (login Tailscale).
    func configure(serverURL: String, user: String, password: String) {
        let auth = password.isEmpty ? nil : BasicAuth.header(user: user, password: password)
        guard let endpoints = Endpoints(serverURL: serverURL) else {
            stop()
            if client != nil { ChatCache.shared.removeAll() }
            client = nil
            connection = .unconfigured
            return
        }
        if let current = client, current.endpoints == endpoints, current.authHeader == auth { return }
        stop()
        // Reconfigurar (nao a primeira configuracao do app) apaga o cache do chat do servidor antigo.
        if client != nil { ChatCache.shared.removeAll() }
        client = APIClient(endpoints: endpoints, authHeader: auth)
        resetData()
        connection = .connecting
        if appActive { start() }
    }

    /// Conecta (refaz o SSE e rebusca tudo). Idempotente.
    func start() {
        guard client != nil else { return }
        eventTask?.cancel()
        if !hasLoaded { connection = .connecting }
        eventTask = Task { [weak self] in await self?.eventLoop() }
        refreshSoon(delay: 0)
    }

    func stop() {
        eventTask?.cancel(); eventTask = nil
        refreshTask?.cancel(); refreshTask = nil
    }

    /// Ligar ao `scenePhase`: ativo reconecta e recupera; background segura ~30 s.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            appActive = true
            notifier.endGrace()
            start() // o iOS mata o socket em segundo plano: refaz sempre
        case .background:
            appActive = false
            notifier.beginGrace { [weak self] in self?.stop() }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: leitura

    /// Rebusca sessoes, inbox e os detalhes observados. Pull-to-refresh chama isto.
    func refreshAll() async {
        guard let client else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if info == nil || !connection.isOnline {
                let i = try await client.info()
                info = i
                let state = ConnectionState.from(i)
                connection = state
                if !state.isOnline && !i.daemonOk { return }
            }
            async let s = client.sessions()
            async let b = client.inbox()
            let (sess, box) = try await (s, b)
            sessions = sess.sessions
            sessionWarnings = sess.warnings
            applyInbox(box)
            for name in watched {
                if let d = try? await client.session(name) { details[name] = d }
            }
            hasLoaded = true
            if case .daemonOld = connection {} else { connection = .online }
        } catch {
            fail(APIError.from(error))
        }
    }

    /// Carrega o detalhe de uma sessao e passa a mante-lo atualizado pelos eventos.
    @discardableResult
    func loadDetail(_ session: String) async -> SessionDetail? {
        guard let client else { return nil }
        watched.insert(session)
        do {
            let d = try await client.session(session)
            details[session] = d
            return d
        } catch {
            fail(APIError.from(error))
            return details[session]
        }
    }

    func stopWatching(_ session: String) { watched.remove(session) }

    /// Detalhe de um item da inbox (comando mono, opcoes). Nao muda o estado da store.
    func prompt(for item: InboxItem) async throws -> PromptInfo {
        try await run { try await $0.prompt(itemID: item.id) }
    }

    // MARK: ultima janela por sessao (persistida)

    func lastWindow(for session: String) -> String? { lastWindows[session] }

    /// Janela a abrir ao entrar na sessao: a ultima usada, se ainda existir; senao nil
    /// (o `/ws` abre no foco do daemon).
    func windowToOpen(in session: String) -> String? {
        guard let id = lastWindows[session] else { return nil }
        if let d = details[session], d.window(id: id) == nil { return nil }
        return id
    }

    func rememberWindow(_ id: String, in session: String) {
        guard SessionName.isValid(session), Endpoints.isValidWindowID(id), lastWindows[session] != id else { return }
        lastWindows[session] = id
        persistLastWindows()
    }

    func forgetWindow(in session: String) {
        guard lastWindows.removeValue(forKey: session) != nil else { return }
        persistLastWindows()
    }

    /// URL do `/ws` satelite para a sessao/janela (foco so do celular).
    func terminalURL(session: String, window: String?) -> URL? {
        endpoints?.wsURL(session: session, window: window)
    }

    // MARK: sessoes e janelas

    func createSession(name: String) async throws {
        _ = try await run { try await $0.createSession(name: name) }
        await refreshAll()
    }

    /// Cria uma janela SEM tirar o foco do PC. Devolve o id para abrir o terminal nela.
    @discardableResult
    func createWindow(in session: String, name: String? = nil, workspace: Int? = nil) async throws -> CreatedWindow {
        let w = try await run { try await $0.createWindow(session: session, name: name, workspace: workspace) }
        _ = await loadDetail(session)
        refreshSoon()
        return w
    }

    func closeWindow(session: String, id: String) async throws {
        try await run { try await $0.closeWindow(session: session, id: id) }
        if lastWindows[session] == id { forgetWindow(in: session) }
        _ = await loadDetail(session)
        refreshSoon()
    }

    // MARK: acoes de pessoa

    /// `summary` = a linha que a pessoa viu (o servidor grava no log).
    func reply(to item: InboxItem, decision: ReplyDecision, riskAck: [String]? = nil, message: String? = nil) async throws {
        // Negar (e "perguntar no terminal") nao pedem Face ID; aprovar pede, e risco alto pede sempre.
        if decision == .once || decision == .always {
            try await authorize(highRisk: item.hasRisk)
        }
        let req = ReplyRequest(decision: decision, message: message,
                               riskAck: (riskAck?.isEmpty == false) ? riskAck : nil,
                               summary: item.summary.isEmpty ? nil : item.summary, planSha: item.planSha)
        let r = try await human { try await $0.reply(itemID: item.id, req) }
        if r.applied { resolved(item) } else { refreshSoon() }
    }

    func answer(_ item: InboxItem, with answer: String) async throws {
        try await authorize(highRisk: item.hasRisk)
        let r = try await human { try await $0.answer(itemID: item.id, answer: answer, question: item.summary) }
        if r.applied { resolved(item) } else { refreshSoon() }
    }

    func respond(to item: InboxItem, action: String, value: String? = nil, promptId: String, riskAck: [String]? = nil) async throws {
        if !Self.actionsWithoutAuth.contains(action) {
            try await authorize(highRisk: item.hasRisk)
        }
        _ = try await human {
            try await $0.respond(itemID: item.id, RespondRequest(action: action, value: value, promptId: promptId, riskAck: riskAck))
        }
        resolved(item)
    }

    func dismiss(_ item: InboxItem) async throws {
        try await human { try await $0.dismiss(itemID: item.id) }
        resolved(item)
    }

    // MARK: interno - Face ID

    /// Acoes de `respond` que so recusam/interrompem: nao pedem Face ID.
    static let actionsWithoutAuth: Set<String> = ["deny", "interrupt", "cancel"]

    /// Pede Face ID (ou a reserva) antes da ordem. Falha vira um `APIError` (`face_id_required`), que a UI
    /// ja mostra como erro de acao; nada e enviado ao servidor.
    func authorize(highRisk: Bool) async throws {
        do {
            try await gate.authorize(highRisk: highRisk)
        } catch {
            let e = AuthGate.apiError(for: error)
            actionError = e
            throw e
        }
    }

    // MARK: interno - chamadas

    private func run<T: Sendable>(_ op: @Sendable (APIClient) async throws -> T) async throws -> T {
        guard let client else { throw APIError.invalidArgument("Servidor nao configurado.") }
        do {
            return try await op(client)
        } catch {
            let e = APIError.from(error)
            noteConnectionFailure(e)
            actionError = e
            throw e
        }
    }

    /// Acoes de pessoa: 1/s no servidor; uma repeticao automatica se `rate_limited` curto.
    private func human<T: Sendable>(_ op: @Sendable (APIClient) async throws -> T) async throws -> T {
        do {
            return try await run(op)
        } catch let e as APIError where e.kind == .rateLimited {
            let wait = min(max(e.retryAfter ?? 1, 0.2), 2.0)
            try? await Task.sleep(for: .seconds(wait))
            actionError = nil
            return try await run(op)
        }
    }

    private func resolved(_ item: InboxItem) {
        inbox.removeAll { $0.id == item.id }
        knownInboxIDs.remove(item.id)
        notifier.clear(itemIDs: [item.id])
        refreshSoon()
    }

    // MARK: interno - estado

    private func resetData() {
        info = nil; sessions = []; sessionWarnings = []; details = [:]
        inbox = []; inboxCounts = [:]; knownInboxIDs = []; inboxSeeded = false
        hasLoaded = false; cursor.reset(); watched = []
    }

    private func applyInbox(_ box: InboxResponse) {
        let fresh = box.items.filter { !knownInboxIDs.contains($0.id) }
        let gone = knownInboxIDs.subtracting(box.items.map(\.id))
        knownInboxIDs = Set(box.items.map(\.id))
        inbox = box.items
        inboxCounts = box.counts
        if !gone.isEmpty { notifier.clear(itemIDs: Array(gone)) }
        if inboxSeeded && !fresh.isEmpty {
            notifier.notify(newItems: fresh, appIsActive: appActive)
        }
        if !inboxSeeded {
            inboxSeeded = true
            Task { await notifier.requestAuthorizationIfNeeded() }
        }
    }

    private func fail(_ error: APIError) {
        noteConnectionFailure(error)
    }

    private func noteConnectionFailure(_ error: APIError) {
        switch error.kind {
        case .networkUnreachable, .accessDenied, .daemonUnreachable, .daemonTooOld:
            var state = ConnectionState.from(error)
            if case .daemonOld = state, let i = info { state = .daemonOld(missing: i.missingVerbs) }
            connection = state
        case .other:
            // Falha generica de uma chamada: so vira estado se ainda nao ha dados.
            if !hasLoaded { connection = ConnectionState.from(error) }
        default:
            break // erros de acao (item sumiu, rate limit...) nao derrubam a conexao
        }
    }

    private func persistLastWindows() {
        if let data = try? JSONEncoder().encode(lastWindows) {
            defaults.set(data, forKey: Self.lastWindowKey)
        }
    }

    // MARK: interno - eventos

    /// Junta varios eventos seguidos em um unico refetch.
    private func refreshSoon(delay: Double = 0.3) {
        if refreshTask != nil, delay > 0 { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            await self.refreshAll()
            self.refreshTask = nil
        }
    }

    private func eventLoop() async {
        var attempt = 0
        while !Task.isCancelled, let client {
            do {
                let stream = client.events(afterSeq: cursor.seq, bootID: cursor.bootID)
                for try await sse in stream {
                    if Task.isCancelled { return }
                    switch cursor.apply(sse) {
                    case .ready:
                        attempt = 0
                        if !connection.isOnline, case .daemonOld = connection {} else { connection = .online }
                    case .refetch:
                        refreshSoon(delay: 0)
                    case .event:
                        handle(ServerEvent(sse))
                    }
                }
                // O servidor fechou o fluxo sem erro: reconecta logo, retomando de onde parou.
                attempt = 0
                try? await Task.sleep(for: .seconds(1))
            } catch {
                if Task.isCancelled { return }
                let e = APIError.from(error)
                noteConnectionFailure(e)
                if e.kind == .accessDenied { return } // credencial errada: nao martela o servidor
                if e.kind == .daemonTooOld { return }
                let wait = max(policy.delay(forAttempt: attempt), e.retryAfter ?? 0)
                attempt += 1
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private func handle(_ ev: ServerEvent) {
        switch ev.kind {
        case .agentState, .attention, .notification,
             .sessionCreated, .sessionClosed,
             .windowCreated, .windowClosed, .windowRetitled:
            refreshSoon()
        case .windowFocused, .workspaceSwitched:
            // Foco e do PC; o app nao segue. So atualiza o rotulo "em foco no PC".
            if let s = ev.session, watched.contains(s) { refreshSoon(delay: 1) }
        default:
            break
        }
    }
}
