import XCTest
import PoppyKit
@testable import PoppyTerminal

/// Backend falso: respostas do GET em fila, stream controlado pelo teste.
final class FakeChatBackend: ChatBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Result<ChatPage, Error>] = []
    private var cont: AsyncThrowingStream<ChatEvent, Error>.Continuation?
    private var _calls: [(before: String?, limit: Int)] = []
    private var _afters: [String?] = []
    private var _sent: [String] = []
    private var _interrupts = 0
    var sendError: Error?

    func enqueue(_ page: ChatPage) { lock.withLock { queue.append(.success(page)) } }
    func enqueue(error: Error) { lock.withLock { queue.append(.failure(error)) } }
    var calls: [(before: String?, limit: Int)] { lock.withLock { _calls } }
    var afters: [String?] { lock.withLock { _afters } }
    var sent: [String] { lock.withLock { _sent } }
    var interrupts: Int { lock.withLock { _interrupts } }
    var hasStream: Bool { lock.withLock { cont != nil } }

    func emit(_ event: ChatEvent) { _ = lock.withLock { cont }?.yield(event) }
    func failStream(_ error: Error) { lock.withLock { cont }?.finish(throwing: error) }

    func page(before: String?, limit: Int) async throws -> ChatPage {
        let next: Result<ChatPage, Error>? = lock.withLock {
            _calls.append((before, limit))
            return queue.isEmpty ? nil : queue.removeFirst()
        }
        switch next {
        case .success(let p): return p
        case .failure(let e): throw e
        case nil: return ChatPage(conversationId: "ab1f47251fd3fea5")
        }
    }

    func send(text: String) async throws -> ChatSendResult {
        if let sendError { throw sendError }
        lock.withLock { _sent.append(text) }
        return ChatSendResult(sent: true, at: 1)
    }

    func interrupt() async throws -> ChatSendResult {
        lock.withLock { _interrupts += 1 }
        return ChatSendResult(sent: true, at: 1)
    }

    func events(after: String?) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { c in
            lock.withLock { _afters.append(after); cont = c }
        }
    }
}

