import XCTest
import PoppyKit
@testable import PoppyTerminal

/// Autenticador falso: devolve o resultado combinado e conta quantas vezes foi chamado.
final class FakeAuthenticator: Authenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var _outcome: AuthOutcome
    private var _calls = 0
    private var _delay: Duration = .zero

    init(_ outcome: AuthOutcome) { _outcome = outcome }

    var outcome: AuthOutcome {
        get { lock.withLock { _outcome } }
        set { lock.withLock { _outcome = newValue } }
    }
    var delay: Duration {
        get { lock.withLock { _delay } }
        set { lock.withLock { _delay = newValue } }
    }
    var calls: Int { lock.withLock { _calls } }

    func authenticate(reason: String) async -> AuthOutcome {
        let (out, wait) = lock.withLock { () -> (AuthOutcome, Duration) in
            _calls += 1
            return (_outcome, _delay)
        }
        if wait > .zero { try? await Task.sleep(for: wait) }
        return out
    }
}

/// Relogio manual do teste.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_790_000_000)
    var date: Date { lock.withLock { t } }
    func advance(_ seconds: TimeInterval) { lock.withLock { t = t.addingTimeInterval(seconds) } }
}

@MainActor
final class AuthGateTests: XCTestCase {
    private var clock: TestClock!

    override func setUp() async throws { clock = TestClock() }

    private func gate(_ auth: FakeAuthenticator, locked: Bool = false) -> AuthGate {
        let c = clock!
        return AuthGate(authenticator: auth, now: { c.date }, startLocked: locked)
    }

    private func item(risk: [String] = []) -> InboxItem {
        InboxItem(id: "1", kind: "approval", summary: "Bash: ls", requestId: "r1", risk: risk, answerable: true)
    }

    // MARK: regras do portao

    func testAutenticacaoFalhandoBloqueiaAOrdem() async {
        let auth = FakeAuthenticator(.failed)
        let g = gate(auth)
        do {
            try await g.authorize(highRisk: false)
            XCTFail("deveria bloquear")
        } catch {
            XCTAssertEqual(error as? AuthGate.Failure, .denied)
        }
        XCTAssertEqual(auth.calls, 1)
    }

    func testCancelarBloqueiaAOrdem() async {
        let g = gate(FakeAuthenticator(.cancelled))
        do {
            try await g.authorize(highRisk: false)
            XCTFail("deveria bloquear")
        } catch {
            XCTAssertEqual(error as? AuthGate.Failure, .cancelled)
        }
    }

    func testGracaDe30sValeMasNaoDepois() async throws {
        let auth = FakeAuthenticator(.success)
        let g = gate(auth)
        try await g.authorize(highRisk: false)
        XCTAssertEqual(auth.calls, 1)
        clock.advance(29)
        try await g.authorize(highRisk: false)
        XCTAssertEqual(auth.calls, 1, "dentro da graca nao pede de novo")
        clock.advance(1) // 30 s: venceu
        try await g.authorize(highRisk: false)
        XCTAssertEqual(auth.calls, 2, "com 30 s a graca acabou")
    }

    func testSegundoPlanoZeraAGraca() async throws {
        let auth = FakeAuthenticator(.success)
        let g = gate(auth)
        try await g.authorize(highRisk: false)
        g.scenePhaseChanged(.background)
        clock.advance(2)
        g.scenePhaseChanged(.active)
        try await g.authorize(highRisk: false)
        XCTAssertEqual(auth.calls, 2, "apos o segundo plano pede de novo, mesmo dentro dos 30 s")
    }

    func testRiscoAltoPedeMesmoDentroDaGraca() async throws {
        let auth = FakeAuthenticator(.success)
        let g = gate(auth)
        try await g.authorize(highRisk: false)
        try await g.authorize(highRisk: true)
        XCTAssertEqual(auth.calls, 2)
        // Controle: sem risco, a graca vale (prova que o teste enxerga a diferenca).
        try await g.authorize(highRisk: false)
        XCTAssertEqual(auth.calls, 2)
    }

