import XCTest
@testable import PoppyKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - apoio

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/api") else {
            throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "sem fixture \(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: try data(name))
    }

    /// Para closures do MockTransport (que nao lancam).
    static func bytes(_ name: String) -> Data { (try? data(name)) ?? Data() }
}

final class MockTransport: APITransport, @unchecked Sendable {
    struct Reply { var status: Int; var body: Data; var headers: [String: String] = [:] }
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let handler: @Sendable (URLRequest) -> Reply

    init(_ handler: @escaping @Sendable (URLRequest) -> Reply) { self.handler = handler }

    var requests: [URLRequest] { lock.withLock { _requests } }
    private func record(_ r: URLRequest) { lock.withLock { _requests.append(r) } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        let r = handler(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers)!
        return (r.body, resp)
    }

    func stream(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        record(request)
        let r = handler(request)
        let resp = HTTPURLResponse(url: request.url!, statusCode: r.status, httpVersion: "HTTP/1.1", headerFields: r.headers)!
        let body = r.body
        let s = AsyncThrowingStream<Data, Error> { c in
            // fatias de 7 bytes para exercitar o parser
            var i = body.startIndex
            while i < body.endIndex {
                let j = body.index(i, offsetBy: 7, limitedBy: body.endIndex) ?? body.endIndex
                c.yield(Data(body[i..<j]))
                i = j
            }
            c.finish()
        }
        return (resp, s)
    }
}

private func makeClient(_ t: MockTransport, auth: String? = nil) -> APIClient {
    APIClient(endpoints: Endpoints(serverURL: "https://exemplo.ts.net")!, authHeader: auth, transport: t)
}

// MARK: - fixtures decodificam

final class FixtureDecodeTests: XCTestCase {
    func testInfo() throws {
        let i = try Fixture.decode(ServerInfo.self, "info.json")
        XCTAssertEqual(i.api, 1)
        XCTAssertEqual(i.bootId, "9f2c41d07a3e8b65")
        XCTAssertEqual(i.defaultSession, "poppy")
        XCTAssertTrue(i.humanActions)
        XCTAssertFalse(i.daemonTooOld)
        XCTAssertEqual(ConnectionState.from(i), .online)
    }

    func testInfoVariantes() throws {
        let old = try Fixture.decode(ServerInfo.self, "info_daemon_antigo.json")
        XCTAssertTrue(old.daemonTooOld)
        XCTAssertEqual(old.missingVerbs.count, 11)
        XCTAssertEqual(ConnectionState.from(old), .daemonOld(missing: old.missingVerbs))
        let fora = try Fixture.decode(ServerInfo.self, "info_daemon_fora.json")
        XCTAssertFalse(fora.daemonOk)
        XCTAssertNotNil(fora.daemonError)
        XCTAssertEqual(ConnectionState.from(fora), .daemonDown)
        let sem = try Fixture.decode(ServerInfo.self, "info_sem_tailscale.json")
        XCTAssertFalse(sem.humanActions)
    }

    func testSessions() throws {
        let r = try Fixture.decode(SessionsResponse.self, "sessions.json")
        XCTAssertEqual(r.sessions.map(\.name), ["celular", "poppy"])
        let poppy = r.sessions[1]
        XCTAssertTrue(poppy.current)
        XCTAssertEqual(poppy.windows, 3)
        XCTAssertEqual(poppy.agents.needsInput, 1)
        XCTAssertEqual(poppy.needsYou, 2)
        XCTAssertTrue(r.warnings.isEmpty)
        let old = try Fixture.decode(SessionsResponse.self, "sessions_daemon_antigo.json")
        XCTAssertEqual(old.warnings, ["list-agents"])
    }

    func testSessionDetail() throws {
        let d = try Fixture.decode(SessionDetail.self, "session_poppy.json")
        XCTAssertEqual(d.name, "poppy")
        XCTAssertEqual(d.workspaces.count, 2)
        XCTAssertEqual(d.allWindows.map(\.id), ["w1", "w2", "w3"])
        XCTAssertEqual(d.pcFocusedWindow?.id, "w1")
        let w2 = try XCTUnwrap(d.window(id: "w2"))
        XCTAssertEqual(w2.host, "notebook")
        XCTAssertEqual(w2.agent?.stateKind, .needsInput)
        XCTAssertEqual(w2.agent?.needsYou, true)
        XCTAssertEqual(d.workspaces[0].displayName, "Workspace 1")
        XCTAssertEqual(d.workspaces[1].displayName, "monitor")
        XCTAssertEqual(d.window(id: "w1")?.runningCmdline, "claude")
        XCTAssertEqual(d.window(id: "w3")?.agent?.harness, "codex")
    }

