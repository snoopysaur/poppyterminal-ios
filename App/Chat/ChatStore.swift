import Foundation
import Observation
import SwiftUI
import os
import PoppyKit

// MARK: - acesso ao servidor (costura para teste)

/// O que o ChatStore precisa do servidor. Em producao e o `APIClient`; nos testes, um falso.
protocol ChatBackend: Sendable {
    func page(before: String?, limit: Int) async throws -> ChatPage
    func send(text: String) async throws -> ChatSendResult
    func interrupt() async throws -> ChatSendResult
    func events(after: String?) -> AsyncThrowingStream<ChatEvent, Error>
}

struct APIChatBackend: ChatBackend {
    let client: APIClient
    let session: String
    let window: String

    func page(before: String?, limit: Int) async throws -> ChatPage {
        try await client.chat(session: session, window: window, before: before, limit: limit)
    }
    func send(text: String) async throws -> ChatSendResult {
        try await client.sendChat(session: session, window: window, text: text)
    }
    func interrupt() async throws -> ChatSendResult {
        try await client.interruptChat(session: session, window: window)
    }
    func events(after: String?) -> AsyncThrowingStream<ChatEvent, Error> {
        client.chatEvents(session: session, window: window, after: after)
    }
}

/// Servidor nao configurado: toda chamada falha com a mensagem padrao.
private struct UnavailableChatBackend: ChatBackend {
    private var failure: APIError { .invalidArgument("Servidor não configurado.") }
    func page(before: String?, limit: Int) async throws -> ChatPage { throw failure }
    func send(text: String) async throws -> ChatSendResult { throw failure }
    func interrupt() async throws -> ChatSendResult { throw failure }
    func events(after: String?) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: failure) }
    }
}

// MARK: - store

/// Estado de uma conversa (uma janela): cache offline, GET inicial, stream com reconexao,
/// envio com bolha local e paginacao para tras. Contrato: `poppyterminal-ios-v030-contrato.md` §7 e §8.3.
@MainActor
@Observable
final class ChatStore {
    enum Phase: Equatable {
        case loading
        case offline(savedAt: Date)
        case live
        case unsupported(ChatUnsupportedReason)
        case failed(String)
    }