    func testSemBiometriaNemSenhaBloqueiaOrdensEMarcaOAviso() async {
        let g = gate(FakeAuthenticator(.unavailable))
        XCTAssertFalse(g.ordersBlocked)
        do {
            try await g.authorize(highRisk: false)
            XCTFail("deveria bloquear")
        } catch {
            XCTAssertEqual(error as? AuthGate.Failure, .unavailable)
        }
        XCTAssertTrue(g.ordersBlocked)
    }

    func testAvaliacoesSimultaneasCompartilhamAMesmaResposta() async throws {
        let auth = FakeAuthenticator(.success)
        auth.delay = .milliseconds(80)
        let g = gate(auth)
        async let a: Void = g.authorize(highRisk: true)
        async let b: Void = g.authorize(highRisk: true)
        _ = try await (a, b)
        XCTAssertEqual(auth.calls, 1, "dois toques seguidos = um so pedido ao sistema")
    }

    // MARK: trava ao abrir e apos segundo plano

    func testAbreTravadoEDesbloqueiaComSucesso() async {
        let g = gate(FakeAuthenticator(.success), locked: true)
        XCTAssertTrue(g.isLocked)
        let r = await g.unlock()
        XCTAssertEqual(r, .success)
        XCTAssertFalse(g.isLocked)
    }

    func testFalhaNoDesbloqueioMantemTravado() async {
        let g = gate(FakeAuthenticator(.failed), locked: true)
        let r = await g.unlock()
        XCTAssertEqual(r, .failed)
        XCTAssertTrue(g.isLocked)
    }

    func testSemBiometriaNemSenhaLiberaSoALeitura() async {
        let g = gate(FakeAuthenticator(.unavailable), locked: true)
        _ = await g.unlock()
        XCTAssertFalse(g.isLocked)
        XCTAssertTrue(g.ordersBlocked)
    }

    func testTravaVoltaAposCincoMinutosEmSegundoPlano() {
        let g = gate(FakeAuthenticator(.success))
        g.scenePhaseChanged(.background)
        clock.advance(299)
        g.scenePhaseChanged(.active)
        XCTAssertFalse(g.isLocked, "299 s: ainda destravado")
        g.scenePhaseChanged(.background)
        clock.advance(300)
        g.scenePhaseChanged(.active)
        XCTAssertTrue(g.isLocked, "300 s: travado")
    }

    // MARK: ServerStore (reply/answer/respond)

    private func makeStore(_ auth: FakeAuthenticator) -> ServerStore {
        let defaults = UserDefaults(suiteName: "authgate-tests-\(UUID().uuidString)")!
        return ServerStore(defaults: defaults, gate: gate(auth))
    }

    func testAprovarNegadoPeloFaceIDNaoVaiAoServidor() async {
        let auth = FakeAuthenticator(.failed)
        let store = makeStore(auth)
        do {
            try await store.reply(to: item(), decision: .once)
            XCTFail("deveria bloquear")
        } catch {
            XCTAssertTrue(APIError.from(error).userMessage.contains("Nada foi enviado"), "\(error)")
        }
        XCTAssertEqual(auth.calls, 1)
    }

    func testControleNegativoComFaceIDOkAOrdemSegueAteOCliente() async {
        // Sem cliente configurado a ordem falha DEPOIS do portao, com outra mensagem: prova que o
        // teste anterior falhou pelo Face ID e nao por outro motivo.
        let auth = FakeAuthenticator(.success)
        let store = makeStore(auth)
        do {
            try await store.reply(to: item(), decision: .once)
            XCTFail("sem cliente deveria falhar")
        } catch {
            XCTAssertFalse(APIError.from(error).userMessage.contains("Nada foi enviado"))
        }
        XCTAssertEqual(auth.calls, 1)
    }