    func testCriados() throws {
        XCTAssertEqual(try Fixture.decode(CreatedSession.self, "session_criada.json").name, "nova")
        let w = try Fixture.decode(CreatedWindow.self, "window_criada.json")
        XCTAssertEqual(w.id, "w10")
        XCTAssertEqual(w.workspace, 2)
    }

    func testInbox() throws {
        let r = try Fixture.decode(InboxResponse.self, "inbox.json")
        XCTAssertEqual(r.items.count, 3)
        XCTAssertEqual(r.seq, 43)
        XCTAssertEqual(r.bootId, "9f2c41d07a3e8b65")
        XCTAssertEqual(r.counts["approval"], 1)
        XCTAssertEqual(r.counts["finished"], 1)
        let a = r.items[0]
        XCTAssertEqual(a.id, "17")
        XCTAssertEqual(a.kind, .approval)
        XCTAssertTrue(a.kind.needsYou)
        XCTAssertEqual(a.options, ["once", "always", "deny"])
        XCTAssertEqual(a.requestId, "9f86d081884c7d65")
        XCTAssertEqual(a.risk, ["rm-recursive"])
        XCTAssertTrue(a.hasRisk)
        XCTAssertEqual(a.alwaysScope, ["Bash(rm:*)"])
        XCTAssertEqual(a.expires, 1_790_000_000_000_000_000)
        XCTAssertEqual(a.window, "w2")
        XCTAssertEqual(a.workspace, 1)
        XCTAssertEqual(a.seq, 41)
        let q = r.items[1]
        XCTAssertEqual(q.kind, .ask)
        XCTAssertEqual(q.options, ["sim", "nao", "depois"])
        let f = r.items[2]
        XCTAssertEqual(f.kind, .finished)
        XCTAssertFalse(f.kind.needsYou)
        XCTAssertEqual(f.options, [])
        XCTAssertEqual(f.count, 1)
    }

    func testPrompts() throws {
        let p = try Fixture.decode(PromptInfo.self, "prompt_approval.json")
        XCTAssertEqual(p.promptId, "p-77")
        XCTAssertTrue(p.answerable)
        XCTAssertEqual(p.actions, ["approve", "approve_always", "deny"])
        XCTAssertEqual(p.options.map(\.n), [1, 2, 3])
        XCTAssertEqual(p.lines.count, 3)
        XCTAssertEqual(p.waitingMs, 4200)
        let a = try Fixture.decode(PromptInfo.self, "prompt_ask.json")
        XCTAssertFalse(a.answerable)
        XCTAssertEqual(a.requestId, "abcd1234")
        XCTAssertEqual(a.options.map(\.label), ["sim", "nao", "depois"])
    }

    func testResultados() throws {
        let r = try Fixture.decode(ReplyResult.self, "reply_ok.json")
        XCTAssertTrue(r.applied)
        XCTAssertEqual(r.decision, "once")
        let a = try Fixture.decode(AnswerResult.self, "answer_ok.json")
        XCTAssertTrue(a.applied)
        XCTAssertEqual(a.answer, "sim")
        let s = try Fixture.decode(RespondResult.self, "respond_ok.json")
        XCTAssertEqual(s.settledBy, "state")
        XCTAssertEqual(s.state, "working")
        XCTAssertEqual(s.promptId, "p-77")
        XCTAssertTrue(try Fixture.decode(DismissResult.self, "dismiss_ok.json").dismissed)
    }

    func testTodasAsFixturesJSONSaoValidas() throws {
        let dir = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures/api")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }
        XCTAssertGreaterThanOrEqual(names.count, 25)
        for n in names {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: try Fixture.data(n)), n)
        }
    }

    func testDecodificacaoTolerante() throws {
        let json = #"{"items":[{"id":5,"kind":"coisa-nova","options":null,"risk":null}],"counts":{"x":2}}"#
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let r = try d.decode(InboxResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.items[0].id, "5")
        XCTAssertEqual(r.items[0].kind, .unknown)
        XCTAssertEqual(r.items[0].options, [])
        XCTAssertEqual(r.items[0].risk, [])
    }
}