    /// Bolha local da mensagem que acabou de ser enviada, ate chegar a do transcript.
    struct Outgoing: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let sentAt: Date
    }

    static let maxVisible = 500
    static let pageSize = 50

    let session: String
    let window: String

    private(set) var phase: Phase = .loading
    /// Visiveis (sem tool_result), antigo para novo, sem repetir id, no maximo 500.
    private(set) var messages: [ChatMessage] = []
    /// Resultado de cada ferramenta, por `tool_use_id`.
    private(set) var toolResults: [String: ChatToolResult] = [:]
    private(set) var hasMore = false
    private(set) var isLoadingOlder = false
    private(set) var agentState = "idle"
    private(set) var pending: PendingPrompt?
    private(set) var sending = false
    private(set) var outgoing: Outgoing?
    private(set) var lastError: APIError?
    var draft = ""

    @ObservationIgnored private let backend: ChatBackend
    @ObservationIgnored private let cache: ChatCache
    @ObservationIgnored private let serverKey: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let outgoingTimeout: Duration
    @ObservationIgnored private let policy = ReconnectPolicy()
    @ObservationIgnored private static let log = Logger(subsystem: "io.github.snoopysaur.poppyterminal", category: "chat")

    /// Todas as mensagens aceitas (inclui tool_result), na ordem do servidor.
    @ObservationIgnored private var raw: [ChatMessage] = []
    @ObservationIgnored private var ids: Set<String> = []
    @ObservationIgnored private var conversationId = ""
    @ObservationIgnored private var newestCursor: String?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var initialDone = false
    @ObservationIgnored private var synced = false          // o GET respondeu nesta execucao
    @ObservationIgnored private var streamAllowed = true
    @ObservationIgnored private var lastEventAt: Date?
    @ObservationIgnored private var reconnectAttempt = 0
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    init(session: String, window: String, store: ServerStore, cache: ChatCache = .shared) {
        self.session = session
        self.window = window
        self.backend = store.apiClient.map { APIChatBackend(client: $0, session: session, window: window) }
            ?? UnavailableChatBackend()
        self.cache = cache
        self.serverKey = store.endpoints?.base.absoluteString ?? ""
        self.now = { Date() }
        self.outgoingTimeout = .seconds(30)
    }

    /// Para testes: backend, relogio e prazo da bolha injetados.
    init(session: String, window: String, serverKey: String, backend: ChatBackend, cache: ChatCache,
         now: @escaping @Sendable () -> Date = { Date() }, outgoingTimeout: Duration = .seconds(30)) {
        self.session = session
        self.window = window
        self.backend = backend
        self.cache = cache
        self.serverKey = serverKey
        self.now = now
        self.outgoingTimeout = outgoingTimeout
    }

    // MARK: ciclo de vida

    /// Cache, depois GET, depois o stream (que segue sozinho, com reconexao).
    func start() async {
        guard !started else { return }
        started = true
        streamAllowed = true
        initialDone = false
        if raw.isEmpty {
            phase = .loading
            let t0 = ContinuousClock.now
            if let file = cache.load(server: serverKey, session: session, window: window, now: now()) {
                applyCache(file)
            }
            let elapsed = ContinuousClock.now - t0
            if elapsed > .milliseconds(50) {
                Self.log.debug("abrir o cache do chat passou de 50 ms: \(String(describing: elapsed), privacy: .public)")
            }
        }
        await firstLoad()
        guard started else { return }
        initialDone = true
        if streamAllowed { startStream() }
    }

    /// Cancela o stream e salva o cache.
    func stop() {
        started = false
        initialDone = false
        streamTask?.cancel(); streamTask = nil
        expiryTask?.cancel(); expiryTask = nil
        saveCache()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            saveCache()
            streamTask?.cancel(); streamTask = nil   // o iOS mata o socket em segundo plano
        case .active:
            if started, initialDone, streamAllowed, streamTask == nil { startStream() }
        default:
            break
        }
    }

    // MARK: paginacao

    func loadOlder() async {
        guard hasMore, !isLoadingOlder, let oldest = raw.first?.cursor, !oldest.isEmpty else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await backend.page(before: oldest, limit: Self.pageSize)
            guard started else { return }
            if !page.supported {
                setUnsupported(page.unsupportedReason ?? .other)
                return
            }
            prepend(page)
        } catch {
            let e = APIError.from(error)
            if e.kind == .cursorStale {
                await resetAndReload(conversation: nil, cursor: nil)
            } else if !Task.isCancelled {
                lastError = e
            }
        }
    }

    // MARK: envio

    func send() async {
        guard !sending, pending == nil else { return }
        let text = draft
        if let problem = ChatText.validate(text) {
            lastError = .invalidArgument(problem)
            return
        }
        sending = true
        lastError = nil
        let bubble = Outgoing(text: text, sentAt: now())
        outgoing = bubble
        draft = ""
        do {
            _ = try await withRateRetry { try await self.backend.send(text: text) }
            sending = false
            if outgoing?.id == bubble.id { scheduleExpiry(of: bubble.id) }
        } catch {
            sending = false
            if outgoing?.id == bubble.id { outgoing = nil }
            if draft.isEmpty { draft = text }
            lastError = APIError.from(error)
        }
    }

    func interrupt() async {
        lastError = nil
        do {
            _ = try await withRateRetry { try await self.backend.interrupt() }
        } catch {
            lastError = APIError.from(error)
        }
    }

    func clearError() { lastError = nil }

    /// "Tentar de novo" da tela de falha.
    func retry() async {
        stop()
        await start()
    }

    /// Acoes de pessoa: 1/s no servidor; uma repeticao curta se `rate_limited`.
    private func withRateRetry<T: Sendable>(_ op: @escaping () async throws -> T) async throws -> T {
        do { return try await op() } catch {
            let e = APIError.from(error)
            guard e.kind == .rateLimited else { throw e }
            let wait = min(max(e.retryAfter ?? 1, 0.2), 2.0)
            try? await Task.sleep(for: .seconds(wait))
            return try await op()
        }
    }

    private func scheduleExpiry(of id: UUID) {
        expiryTask?.cancel()
        let timeout = outgoingTimeout
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.outgoing?.id == id else { return }
            self.outgoing = nil
        }
    }

    // MARK: carga inicial

    private func applyCache(_ file: ChatCacheFile) {
        raw = file.messages.filter(Self.isStorable)
        conversationId = file.conversationId
        newestCursor = file.messages.last(where: { !$0.cursor.isEmpty })?.cursor
        hasMore = !raw.isEmpty
        rebuild()
        phase = .offline(savedAt: file.savedAt)
    }

    private func firstLoad() async {
        do {
            let page = try await backend.page(before: nil, limit: Self.pageSize)
            guard started else { return }
            applyFirstPage(page, replaceExisting: true)
        } catch {
            guard started, !Task.isCancelled else { return }
            let e = APIError.from(error)
            lastError = e
            switch e.kind {
            case .humanRequiresTailscale, .accessDenied, .daemonTooOld, .invalidParams:
                streamAllowed = false
            default:
                break
            }
            if raw.isEmpty { phase = .failed(e.userMessage) }
        }
    }

    /// `replaceExisting`: o que ja existe veio do cache. Sem sobreposicao com a pagina, o cache
    /// tem buraco e e descartado. Sem isso (reset), o que existe veio do stream e e mais novo.
    private func applyFirstPage(_ page: ChatPage, replaceExisting: Bool) {
        guard page.supported else {
            setUnsupported(page.unsupportedReason ?? .other)
            return
        }
        if !conversationId.isEmpty, !page.conversationId.isEmpty, conversationId != page.conversationId {
            raw = []
            cache.remove(server: serverKey, session: session, window: window)
            newestCursor = nil
        }
        let incoming = page.messages.filter(Self.isStorable)
        if raw.isEmpty {
            raw = incoming
            hasMore = page.hasMore
        } else if let first = incoming.first, let idx = raw.firstIndex(where: { $0.id == first.id }) {
            let pageIDs = Set(incoming.map(\.id))
            let older = Array(raw[..<idx])
            let newer = raw[idx...].filter { !pageIDs.contains($0.id) }
            raw = older + incoming + newer
            hasMore = idx > 0 ? true : page.hasMore
        } else if !incoming.isEmpty {
            let pageIDs = Set(incoming.map(\.id))
            raw = replaceExisting ? incoming : incoming + raw.filter { !pageIDs.contains($0.id) }
            if replaceExisting { hasMore = page.hasMore }
        }
        if !page.conversationId.isEmpty { conversationId = page.conversationId }
        agentState = page.state
        pending = page.pending
        advanceCursor(page.newestCursor)
        if let last = raw.last(where: { !$0.cursor.isEmpty }) { advanceCursor(last.cursor) }
        trimToLimit()
        rebuild()
        synced = true
        lastEventAt = now()
        phase = .live
    }

    private func setUnsupported(_ reason: ChatUnsupportedReason) {
        phase = .unsupported(reason)
        streamAllowed = false
        streamTask?.cancel(); streamTask = nil
        raw = []
        rebuild()
        hasMore = false
        pending = nil
        cache.remove(server: serverKey, session: session, window: window)
    }

    // MARK: stream

    private func startStream() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in await self?.streamLoop() }
    }

    private func streamLoop() async {
        while !Task.isCancelled {
            do {
                for try await event in backend.events(after: newestCursor) {
                    if Task.isCancelled { return }
                    guard await handle(event) else { return }
                }
                // Fechado sem erro: reconecta logo, retomando do ultimo cursor.
                try? await Task.sleep(for: .seconds(1))
            } catch {
                if Task.isCancelled { return }
                let e = APIError.from(error)
                markOffline()
                switch e.kind {
                case .humanRequiresTailscale, .accessDenied, .daemonTooOld, .notChat, .remoteWindow, .invalidParams:
                    lastError = e
                    streamAllowed = false
                    return
                default:
                    break
                }
                let wait = max(policy.delay(forAttempt: reconnectAttempt), e.retryAfter ?? 0)
                reconnectAttempt += 1
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private func markOffline() {
        if case .live = phase { phase = .offline(savedAt: lastEventAt ?? now()) }
    }

    /// `false` encerra o laco (sem chat nesta janela).
    private func handle(_ event: ChatEvent) async -> Bool {
        lastEventAt = now()
        switch event {
        case let .ready(conversation, _, state, pendingPrompt):
            reconnectAttempt = 0
            if !conversationId.isEmpty, !conversation.isEmpty, conversation != conversationId {
                await resetAndReload(conversation: conversation, cursor: nil)
                return streamAllowed
            }
            if conversationId.isEmpty { conversationId = conversation }
            agentState = state
            pending = pendingPrompt
            if !synced {
                do {
                    let page = try await backend.page(before: nil, limit: Self.pageSize)
                    guard started else { return false }
                    applyFirstPage(page, replaceExisting: true)
                } catch {
                    lastError = APIError.from(error)
                }
            }
            if synced { phase = .live }
            return streamAllowed
        case let .message(message):
            ingest(message)
        case let .reset(conversation, _, cursor):
            await resetAndReload(conversation: conversation, cursor: cursor)
            return streamAllowed
        case let .state(state, pendingPrompt):
            agentState = state
            pending = pendingPrompt
        case let .unsupported(reason):
            setUnsupported(ChatUnsupportedReason(reason: reason))
            return false
        case .ping, .unknown:
            break
        }
        return true
    }

    /// `reset` do stream (ou `cursor_stale`): limpa lista e cache da janela e refaz o GET sem `before`.
    private func resetAndReload(conversation: String?, cursor: String?) async {
        raw = []
        ids = []
        hasMore = false
        cache.remove(server: serverKey, session: session, window: window)
        conversationId = conversation ?? ""
        newestCursor = (cursor?.isEmpty == false) ? cursor : nil
        rebuild()
        do {
            let page = try await backend.page(before: nil, limit: Self.pageSize)
            guard started else { return }
            applyFirstPage(page, replaceExisting: false)
        } catch {
            let e = APIError.from(error)
            lastError = e
            synced = false
            if raw.isEmpty { phase = .failed(e.userMessage) }
        }
    }

    // MARK: lista

    /// So o que a UI sabe desenhar: papel e tipo conhecidos, e o conteudo que o tipo exige.
    private static func isStorable(_ m: ChatMessage) -> Bool {
        guard !m.id.isEmpty, m.role != .unknown else { return false }
        switch m.kind {
        case .unknown: return false
        case .toolUse: return m.tool != nil
        case .toolResult: return m.result != nil
        case .text, .image, .interrupted: return true
        }
    }

    private func ingest(_ m: ChatMessage) {
        advanceCursor(m.cursor)
        guard Self.isStorable(m), !ids.contains(m.id) else { return }
        raw.append(m)
        if m.role == .user, m.kind == .text, let o = outgoing,
           Self.normalized(m.text) == Self.normalized(o.text) {
            outgoing = nil
            expiryTask?.cancel()
        }
        trimToLimit()
        rebuild()
    }

    private func prepend(_ page: ChatPage) {
        let fresh = page.messages.filter { Self.isStorable($0) && !ids.contains($0.id) }
        var merged = fresh + raw
        hasMore = page.hasMore
        let visible = Self.visibleCount(merged)
        if visible > Self.maxVisible {
            // Respeita o teto de 500: fica com o mais novo e para de paginar.
            merged.removeFirst(Self.cutIndex(merged, dropping: visible - Self.maxVisible))
            hasMore = false
        }
        raw = merged
        rebuild()
    }

    /// Passa de 500 visiveis: some o mais antigo (e os tool_result antes do primeiro que fica).
    private func trimToLimit() {
        let visible = Self.visibleCount(raw)
        guard visible > Self.maxVisible else { return }
        raw.removeFirst(Self.cutIndex(raw, dropping: visible - Self.maxVisible))
        hasMore = true
    }

    private static func visibleCount(_ list: [ChatMessage]) -> Int {
        list.reduce(0) { $0 + ($1.kind == .toolResult ? 0 : 1) }
    }

    /// Indice do primeiro item que fica depois de descartar os `drop` visiveis mais antigos.
    private static func cutIndex(_ list: [ChatMessage], dropping drop: Int) -> Int {
        var seen = 0
        for (i, m) in list.enumerated() where m.kind != .toolResult {
            seen += 1
            if seen == drop + 1 { return i }
        }
        return list.count
    }

    private func rebuild() {
        var visible: [ChatMessage] = []
        var results: [String: ChatToolResult] = [:]
        visible.reserveCapacity(raw.count)
        for m in raw {
            if m.kind == .toolResult {
                if let r = m.result { results[r.toolUseId] = r }
            } else {
                visible.append(m)
            }
        }
        ids = Set(raw.map(\.id))
        if messages != visible { messages = visible }
        if toolResults != results { toolResults = results }
    }

    // MARK: cursor e cache

    /// Guarda o cursor mais novo (mesma conversa: maior offset; conversa diferente: o recebido).
    private func advanceCursor(_ cursor: String) {
        guard !cursor.isEmpty else { return }
        guard let current = newestCursor, let a = Self.parse(current), let b = Self.parse(cursor),
              a.conversation == b.conversation else {
            newestCursor = cursor
            return
        }
        if b.offset >= a.offset { newestCursor = cursor }
    }

    private static func parse(_ cursor: String) -> (conversation: Substring, offset: Int)? {
        guard let dot = cursor.lastIndex(of: "."), let off = Int(cursor[cursor.index(after: dot)...]) else { return nil }
        return (cursor[..<dot], off)
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// So salva depois de falar com o servidor nesta execucao (nao renova a validade de dado velho).
    private func saveCache() {
        guard synced, !conversationId.isEmpty, !raw.isEmpty else { return }
        switch phase {
        case .live, .offline:
            cache.save(ChatCacheFile(v: ChatCache.formatVersion, server: serverKey, session: session, window: window,
                                     conversationId: conversationId, savedAt: now(), messages: raw))
        default:
            break
        }
    }

    // MARK: leitura para testes

    var currentConversationId: String { conversationId }
    var currentCursor: String? { newestCursor }
}
