import XCTest
@testable import PoppyKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ChatTests: XCTestCase {
    private func snake() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func endpoints() throws -> Endpoints {
        try XCTUnwrap(Endpoints(serverURL: "https://exemplo.ts.net"))
    }

    private func client(_ transport: MockTransport) throws -> APIClient {
        APIClient(endpoints: try endpoints(), transport: transport)
    }

    // MARK: fixtures de API

    func testDecodificaChatBasico() throws {
        let p = try Fixture.decode(ChatPage.self, "chat_basico.json")
        XCTAssertTrue(p.supported)
        XCTAssertNil(p.unsupportedReason)
        XCTAssertEqual(p.conversationId, "ab1f47251fd3fea5")
        XCTAssertEqual(p.agentVersion, "2.1.295")
        XCTAssertEqual(p.messages.count, 24)
        XCTAssertFalse(p.hasMore)
        XCTAssertEqual(p.oldestCursor, "ab1f47251fd3fea5.2010")
        let kinds = Set(p.messages.map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.text, .toolUse, .toolResult, .image, .interrupted]))
        XCTAssertFalse(kinds.contains(.unknown))
        XCTAssertFalse(p.messages.contains { $0.role == .unknown })
        let use = try XCTUnwrap(p.messages.first { $0.kind == .toolUse })
        XCTAssertNotNil(use.tool)
        XCTAssertEqual(use.text, "")
        let res = try XCTUnwrap(p.messages.first { $0.kind == .toolResult })
        XCTAssertNotNil(res.result)
        XCTAssertGreaterThan(p.messages[0].ts, 0)
        XCTAssertEqual(p.messages[0].date.timeIntervalSince1970, Double(p.messages[0].ts) / 1000)
    }

    func testDecodificaChatGrandeEPendente() throws {
        let p1 = try Fixture.decode(ChatPage.self, "chat_grande_p1.json")
        let p2 = try Fixture.decode(ChatPage.self, "chat_grande_p2.json")
        XCTAssertEqual(p1.messages.count, 50)
        XCTAssertEqual(p2.messages.count, 50)
        XCTAssertTrue(p1.hasMore)
        XCTAssertEqual(p1.conversationId, p2.conversationId)
        XCTAssertTrue(Set(p1.messages.map(\.id)).isDisjoint(with: Set(p2.messages.map(\.id))))

        let pend = try Fixture.decode(ChatPage.self, "chat_pendente.json")
        XCTAssertEqual(pend.state, "needs_input")
        XCTAssertEqual(pend.pending, PendingPrompt(inboxId: "41", kind: "approval", summary: pend.pending?.summary ?? ""))
        XCTAssertFalse(pend.pending?.summary.isEmpty ?? true)
    }

    func testDecodificaChatNaoSuportado() throws {
        let a = try Fixture.decode(ChatPage.self, "chat_unsupported_not_claude.json")
        XCTAssertFalse(a.supported)
        XCTAssertEqual(a.unsupportedReason, .notClaude)
        XCTAssertTrue(a.messages.isEmpty)
        XCTAssertNil(a.pending)
        let b = try Fixture.decode(ChatPage.self, "chat_unsupported_transcript_not_found.json")
        XCTAssertEqual(b.unsupportedReason, .transcriptNotFound)
        for r in [ChatUnsupportedReason.noAgent, .notClaude, .noSessionId, .transcriptNotFound,
                  .sessionMismatch, .unknownFormat, .unreadable, .remoteWindow, .other] {
            XCTAssertFalse(r.userMessage.isEmpty)
        }
        XCTAssertEqual(ChatUnsupportedReason(reason: "algo_novo"), .other)
    }

    func testDecodificaEnvioEInterrupcao() throws {
        let s = try Fixture.decode(ChatSendResult.self, "chat_send_ok.json")
        XCTAssertTrue(s.sent)
        XCTAssertEqual(s.at, 1791550800000)
        let i = try Fixture.decode(ChatSendResult.self, "chat_interrupt_ok.json")
        XCTAssertTrue(i.sent)
    }

    func testInfoV030EWindowV030() throws {
        let info = try Fixture.decode(ServerInfo.self, "info_v030.json")
        XCTAssertEqual(info.features, ["chat", "phone_view"])
        XCTAssertTrue(info.supportsChat)
        XCTAssertTrue(info.supportsPhoneView)
        // servidor v0.2: sem `features`
        let legacy = Data(#"{"api":1,"boot_id":"x","daemon_ok":true,"default_session":"poppy","human_actions":true,"missing_verbs":[],"server_version":"0.8.5-poppy"}"#.utf8)
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let old = try dec.decode(ServerInfo.self, from: legacy)
        XCTAssertTrue(old.features.isEmpty)
        XCTAssertFalse(old.supportsChat)
        XCTAssertFalse(old.supportsPhoneView)

        let s = try Fixture.decode(SessionDetail.self, "session_v030.json")
        let w1 = try XCTUnwrap(s.window(id: "w1"))
        XCTAssertEqual(w1.cols, 80)
        XCTAssertEqual(w1.rows, 43)
        XCTAssertTrue(w1.chat)
        let w2 = try XCTUnwrap(s.window(id: "w2"))
        XCTAssertEqual(w2.cols, 120)
        XCTAssertFalse(w2.chat)
        // fixture da v0.2: cols/rows/chat ausentes
        let v2 = try Fixture.decode(SessionDetail.self, "session_poppy.json")
        for w in v2.allWindows where w.cols == 0 { XCTAssertEqual(w.rows, 0); XCTAssertFalse(w.chat) }
    }

    func testErrosNovos() throws {
        let cases: [(String, APIError.Kind)] = [
            ("erro_pending_prompt.json", .pendingPrompt),
            ("erro_cursor_stale.json", .cursorStale),
            ("erro_too_many_streams.json", .tooManyStreams),
        ]
        for (file, kind) in cases {
            let e = APIError.parse(status: 409, body: try Fixture.data(file), retryAfter: nil)
            XCTAssertEqual(e.kind, kind, file)
            XCTAssertFalse(e.userMessage.isEmpty)
        }
        for code in ["remote_window", "not_chat"] {
            let e = APIError.api(status: 409, code: code, message: "", retryAfter: nil)
            XCTAssertTrue(e.kind == .remoteWindow || e.kind == .notChat)
            XCTAssertNotEqual(e.userMessage, "Algo deu errado.")
        }
        let tex = APIError.parse(status: 400, body: try Fixture.data("erro_chat_texto_invalido.json"), retryAfter: nil)
        XCTAssertEqual(tex.kind, .invalidParams)
        let tail = APIError.parse(status: 403, body: try Fixture.data("erro_chat_sem_tailscale.json"), retryAfter: nil)
        XCTAssertEqual(tail.kind, .humanRequiresTailscale)
    }

    // MARK: stream

    func testSequenciaDoStreamSSE() throws {
        var parser = SSEParser()
        var events = parser.feed(try Fixture.data("chat_stream_sse.txt"))
        events += parser.finish()
        let chat = events.map { ChatEvent($0) }
        let names: [String] = chat.map {
            switch $0 {
            case .ready: return "ready"
            case .message: return "message"
            case .reset: return "reset"
            case .state: return "state"
            case .ping: return "ping"
            case .unsupported: return "unsupported"
            case .unknown: return "unknown"
            }
        }
        XCTAssertEqual(names, ["ready", "state", "state", "ping", "reset", "message", "message", "unsupported"])

        guard case let .ready(conv, cursor, state, pending) = chat[0] else { return XCTFail("ready") }
        XCTAssertEqual(conv, "64105dfca6013bc2")
        XCTAssertEqual(cursor, "64105dfca6013bc2.1900")
        XCTAssertEqual(state, "working")
        XCTAssertNil(pending)
        guard case let .state(st, pend) = chat[1] else { return XCTFail("state") }
        XCTAssertEqual(st, "needs_input")
        XCTAssertEqual(pend?.inboxId, "41")
        guard case let .state(_, none) = chat[2] else { return XCTFail("state 2") }
        XCTAssertNil(none)
        guard case let .reset(c2, reason, rc) = chat[4] else { return XCTFail("reset") }
        XCTAssertEqual(c2, "f4153cb68812ca20")
        XCTAssertEqual(reason, "session_changed")
        XCTAssertEqual(rc, "f4153cb68812ca20.0")
        guard case let .message(m) = chat[5] else { return XCTFail("message") }
        XCTAssertEqual(m.role, .user)
        XCTAssertEqual(m.cursor, "f4153cb68812ca20.1592")
        XCTAssertEqual(chat[7], .unsupported(reason: "transcript_not_found"))
    }

    func testEventoIlegivelViraUnknown() {
        XCTAssertEqual(ChatEvent(SSEEvent(event: "message", data: "{quebrado")), .unknown(name: "message"))
        XCTAssertEqual(ChatEvent(SSEEvent(event: "ready", data: "nao e json")), .unknown(name: "ready"))
        XCTAssertEqual(ChatEvent(SSEEvent(event: "novidade", data: "{}")), .unknown(name: "novidade"))
        XCTAssertEqual(ChatEvent(SSEEvent(event: "ping", data: "")), .ping)
    }

    func testChatEventsViaCliente() async throws {
        let body = try Fixture.data("chat_stream_sse.txt")
        let mock = MockTransport { _ in .init(status: 200, body: body) }
        let c = try client(mock)
        var got: [ChatEvent] = []
        for try await ev in c.chatEvents(session: "poppy", window: "w1", after: "ab1f47251fd3fea5.2010") { got.append(ev) }
        XCTAssertEqual(got.count, 8)
        let req = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.absoluteString,
                       "https://exemplo.ts.net/api/v1/sessions/poppy/windows/w1/chat/stream?after=ab1f47251fd3fea5.2010")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "text/event-stream")
    }

    func testChatEventsComErroHTTP() async throws {
        let body = try Fixture.data("erro_too_many_streams.json")
        let mock = MockTransport { _ in .init(status: 429, body: body, headers: ["Retry-After": "5"]) }
        let c = try client(mock)
        do {
            for try await _ in c.chatEvents(session: "poppy", window: "w1", after: nil) {}
            XCTFail("devia lancar")
        } catch {
            let e = try XCTUnwrap(error as? APIError)
            XCTAssertEqual(e.kind, .tooManyStreams)
            XCTAssertEqual(e.retryAfter, 5)
        }
    }

    func testChatEventsComCursorInvalidoNaoConecta() async throws {
        let mock = MockTransport { _ in .init(status: 200, body: Data()) }
        let c = try client(mock)
        do {
            for try await _ in c.chatEvents(session: "poppy", window: "w1", after: "../etc") {}
            XCTFail("devia lancar")
        } catch {
            XCTAssertNotNil(error as? APIError)
        }
        XCTAssertTrue(mock.requests.isEmpty)
    }

    // MARK: URLs

    func testCursorValido() {
        XCTAssertTrue(Endpoints.isValidCursor("ab1f47251fd3fea5.2010"))
        XCTAssertTrue(Endpoints.isValidCursor("ab1f47251fd3fea5.0"))
        XCTAssertTrue(Endpoints.isValidCursor("ab1f47251fd3fea5.123456789012345"))
        XCTAssertFalse(Endpoints.isValidCursor("ab1f47251fd3fea5.1234567890123456")) // 16 digitos
        XCTAssertFalse(Endpoints.isValidCursor("ab1f47251fd3fea5."))
        XCTAssertFalse(Endpoints.isValidCursor("ab1f47251fd3fea.5"))                 // 15 hex
        XCTAssertFalse(Endpoints.isValidCursor("AB1F47251FD3FEA5.5"))                // maiuscula
        XCTAssertFalse(Endpoints.isValidCursor("zb1f47251fd3fea5.5"))
        XCTAssertFalse(Endpoints.isValidCursor("ab1f47251fd3fea5.5.5"))
        XCTAssertFalse(Endpoints.isValidCursor("ab1f47251fd3fea5.5\n"))
        XCTAssertFalse(Endpoints.isValidCursor("ab1f47251fd3fea5.-1"))
        XCTAssertFalse(Endpoints.isValidCursor(""))
    }

    func testURLsDoChat() throws {
        let e = try endpoints()
        let base = "https://exemplo.ts.net/api/v1/sessions/poppy/windows/w1/chat"
        XCTAssertEqual(e.chat(session: "poppy", window: "w1")?.absoluteString, base)
        XCTAssertEqual(e.chat(session: "poppy", window: "w1", before: "ab1f47251fd3fea5.2010", limit: 50)?.absoluteString,
                       base + "?before=ab1f47251fd3fea5.2010&limit=50")
        XCTAssertEqual(e.chat(session: "poppy", window: "w1", before: nil, limit: 200)?.absoluteString, base + "?limit=200")
        XCTAssertNil(e.chat(session: "poppy", window: "w1", before: nil, limit: 0))
        XCTAssertNil(e.chat(session: "poppy", window: "w1", before: nil, limit: 201))
        XCTAssertNil(e.chatStream(session: "poppy", window: "w1", after: "x"))
        XCTAssertEqual(e.chatStream(session: "poppy", window: "w1", after: nil)?.absoluteString, base + "/stream")
        XCTAssertEqual(e.chatSend(session: "poppy", window: "w1")?.absoluteString, base + "/send")
        XCTAssertEqual(e.chatInterrupt(session: "poppy", window: "w1")?.absoluteString, base + "/interrupt")
        XCTAssertNil(e.chatSend(session: "po ppy", window: "w1"))
        XCTAssertNil(e.chatInterrupt(session: "poppy", window: "w 1"))
        XCTAssertNil(e.chat(session: "poppy", window: "w1/../x"))
    }

    func testCursorInvalidoNaoMontaURL() throws {
        let e = try endpoints()
        for bad in ["", "abc", "ab1f47251fd3fea5", "ab1f47251fd3fea5.2010&x=1", "../../etc.1", "ab1f47251fd3fea5.2010 "] {
            XCTAssertNil(e.chat(session: "poppy", window: "w1", before: bad, limit: nil), bad)
            XCTAssertNil(e.chatStream(session: "poppy", window: "w1", after: bad), bad)
        }
    }

    func testWsURLPhoneView() throws {
        let e = try endpoints()
        let url = try XCTUnwrap(e.wsURL(session: "poppy", window: "w2", phoneView: true))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "view" }?.value, "phone")
        XCTAssertEqual(items.first { $0.name == "mode" }?.value, "satellite")
        XCTAssertEqual(items.first { $0.name == "window" }?.value, "w2")
        XCTAssertEqual(url.absoluteString, "wss://exemplo.ts.net/ws?session=poppy&mode=satellite&window=w2&view=phone")
        // sem phoneView: igual ao de sempre
        XCTAssertEqual(e.wsURL(session: "poppy", window: "w2", phoneView: false), e.wsURL(session: "poppy", window: "w2"))
        XCTAssertFalse(e.wsURL(session: "poppy", window: "w2")?.absoluteString.contains("view=") ?? true)
        XCTAssertNil(e.wsURL(session: "po ppy", window: nil, phoneView: true))
    }

    // MARK: cliente

    func testChatGetViaCliente() async throws {
        let body = try Fixture.data("chat_basico.json")
        let mock = MockTransport { _ in .init(status: 200, body: body) }
        let page = try await client(mock).chat(session: "poppy", window: "w1", before: "ab1f47251fd3fea5.2010", limit: 20)
        XCTAssertEqual(page.messages.count, 24)
        let req = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertNil(req.value(forHTTPHeaderField: "X-Poppy-Client"))
        XCTAssertTrue(req.url?.absoluteString.hasSuffix("/chat?before=ab1f47251fd3fea5.2010&limit=20") ?? false)
    }

    func testChatGetComParametroInvalidoNaoVaiParaARede() async throws {
        let mock = MockTransport { _ in .init(status: 200, body: Data()) }
        let c = try client(mock)
        for (before, limit) in [("lixo", 50), (nil, 0), (nil, 500)] as [(String?, Int)] {
            do {
                _ = try await c.chat(session: "poppy", window: "w1", before: before, limit: limit)
                XCTFail("devia lancar")
            } catch {
                XCTAssertNotNil(error as? APIError)
            }
        }
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testEnviarEInterromper() async throws {
        let ok = try Fixture.data("chat_send_ok.json")
        let mock = MockTransport { _ in .init(status: 200, body: ok) }
        let c = try client(mock)
        let r = try await c.sendChat(session: "poppy", window: "w1", text: "oi\ntudo bem?")
        XCTAssertTrue(r.sent)
        let send = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(send.httpMethod, "POST")
        XCTAssertEqual(send.value(forHTTPHeaderField: "X-Poppy-Client"), "PoppyTerminal-iOS")
        XCTAssertTrue(send.url?.absoluteString.hasSuffix("/windows/w1/chat/send") ?? false)
        let sent = try JSONSerialization.jsonObject(with: try XCTUnwrap(send.httpBody)) as? [String: Any]
        XCTAssertEqual(sent?["text"] as? String, "oi\ntudo bem?")

        _ = try await c.interruptChat(session: "poppy", window: "w1")
        let intr = try XCTUnwrap(mock.requests.last)
        XCTAssertEqual(intr.httpMethod, "POST")
        XCTAssertEqual(intr.value(forHTTPHeaderField: "X-Poppy-Client"), "PoppyTerminal-iOS")
        XCTAssertTrue(intr.url?.absoluteString.hasSuffix("/windows/w1/chat/interrupt") ?? false)
        XCTAssertEqual(String(data: try XCTUnwrap(intr.httpBody), encoding: .utf8), "{}")
    }

    func testEnviarTextoInvalidoNaoVaiParaARede() async throws {
        let mock = MockTransport { _ in .init(status: 200, body: Data()) }
        let c = try client(mock)
        do {
            _ = try await c.sendChat(session: "poppy", window: "w1", text: "oi\u{1B}[31m")
            XCTFail("devia lancar")
        } catch {
            guard case APIError.invalidArgument = error else { return XCTFail("\(error)") }
        }
        XCTAssertTrue(mock.requests.isEmpty)
    }

    func testEnviarComPendenteDevolve409() async throws {
        let body = try Fixture.data("erro_pending_prompt.json")
        let mock = MockTransport { _ in .init(status: 409, body: body) }
        do {
            _ = try await client(mock).sendChat(session: "poppy", window: "w1", text: "oi")
            XCTFail("devia lancar")
        } catch {
            XCTAssertEqual((error as? APIError)?.kind, .pendingPrompt)
        }
    }

    // MARK: validacao do texto

    func testValidacaoDoTexto() {
        XCTAssertNil(ChatText.validate("oi"))
        XCTAssertNil(ChatText.validate("linha 1\nlinha 2\n\tindentada"))
        XCTAssertNil(ChatText.validate("linha 1\r\nlinha 2\rlinha 3"))      // CRLF e CR viram LF
        XCTAssertNil(ChatText.validate("acentuação, emoji 🙂 e ñ"))
        XCTAssertNotNil(ChatText.validate(""))
        XCTAssertNotNil(ChatText.validate("   \n\t  "))
        XCTAssertNotNil(ChatText.validate("\r\n\r\n"))
        // limite em runas, nao em bytes nem em graphemes
        XCTAssertNil(ChatText.validate(String(repeating: "a", count: 4000)))
        XCTAssertNotNil(ChatText.validate(String(repeating: "a", count: 4001)))
        XCTAssertNil(ChatText.validate(String(repeating: "é", count: 4000)))
        XCTAssertNil(ChatText.validate(String(repeating: "🙂", count: 4000)))
        XCTAssertNotNil(ChatText.validate(String(repeating: "🙂", count: 4001)))
        // CRLF conta como 1 runa (apos normalizar)
        XCTAssertNil(ChatText.validate("a" + String(repeating: "\r\n", count: 3999)))
        // controles
        XCTAssertNotNil(ChatText.validate("a\u{1B}b"))      // ESC
        XCTAssertNotNil(ChatText.validate("a\u{00}b"))      // NUL
        XCTAssertNotNil(ChatText.validate("a\u{07}b"))      // BEL
        XCTAssertNotNil(ChatText.validate("a\u{08}b"))      // BS
        XCTAssertNotNil(ChatText.validate("a\u{0B}b"))      // VT
        XCTAssertNotNil(ChatText.validate("a\u{0C}b"))      // FF
        XCTAssertNotNil(ChatText.validate("a\u{7F}b"))      // DEL
        XCTAssertNotNil(ChatText.validate("a\u{80}b"))      // C1
        XCTAssertNotNil(ChatText.validate("a\u{9B}b"))      // CSI (C1)
        XCTAssertNotNil(ChatText.validate("a\u{9F}b"))
        XCTAssertNil(ChatText.validate("a\u{A0}b"))         // NBSP nao e controle
        XCTAssertEqual(ChatText.maxRunes, 4000)
    }

    // MARK: tolerancia e codificacao

    func testMensagemTolerante() throws {
        let json = #"{"id":"x:0","role":"alien","kind":"hologram","ts":"lixo","tool":5}"#
        let m = try snake().decode(ChatMessage.self, from: Data(json.utf8))
        XCTAssertEqual(m.id, "x:0")
        XCTAssertEqual(m.role, .unknown)
        XCTAssertEqual(m.kind, .unknown)
        XCTAssertEqual(m.ts, 0)
        XCTAssertEqual(m.text, "")
        XCTAssertFalse(m.truncated)
        XCTAssertNil(m.tool)
        XCTAssertNil(m.result)
        let vazio = try snake().decode(ChatMessage.self, from: Data("{}".utf8))
        XCTAssertEqual(vazio.id, "")
    }

    func testPaginaTolerante() throws {
        let p = try snake().decode(ChatPage.self, from: Data("{}".utf8))
        XCTAssertFalse(p.supported)
        XCTAssertEqual(p.unsupportedReason, .other)
        XCTAssertTrue(p.messages.isEmpty)
        XCTAssertEqual(p.state, "idle")
    }

    func testIdaEVoltaDoCache() throws {
        // O cache do app usa JSONEncoder/Decoder padrao: a mensagem precisa sobreviver.
        let m = ChatMessage(id: "a:0", cursor: "ab1f47251fd3fea5.10", ts: 1791550802000, role: "assistant",
                            kind: "tool_use", text: "", truncated: true,
                            tool: ChatToolCall(id: "toolu_1", name: "Bash", summary: "go test ./..."),
                            result: ChatToolResult(toolUseId: "toolu_1", ok: false, lines: 4))
        let data = try JSONEncoder().encode([m])
        XCTAssertEqual(try JSONDecoder().decode([ChatMessage].self, from: data), [m])
        // e continua legivel pelo decoder do cliente (snake_case)
        XCTAssertEqual(try snake().decode([ChatMessage].self, from: data), [m])
    }

    // MARK: contrato Go x Swift

    func testContratoComAsProjecoesEsperadas() throws {
        struct Esperado: Decodable {
            var fixture: String
            var conversationId: String
            var supported: Bool
            var reason: String
            var agentVersion: String
            var messages: [ChatMessage]
        }
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "esperado", withExtension: nil,
                                                  subdirectory: "Fixtures/chat"))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThanOrEqual(files.count, 9)
        var total = 0
        for f in files {
            let e = try snake().decode(Esperado.self, from: try Data(contentsOf: f))
            XCTAssertEqual(e.fixture + ".json", f.lastPathComponent)
            XCTAssertEqual(e.supported, e.reason.isEmpty, f.lastPathComponent)
            for m in e.messages {
                XCTAssertFalse(m.id.isEmpty, f.lastPathComponent)
                XCTAssertTrue(Endpoints.isValidCursor(m.cursor), "\(f.lastPathComponent) \(m.cursor)")
                XCTAssertNotEqual(m.role, .unknown, f.lastPathComponent)
                XCTAssertNotEqual(m.kind, .unknown, f.lastPathComponent)
                switch m.kind {
                case .toolUse: XCTAssertNotNil(m.tool, m.id)
                case .toolResult: XCTAssertNotNil(m.result, m.id)
                default: break
                }
            }
            total += e.messages.count
        }
        XCTAssertGreaterThan(total, 50)
    }
}