// MARK: - erros

final class APIErrorTests: XCTestCase {
    private func parse(_ file: String, status: Int, retry: Double? = nil) throws -> APIError {
        APIError.parse(status: status, body: try Fixture.data(file), retryAfter: retry)
    }

    func testCodigosTipados() throws {
        XCTAssertEqual(try parse("erro_daemon_antigo.json", status: 502).kind, .daemonTooOld)
        XCTAssertEqual(try parse("erro_needs_attach.json", status: 409).kind, .needsAttach)
        XCTAssertEqual(try parse("erro_prompt_changed.json", status: 409).kind, .promptChanged)
        XCTAssertEqual(try parse("erro_human_sem_tailscale.json", status: 403).kind, .humanRequiresTailscale)
        XCTAssertEqual(try parse("erro_item_sumiu.json", status: 404).kind, .itemNotFound)
        let he = try parse("erro_hold_ended.json", status: 409)
        XCTAssertEqual(he.kind, .holdEnded)
        XCTAssertEqual(he.userMessage, "A espera acabou, responda pelo terminal.")
        XCTAssertEqual(try parse("erro_sem_cabecalho.json", status: 400).kind, .clientHeaderRequired)
        XCTAssertEqual(try parse("erro_nome_invalido.json", status: 400).kind, .invalidParams)
        XCTAssertEqual(try parse("erro_sessao_inexistente.json", status: 404).kind, .sessionNotFound)
        let rl = try parse("erro_rate_limited.json", status: 429, retry: 1)
        XCTAssertEqual(rl.kind, .rateLimited)
        XCTAssertEqual(rl.retryAfter, 1)
        XCTAssertEqual(rl.code, "rate_limited")
    }

    func testCodigosSemFixture() {
        let casos: [(String, APIError.Kind)] = [
            ("daemon_unreachable", .daemonUnreachable), ("session_exists", .sessionExists), ("remote_item", .remoteItem),
        ]
        for (code, kind) in casos {
            let body = Data("{\"error\":{\"code\":\"\(code)\",\"message\":\"m\"}}".utf8)
            XCTAssertEqual(APIError.parse(status: 409, body: body, retryAfter: nil).kind, kind)
        }
    }

    func test401e403CruViramAcessoNegado() {
        XCTAssertEqual(APIError.parse(status: 403, body: Data("Forbidden".utf8), retryAfter: nil).kind, .accessDenied)
        XCTAssertEqual(APIError.parse(status: 401, body: Data(), retryAfter: nil).kind, .accessDenied)
        XCTAssertEqual(ConnectionState.from(APIError.parse(status: 401, body: Data(), retryAfter: nil)), .accessDenied)
    }

    func testRede() {
        XCTAssertEqual(APIError.from(URLError(.cannotConnectToHost)).kind, .networkUnreachable)
        XCTAssertEqual(ConnectionState.from(APIError.from(URLError(.timedOut))), .tailscaleOff)
        XCTAssertEqual(APIError.from(URLError(.userAuthenticationRequired)).kind, .accessDenied)
    }
}

// MARK: - cliente