@MainActor
final class ChatStoreTests: XCTestCase {
    private let conv = "ab1f47251fd3fea5"
    private let server = "http://exemplo.invalid:8080"
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private var dir: URL!
    private var cache: ChatCache!
    private var backend: FakeChatBackend!
    private var stores: [ChatStore] = []

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("chatstore-\(UUID().uuidString)")
        cache = ChatCache(directory: dir)
        backend = FakeChatBackend()
    }

    override func tearDown() async throws {
        for s in stores { s.stop() }
        stores = []
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: ajudantes

    private func make(timeout: Duration = .seconds(30)) -> ChatStore {
        let t0 = self.t0
        let s = ChatStore(session: "s1", window: "w1", serverKey: server, backend: backend, cache: cache,
                          now: { t0 }, outgoingTimeout: timeout)
        stores.append(s)
        return s
    }

    private func msg(_ i: Int, role: String = "assistant", kind: String = "text", text: String? = nil,
                     tool: ChatToolCall? = nil, result: ChatToolResult? = nil) -> ChatMessage {
        ChatMessage(id: "u\(i):0", cursor: "\(conv).\(i * 10)", ts: Int64(i), role: role, kind: kind,
                    text: kind == "text" ? (text ?? "msg \(i)") : "", tool: tool, result: result)
    }

    private func page(_ range: ClosedRange<Int>, hasMore: Bool = false, state: String = "idle",
                      pending: PendingPrompt? = nil, conversation: String? = nil) -> ChatPage {
        let list = range.map { msg($0) }
        return ChatPage(conversationId: conversation ?? conv, messages: list, hasMore: hasMore,
                        oldestCursor: list.first?.cursor ?? "", newestCursor: list.last?.cursor ?? "",
                        state: state, pending: pending)
    }

    private func cacheFile(_ range: ClosedRange<Int>, conversation: String? = nil) -> ChatCacheFile {
        ChatCacheFile(v: 1, server: server, session: "s1", window: "w1", conversationId: conversation ?? conv,
                      savedAt: t0.addingTimeInterval(-3600), messages: range.map { msg($0) })
    }

    private func eventually(_ what: String = "", _ cond: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if cond() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condicao nao chegou: \(what)", file: file, line: line)
    }

    private func started(_ s: ChatStore) async {
        await s.start()
        await eventually("stream aberto") { backend.hasStream }
    }

    private func ids(_ s: ChatStore) -> [String] { s.messages.map(\.id) }

    // MARK: carga

    func testAbreComGetEFicaLive() async {
        backend.enqueue(page(1...3, hasMore: true, state: "working"))
        let s = make()
        await started(s)
        XCTAssertEqual(s.phase, .live)
        XCTAssertEqual(ids(s), ["u1:0", "u2:0", "u3:0"])
        XCTAssertTrue(s.hasMore)
        XCTAssertEqual(s.agentState, "working")
        XCTAssertEqual(backend.calls.count, 1)
        XCTAssertNil(backend.calls[0].before)
        XCTAssertEqual(backend.afters.first, "\(conv).30", "o stream segue do ultimo cursor")
    }

    func testSemRedeFicaOfflineComCache() async {
        cache.save(cacheFile(1...3))
        backend.enqueue(error: APIError.network(.networkUnreachable))
        let s = make()
        await s.start()
        guard case .offline(let savedAt) = s.phase else { return XCTFail("esperava offline, veio \(s.phase)") }
        XCTAssertEqual(savedAt, t0.addingTimeInterval(-3600))
        XCTAssertEqual(ids(s).count, 3)
        XCTAssertNotNil(s.lastError)
    }

    func testSemRedeSemCacheFalha() async {
        backend.enqueue(error: APIError.network(.networkUnreachable))
        let s = make()
        await s.start()
        guard case .failed = s.phase else { return XCTFail("esperava failed, veio \(s.phase)") }
    }

    func testCacheSobrepostoComGetNaoDuplicaEMantemOsMaisAntigos() async {
        cache.save(cacheFile(1...6))
        backend.enqueue(page(4...8, hasMore: true))
        let s = make()
        await started(s)
        XCTAssertEqual(ids(s), (1...8).map { "u\($0):0" })
        XCTAssertTrue(s.hasMore)
    }

    func testCacheComBuracoEDescartado() async {
        cache.save(cacheFile(1...3))
        backend.enqueue(page(50...52, hasMore: true))
        let s = make()
        await started(s)
        XCTAssertEqual(ids(s), ["u50:0", "u51:0", "u52:0"])
    }

    func testConversaDiferenteDoCacheDescartaOCache() async {
        cache.save(cacheFile(1...3, conversation: "0000000000000000"))
        backend.enqueue(page(10...11))
        let s = make()
        await started(s)
        XCTAssertEqual(ids(s), ["u10:0", "u11:0"])
        XCTAssertEqual(s.currentConversationId, conv)
    }

    func testJanelaSemChatMostraUnsupportedEApagaOCache() async {
        cache.save(cacheFile(1...3))
        backend.enqueue(ChatPage(supported: false, reason: "no_agent"))
        let s = make()
        await s.start()
        XCTAssertEqual(s.phase, .unsupported(.noAgent))
        XCTAssertTrue(s.messages.isEmpty)
        XCTAssertNil(cache.load(server: server, session: "s1", window: "w1", now: t0))
        XCTAssertFalse(backend.hasStream, "sem chat nao abre stream")
    }

    // MARK: stream

    func testStreamDeduplicaPorIdEIgnoraDesconhecidos() async {
        backend.enqueue(page(1...2))
        let s = make()
        await started(s)
        backend.emit(.message(msg(2)))                       // repetida
        backend.emit(.message(msg(3)))
        backend.emit(.message(ChatMessage(id: "x:0", cursor: "\(conv).35", role: "assistant", kind: "novidade")))
        backend.emit(.message(ChatMessage(id: "y:0", cursor: "\(conv).36", role: "sistema", kind: "text", text: "?")))
        backend.emit(.message(msg(4)))
        await eventually("u4") { ids(s).contains("u4:0") }
        XCTAssertEqual(ids(s), ["u1:0", "u2:0", "u3:0", "u4:0"])
        XCTAssertEqual(s.currentCursor, "\(conv).40")
    }

    func testToolResultVaiParaToolResultsENaoParaMessages() async {
        backend.enqueue(page(1...1))
        let s = make()
        await started(s)
        backend.emit(.message(msg(2, kind: "tool_use", tool: ChatToolCall(id: "toolu_1", name: "Bash", summary: "ls"))))
        backend.emit(.message(msg(3, role: "user", kind: "tool_result",
                                  result: ChatToolResult(toolUseId: "toolu_1", ok: false, lines: 4))))
        await eventually("resultado") { s.toolResults["toolu_1"] != nil }
        XCTAssertEqual(ids(s), ["u1:0", "u2:0"])
        XCTAssertEqual(s.toolResults["toolu_1"], ChatToolResult(toolUseId: "toolu_1", ok: false, lines: 4))
    }

    func testNoMaximo500VisiveisEPassaAPoderPaginar() async {
        backend.enqueue(page(1...1))
        let s = make()
        await started(s)
        for i in 2...520 { backend.emit(.message(msg(i))) }
        await eventually("520") { s.messages.last?.id == "u520:0" }
        XCTAssertEqual(s.messages.count, 500)
        XCTAssertEqual(s.messages.first?.id, "u21:0")
        XCTAssertTrue(s.hasMore)
    }

    func testStateAtualizaEstadoEPendente() async {
        backend.enqueue(page(1...1))
        let s = make()
        await started(s)
        let p = PendingPrompt(inboxId: "41", kind: "approval", summary: "Bash: go test")
        backend.emit(.state(state: "needs_input", pending: p))
        await eventually("pendente") { s.pending == p }
        XCTAssertEqual(s.agentState, "needs_input")
        backend.emit(.state(state: "working", pending: nil))
        await eventually("sem pendente") { s.pending == nil }
    }

    func testResetLimpaListaECacheERefazOGet() async {
        cache.save(cacheFile(1...2))
        backend.enqueue(page(1...2))
        let s = make()
        await started(s)
        backend.enqueue(page(100...101, conversation: "1111111111111111"))
        backend.emit(.reset(conversationId: "1111111111111111", reason: "session_changed", cursor: "1111111111111111.0"))
        await eventually("lista nova") { ids(s) == ["u100:0", "u101:0"] }
        XCTAssertEqual(backend.calls.count, 2)
        XCTAssertNil(backend.calls[1].before, "o GET do reset nao leva before")
        XCTAssertEqual(s.currentConversationId, "1111111111111111")
        XCTAssertNil(cache.load(server: server, session: "s1", window: "w1", now: t0), "cache da janela some no reset")
    }

    func testResetDeduplicaMensagemQueChegouPeloStream() async {
        backend.enqueue(page(1...1))
        let s = make()
        await started(s)
        backend.enqueue(page(5...6))
        backend.emit(.reset(conversationId: conv, reason: "clear", cursor: "\(conv).50"))
        backend.emit(.message(msg(6)))
        backend.emit(.message(msg(7)))
        await eventually("u7") { ids(s).contains("u7:0") }
        XCTAssertEqual(ids(s), ["u5:0", "u6:0", "u7:0"])
    }

    func testUnsupportedDoStreamEncerra() async {
        backend.enqueue(page(1...2))
        let s = make()
        await started(s)
        backend.emit(.unsupported(reason: "transcript_not_found"))
        await eventually("unsupported") { s.phase == .unsupported(.transcriptNotFound) }
        XCTAssertTrue(s.messages.isEmpty)
    }

    func testReconectaComOUltimoCursor() async {
        backend.enqueue(page(1...2))
        let s = make()
        await started(s)
        backend.emit(.message(msg(3)))
        await eventually("u3") { ids(s).contains("u3:0") }
        backend.failStream(APIError.network(.networkUnreachable))
        await eventually("offline") { if case .offline = s.phase { true } else { false } }
        // 1 s de espera da primeira tentativa + folga.
        await eventually("nova conexao") { backend.afters.count >= 2 }
        XCTAssertEqual(backend.afters.last ?? nil, "\(conv).30")
        backend.emit(.ready(conversationId: conv, cursor: "\(conv).30", state: "idle", pending: nil))
        await eventually("live de novo") { s.phase == .live }
    }

    // MARK: paginacao

    func testLoadOlderPrependeSemDuplicar() async {
        backend.enqueue(page(5...8, hasMore: true))
        let s = make()
        await started(s)
        backend.enqueue(page(2...5, hasMore: false))
        await s.loadOlder()
        XCTAssertEqual(backend.calls.last?.before, "\(conv).50")
        XCTAssertEqual(ids(s), (2...8).map { "u\($0):0" })
        XCTAssertFalse(s.hasMore)
    }

    func testCursorStaleNoLoadOlderFazReset() async {
        backend.enqueue(page(5...8, hasMore: true))
        let s = make()
        await started(s)
        backend.enqueue(error: APIError.api(status: 409, code: "cursor_stale", message: "", retryAfter: nil))
        backend.enqueue(page(1...2, conversation: "2222222222222222"))
        await s.loadOlder()
        XCTAssertEqual(ids(s), ["u1:0", "u2:0"])
        XCTAssertNil(backend.calls.last?.before)
        XCTAssertEqual(s.currentConversationId, "2222222222222222")
    }

    // MARK: envio

    func testEnviarMostraBolhaEnviandoEEscondeQuandoChegaAMensagem() async {
        backend.enqueue(page(1...1))
        let s = make()
        await started(s)
        s.draft = "rode os testes"
        await s.send()
        XCTAssertEqual(backend.sent, ["rode os testes"])
        XCTAssertEqual(s.outgoing?.text, "rode os testes")
        XCTAssertEqual(s.draft, "")
        backend.emit(.message(msg(2, role: "user", text: "rode os testes\n")))
        await eventually("bolha some") { s.outgoing == nil }
        XCTAssertTrue(ids(s).contains("u2:0"))
    }

    func testBolhaEnviandoExpiraNoPrazo() async {
        backend.enqueue(page(1...1))
        let s = make(timeout: .milliseconds(50))
        await started(s)
        s.draft = "oi"
        await s.send()
        XCTAssertNotNil(s.outgoing)
        await eventually("expirou") { s.outgoing == nil }
    }

    func testFalhaNoEnvioRestauraORascunhoEGuardaOErro() async {
        backend.enqueue(page(1...1))
        let s = make()
        await started(s)
        backend.sendError = APIError.api(status: 429, code: "pending_prompt", message: "", retryAfter: nil)
        s.draft = "oi"
        await s.send()
        XCTAssertNil(s.outgoing)
        XCTAssertEqual(s.draft, "oi")
        XCTAssertEqual(s.lastError?.kind, .pendingPrompt)
        XCTAssertFalse(s.sending)
    }

    func testTextoInvalidoNaoEnvia() async {
        backend.enqueue(page(1...1))
        let s = make()
        await started(s)
        s.draft = "   \n"
        await s.send()
        XCTAssertTrue(backend.sent.isEmpty)
        XCTAssertNil(s.outgoing)
        XCTAssertNotNil(s.lastError)
    }

    func testComPendenteNaoEnvia() async {
        backend.enqueue(page(1...1, pending: PendingPrompt(inboxId: "41", kind: "approval", summary: "x")))
        let s = make()
        await started(s)
        s.draft = "oi"
        await s.send()
        XCTAssertTrue(backend.sent.isEmpty)
        XCTAssertEqual(s.draft, "oi")
    }

    func testInterromperChamaOBackend() async {
        backend.enqueue(page(1...1, state: "working"))
        let s = make()
        await started(s)
        await s.interrupt()
        XCTAssertEqual(backend.interrupts, 1)
    }

    // MARK: cache ao parar

    func testStopSalvaOCacheDepoisDeSincronizar() async {
        backend.enqueue(page(1...3))
        let s = make()
        await started(s)
        s.stop()
        let saved = cache.load(server: server, session: "s1", window: "w1", now: t0)
        XCTAssertEqual(saved?.messages.map(\.id), ["u1:0", "u2:0", "u3:0"])
        XCTAssertEqual(saved?.conversationId, conv)
    }

    func testStopSemSincronizarNaoRenovaOCache() async {
        cache.save(cacheFile(1...3))
        backend.enqueue(error: APIError.network(.networkUnreachable))
        let s = make()
        await s.start()
        s.stop()
        let saved = cache.load(server: server, session: "s1", window: "w1", now: t0)
        XCTAssertEqual(saved?.savedAt, t0.addingTimeInterval(-3600), "continua com a data antiga")
    }
}