    func testNegarNaoPedeFaceID() async {
        let auth = FakeAuthenticator(.failed)
        let store = makeStore(auth)
        do { try await store.reply(to: item(), decision: .deny) } catch {}
        XCTAssertEqual(auth.calls, 0, "Negar nao pede Face ID")
    }

    func testResponderPerguntaNegadoPeloFaceID() async {
        let auth = FakeAuthenticator(.failed)
        let store = makeStore(auth)
        do {
            try await store.answer(item(), with: "sim")
            XCTFail("deveria bloquear")
        } catch {
            XCTAssertTrue(APIError.from(error).userMessage.contains("Nada foi enviado"))
        }
        XCTAssertEqual(auth.calls, 1)
    }

    func testRespondPedeFaceIDMasDenyNao() async {
        let auth = FakeAuthenticator(.failed)
        let store = makeStore(auth)
        do {
            try await store.respond(to: item(), action: "approve", promptId: "p1")
            XCTFail("deveria bloquear")
        } catch {
            XCTAssertTrue(APIError.from(error).userMessage.contains("Nada foi enviado"))
        }
        XCTAssertEqual(auth.calls, 1)
        do { try await store.respond(to: item(), action: "deny", promptId: "p1") } catch {}
        XCTAssertEqual(auth.calls, 1, "deny nao pede Face ID")
    }

    func testRiscoAltoNoStorePedeDeNovoDentroDaGraca() async {
        let auth = FakeAuthenticator(.success)
        let store = makeStore(auth)
        do { try await store.reply(to: item(), decision: .once) } catch {}
        do { try await store.reply(to: item(), decision: .once) } catch {}
        XCTAssertEqual(auth.calls, 1, "sem risco: graca")
        do { try await store.reply(to: item(risk: ["rm -rf"]), decision: .once) } catch {}
        XCTAssertEqual(auth.calls, 2, "com risco: pede de novo")
    }

    // MARK: ChatStore.send

    func testEnviarNoChatComFaceIDNegadoNaoEnviaEGuardaORascunho() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("authgate-chat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let backend = FakeChatBackend()
        let auth = FakeAuthenticator(.failed)
        let chat = ChatStore(session: "s1", window: "w1", serverKey: "http://exemplo.invalid:8080", backend: backend,
                             cache: ChatCache(directory: dir), gate: gate(auth))
        chat.draft = "rode os testes"
        await chat.send()
        XCTAssertTrue(backend.sent.isEmpty, "nada pode sair sem Face ID")
        XCTAssertEqual(chat.draft, "rode os testes")
        XCTAssertNil(chat.outgoing)
        XCTAssertFalse(chat.sending)
        XCTAssertNotNil(chat.lastError)

        // Controle: com Face ID ok, a mesma mensagem sai.
        auth.outcome = .success
        await chat.send()
        XCTAssertEqual(backend.sent, ["rode os testes"])
        chat.stop()
    }

    // MARK: stub (DEBUG)

    #if DEBUG
    func testStubSoEntraComOArgumentoDeLancamento() {
        XCTAssertNil(StubAuthenticator.fromLaunchArguments(["app"]))
        XCTAssertNil(StubAuthenticator.fromLaunchArguments(["app", "-auth-stub"]))
        XCTAssertNil(StubAuthenticator.fromLaunchArguments(["app", "-auth-stub", "talvez"]))
        XCTAssertEqual(StubAuthenticator.fromLaunchArguments(["app", "-auth-stub", "deny"])?.mode, .deny)
        XCTAssertEqual(StubAuthenticator.marker, "POPPY_AUTH_STUB_DEBUG_ONLY")
    }
    #endif

    // MARK: Motion

    func testTetoDoFaceIDParaWaving() {
        XCTAssertLessThanOrEqual(Motion.faceIDToWaving, .milliseconds(400))
        XCTAssertLessThanOrEqual(Motion.faceIDToWavingSeconds, 0.4)
    }
}