final class APIClientTests: XCTestCase {
    func testGetLevaAuthENaoClientHeader() async throws {
        let t = MockTransport { _ in .init(status: 200, body: Fixture.bytes("sessions.json")) }
        let r = try await makeClient(t, auth: BasicAuth.header(user: "u", password: "p")).sessions()
        XCTAssertEqual(r.sessions.count, 2)
        let req = t.requests[0]
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.url?.absoluteString, "https://exemplo.ts.net/api/v1/sessions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Basic dTpw")
        XCTAssertNil(req.value(forHTTPHeaderField: "X-Poppy-Client"))
    }

    func testPostEDeleteLevamXPoppyClient() async throws {
        let t = MockTransport { req in
            let path = req.url?.path ?? ""
            if req.httpMethod == "DELETE" { return .init(status: 204, body: Data()) }
            if path == "/api/v1/sessions" { return .init(status: 201, body: Fixture.bytes("session_criada.json")) }
            if path.hasSuffix("/windows") { return .init(status: 201, body: Fixture.bytes("window_criada.json")) }
            if path.hasSuffix("/reply") { return .init(status: 200, body: Fixture.bytes("reply_ok.json")) }
            if path.hasSuffix("/answer") { return .init(status: 200, body: Fixture.bytes("answer_ok.json")) }
            if path.hasSuffix("/respond") { return .init(status: 200, body: Fixture.bytes("respond_ok.json")) }
            return .init(status: 200, body: Fixture.bytes("dismiss_ok.json"))
        }
        let c = makeClient(t)
        _ = try await c.createSession(name: "nova")
        _ = try await c.createWindow(session: "poppy", name: "  ", workspace: 2)
        try await c.closeWindow(session: "poppy", id: "w10")
        _ = try await c.reply(itemID: "17", ReplyRequest(decision: .once, riskAck: ["rm-recursive"], summary: "Bash: rm -rf build/"))
        _ = try await c.answer(itemID: "18", answer: "sim", question: "Deploy no staging?")
        _ = try await c.respond(itemID: "17", RespondRequest(action: "approve", promptId: "p-77"))
        try await c.dismiss(itemID: "19")
        XCTAssertEqual(t.requests.count, 7)
        for r in t.requests {
            XCTAssertEqual(r.value(forHTTPHeaderField: "X-Poppy-Client"), "PoppyTerminal-iOS", r.url?.absoluteString ?? "")
        }
        let paths = t.requests.map { ($0.httpMethod ?? "") + " " + ($0.url?.path ?? "") }
        XCTAssertEqual(paths, [
            "POST /api/v1/sessions",
            "POST /api/v1/sessions/poppy/windows",
            "DELETE /api/v1/sessions/poppy/windows/w10",
            "POST /api/v1/inbox/17/reply",
            "POST /api/v1/inbox/18/answer",
            "POST /api/v1/inbox/17/respond",
            "POST /api/v1/inbox/19/dismiss",
        ])
        func body(_ i: Int) throws -> [String: Any] {
            let data = try XCTUnwrap(t.requests[i].httpBody)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        XCTAssertEqual(try body(0)["name"] as? String, "nova")
        let w = try body(1)
        XCTAssertNil(w["name"]) // nome em branco nao vai
        XCTAssertEqual(w["workspace"] as? Int, 2)
        XCTAssertNil(w["focus"]) // o servidor ja usa focus:false
        let rep = try body(3)
        XCTAssertEqual(rep["decision"] as? String, "once")
        XCTAssertEqual(rep["risk_ack"] as? [String], ["rm-recursive"])
        XCTAssertEqual(rep["summary"] as? String, "Bash: rm -rf build/")
        XCTAssertNil(rep["plan_sha"])
        XCTAssertEqual(try body(4)["answer"] as? String, "sim")
        XCTAssertEqual(try body(5)["prompt_id"] as? String, "p-77")
        XCTAssertNil(t.requests[2].httpBody)
    }

    func testErroDoServidorViraAPIError() async throws {
        let t = MockTransport { _ in .init(status: 409, body: Fixture.bytes("erro_needs_attach.json")) }
        do {
            _ = try await makeClient(t).reply(itemID: "17", ReplyRequest(decision: .deny))
            XCTFail("devia lancar")
        } catch let e as APIError {
            XCTAssertEqual(e.kind, .needsAttach)
        }
    }

    func testRateLimitedLeRetryAfter() async throws {
        let t = MockTransport { _ in
            .init(status: 429, body: Fixture.bytes("erro_rate_limited.json"), headers: ["Retry-After": "2"])
        }
        do {
            try await makeClient(t).dismiss(itemID: "1")
            XCTFail("devia lancar")
        } catch let e as APIError {
            XCTAssertEqual(e.kind, .rateLimited)
            XCTAssertEqual(e.retryAfter, 2)
        }
    }

    func testIdentificadoresInvalidosNaoSaemDoCliente() async {
        let t = MockTransport { _ in .init(status: 200, body: Data("{}".utf8)) }
        let c = makeClient(t)
        do { _ = try await c.session("../x"); XCTFail("devia lancar") } catch {}
        do { try await c.closeWindow(session: "poppy", id: "w1/../x"); XCTFail("devia lancar") } catch {}
        do { _ = try await c.createSession(name: "nome invalido!"); XCTFail("devia lancar") } catch {}
        XCTAssertTrue(t.requests.isEmpty)
    }

    func testEventosViaTransporte() async throws {
        let t = MockTransport { _ in .init(status: 200, body: Fixture.bytes("events_sse.txt")) }
        var got: [SSEEvent] = []
        for try await e in makeClient(t).events(afterSeq: 40, bootID: "9f2c41d07a3e8b65") { got.append(e) }
        XCTAssertEqual(got.map(\.event), ["ready", "attention", "agent-state", "gap"])
        XCTAssertEqual(t.requests[0].url?.absoluteString,
                       "https://exemplo.ts.net/api/v1/events?after_seq=40&boot_id=9f2c41d07a3e8b65")
        XCTAssertNil(t.requests[0].value(forHTTPHeaderField: "X-Poppy-Client"))
    }

    func testEventosErroHTTP() async {
        let t = MockTransport { _ in .init(status: 401, body: Data()) }
        do {
            for try await _ in makeClient(t).events() {}
            XCTFail("devia lancar")
        } catch let e as APIError {
            XCTAssertEqual(e.kind, .accessDenied)
        } catch {
            XCTFail("\(error)")
        }
    }
}

// MARK: - endpoints

final class EndpointsTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(Endpoints(serverURL: "exemplo.ts.net")?.base.absoluteString, "https://exemplo.ts.net")
        XCTAssertEqual(Endpoints(serverURL: "https://exemplo.ts.net/ws/")?.base.absoluteString, "https://exemplo.ts.net")
        XCTAssertEqual(Endpoints(serverURL: "https://exemplo.ts.net:8443/x/ws?a=1#f")?.base.absoluteString, "https://exemplo.ts.net:8443/x")
        XCTAssertNil(Endpoints(serverURL: "http://exemplo.ts.net"))
        XCTAssertNotNil(Endpoints(serverURL: "http://127.0.0.1:8080"))
        XCTAssertNotNil(Endpoints(serverURL: "http://localhost:8080"))
        XCTAssertNil(Endpoints(serverURL: "  "))
        XCTAssertNil(Endpoints(serverURL: "ftp://x"))
    }

    func testWsURL() throws {
        let e = try XCTUnwrap(Endpoints(serverURL: "https://exemplo.ts.net"))
        XCTAssertEqual(e.wsURL(session: "poppy", window: "w2")?.absoluteString,
                       "wss://exemplo.ts.net/ws?session=poppy&mode=satellite&window=w2")
        XCTAssertEqual(e.wsURL(session: "poppy", window: nil)?.absoluteString,
                       "wss://exemplo.ts.net/ws?session=poppy&mode=satellite")
        XCTAssertEqual(e.wsURL(session: nil, window: nil)?.absoluteString, "wss://exemplo.ts.net/ws?mode=satellite")
        XCTAssertEqual(e.wsURL(session: " ", window: "")?.absoluteString, "wss://exemplo.ts.net/ws?mode=satellite")
        XCTAssertNil(e.wsURL(session: "po ppy", window: nil))
        XCTAssertNil(e.wsURL(session: "poppy", window: "a b"))
        XCTAssertNil(e.wsURL(session: "poppy", window: "w&mode=x"))
        XCTAssertNil(e.wsURL(session: "poppy", window: String(repeating: "a", count: 65)))
        XCTAssertNotNil(e.wsURL(session: "poppy", window: String(repeating: "a", count: 64)))
        let local = try XCTUnwrap(Endpoints(serverURL: "http://127.0.0.1:9000"))
        XCTAssertEqual(local.wsURL(session: "s", window: "w1")?.absoluteString,
                       "ws://127.0.0.1:9000/ws?session=s&mode=satellite&window=w1")
        let pref = try XCTUnwrap(Endpoints(serverURL: "https://h.ts.net/app/ws"))
        XCTAssertEqual(pref.wsURL(session: nil, window: "w1")?.absoluteString, "wss://h.ts.net/app/ws?mode=satellite&window=w1")
        XCTAssertEqual(pref.info.absoluteString, "https://h.ts.net/app/api/v1/info")
    }

    func testRotasDeJanelaSemFoco() throws {
        let e = try XCTUnwrap(Endpoints(serverURL: "https://exemplo.ts.net"))
        XCTAssertEqual(e.window(session: "poppy", id: "w1")?.absoluteString,
                       "https://exemplo.ts.net/api/v1/sessions/poppy/windows/w1")
        XCTAssertEqual(e.windows(session: "poppy")?.absoluteString,
                       "https://exemplo.ts.net/api/v1/sessions/poppy/windows")
        XCTAssertNil(e.window(session: "poppy", id: "../x"))
    }

    func testIDsValidos() {
        XCTAssertTrue(Endpoints.isValidWindowID("w1"))
        XCTAssertTrue(Endpoints.isValidWindowID("a_B-9"))
        XCTAssertFalse(Endpoints.isValidWindowID(""))
        XCTAssertFalse(Endpoints.isValidWindowID("w/1"))
        XCTAssertFalse(Endpoints.isValidWindowID("w1\n"))
    }

    func testEventsURL() throws {
        let e = try XCTUnwrap(Endpoints(serverURL: "https://exemplo.ts.net"))
        XCTAssertEqual(e.events(afterSeq: nil, bootID: "abc").absoluteString, "https://exemplo.ts.net/api/v1/events")
        XCTAssertEqual(e.events(afterSeq: 7, bootID: nil).absoluteString, "https://exemplo.ts.net/api/v1/events?after_seq=7")
    }
}

// MARK: - SSE

final class SSEParserTests: XCTestCase {
    func testFixtureInteira() throws {
        var p = SSEParser()
        var evs = p.feed(try Fixture.data("events_sse.txt"))
        evs += p.finish()
        XCTAssertEqual(evs.map(\.event), ["ready", "attention", "agent-state", "gap"])
        XCTAssertEqual(evs[0].id, "43")
        XCTAssertEqual(evs[0].retry, 3000)
        XCTAssertEqual(evs[2].id, "45")
        XCTAssertEqual(evs[3].data, "")
        let a = ServerEvent(evs[1])
        XCTAssertEqual(a.kind, .attention)
        XCTAssertEqual(a.seq, 44)
        XCTAssertEqual(a.attentionID, "20")
        XCTAssertEqual(a.session, "poppy")
        XCTAssertEqual(a.action, "open")
        let s = ServerEvent(evs[2])
        XCTAssertEqual(s.kind, .agentState)
        XCTAssertEqual(s.window, "w1")
        XCTAssertEqual(s.state, "working")
    }

    func testFatiasDeUmByteIguaisAoTodo() throws {
        let raw = try Fixture.data("events_sse.txt")
        var whole = SSEParser()
        var a = whole.feed(raw)
        a += whole.finish()
        var byte = SSEParser()
        var b: [SSEEvent] = []
        for x in raw { b += byte.feed(Data([x])) }
        b += byte.finish()
        XCTAssertEqual(a, b)
    }

    func testMultilinhaComentarioCRLF() {
        var p = SSEParser()
        let evs = p.feed(": ping\r\n\r\nid: 9\r\nevent: x\r\ndata: a\r\ndata: b\r\n\r\ndata:sem espaco\n\n")
        XCTAssertEqual(evs.count, 2) // o comentario sozinho nao gera evento
        XCTAssertEqual(evs[0], SSEEvent(id: "9", event: "x", data: "a\nb", retry: nil))
        XCTAssertEqual(evs[1].event, "message")
        XCTAssertEqual(evs[1].data, "sem espaco")
        XCTAssertEqual(evs[1].id, "9") // last-event-id persiste
        XCTAssertEqual(p.lastEventID, "9")
    }

    func testCRSolto() {
        var p = SSEParser()
        let evs = p.feed("event: a\rdata: 1\r\r")
        XCTAssertEqual(evs, [SSEEvent(id: nil, event: "a", data: "1", retry: nil)])
    }

    func testBOMEUTF8PartidoEntreFatias() {
        var p = SSEParser()
        let bytes = Array("\u{FEFF}data: caf\u{E9} \u{1F600}\n\n".utf8)
        var evs: [SSEEvent] = []
        for b in bytes { evs += p.feed(bytes: [b]) }
        XCTAssertEqual(evs.map(\.data), ["caf\u{E9} \u{1F600}"])
    }

    func testPingEntreLinhasNaoInterrompe() {
        var p = SSEParser()
        var evs = p.feed("event: a\ndata: 1\n")
        evs += p.feed(": ping\n")
        evs += p.feed("\n")
        XCTAssertEqual(evs.count, 1)
        XCTAssertEqual(evs[0].data, "1")
    }

    func testIncompletoDescartadoNoFim() {
        var p = SSEParser()
        var evs = p.feed("data: meio")
        evs += p.finish()
        XCTAssertTrue(evs.isEmpty)
    }
}

final class EventCursorTests: XCTestCase {
    private func ev(_ id: String?, _ name: String, _ data: String) -> SSEEvent {
        SSEEvent(id: id, event: name, data: data)
    }

    func testAvancaComIdsEGuardaBoot() {
        var c = EventCursor()
        XCTAssertEqual(c.apply(ev("43", "ready", #"{"boot_id":"B1","replayed":1,"seq":43}"#)), .ready(replayed: 1))
        XCTAssertEqual(c.seq, 43)
        XCTAssertEqual(c.bootID, "B1")
        XCTAssertEqual(c.apply(ev("44", "attention", #"{"seq":44,"type":"attention"}"#)), .event)
        XCTAssertEqual(c.apply(ev("45", "agent-state", "{}")), .event)
        XCTAssertEqual(c.seq, 45)
        XCTAssertEqual(c.apply(ev("10", "agent-state", "{}")), .event) // nunca recua
        XCTAssertEqual(c.seq, 45)
    }

    func testGapPedeRefetch() {
        var c = EventCursor(seq: 5, bootID: "B")
        XCTAssertEqual(c.apply(ev(nil, "gap", "")), .refetch)
        XCTAssertEqual(c.apply(ev(nil, "gap", #"{"type":"gap","reason":"daemon_closed"}"#)), .refetch)
        XCTAssertEqual(c.seq, 5)
    }

    func testBootIdDiferentePedeRefetchEReinicia() {
        var c = EventCursor(seq: 500, bootID: "B1")
        XCTAssertEqual(c.apply(ev("3", "ready", #"{"boot_id":"B2","replayed":0,"seq":3}"#)), .refetch)
        XCTAssertEqual(c.bootID, "B2")
        XCTAssertEqual(c.seq, 3)
        XCTAssertEqual(c.apply(ev("4", "agent-state", "{}")), .event)
        XCTAssertEqual(c.seq, 4)
    }
}

// MARK: - snippets

final class SnippetTests: XCTestCase {
    func testPayload() {
        XCTAssertEqual(Snippet(title: "c", text: "claude").payload, Array("claude\r".utf8))
        XCTAssertEqual(Snippet(title: "c", text: "ls\n", appendsReturn: true).payload, Array("ls\r".utf8))
        XCTAssertEqual(Snippet(title: "c", text: "a\r\nb", appendsReturn: false).payload, Array("a\rb".utf8))
    }

    func testDefaultsTemClaude() {
        XCTAssertTrue(SnippetList.defaults.contains { $0.text == "claude" })
    }

    func testRoundTripELimpeza() throws {
        let raw = [Snippet(id: "a", title: "  um  ", text: "x"), Snippet(id: "b", title: "", text: "y"),
                   Snippet(id: "a", title: "dois", text: "z")]
        let data = try XCTUnwrap(SnippetList.encode(raw))
        let back = SnippetList.decode(data)
        XCTAssertEqual(back.map(\.title), ["um", "dois"])
        XCTAssertEqual(Set(back.map(\.id)).count, 2)
        XCTAssertEqual(SnippetList.decode(nil), SnippetList.defaults)
        XCTAssertEqual(SnippetList.decode(Data("lixo".utf8)), SnippetList.defaults)
        XCTAssertEqual(SnippetList.decode(Data("[]".utf8)), [])
    }

    func testLimites() {
        let many = (0..<50).map { Snippet(title: "t\($0)", text: "x") }
        XCTAssertEqual(SnippetList.sanitized(many).count, SnippetList.maxCount)
        let long = Snippet(title: "t", text: String(repeating: "a", count: 5000))
        XCTAssertEqual(SnippetList.sanitized([long])[0].text.count, SnippetList.maxTextLength)
    }
}
