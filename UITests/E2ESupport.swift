import XCTest

/// Ponte do teste com o servidor REAL (scripts/e2e-server.sh): le o estado pela mesma
/// API HTTP que o app usa, para provar o que a tela nao mostra (por exemplo, o foco do PC).
/// O endereco vem de `TEST_RUNNER_E2E_URL` (xcodebuild repassa como `E2E_URL`).
@MainActor
enum E2E {
    static var baseURL: URL? {
        ProcessInfo.processInfo.environment["E2E_URL"].flatMap(URL.init(string:))
    }
    static var legacyURL: String? {
        ProcessInfo.processInfo.environment["E2E_LEGACY_URL"]
    }
    /// Janela semeada como "Claude Code" com transcript (o chat dela abre por padrao).
    static let chatWindow = "conversa"
    static var session: String {
        ProcessInfo.processInfo.environment["E2E_SESSION"] ?? "e2e"
    }

    struct Window: Equatable {
        let id: String
        let name: String
        let focused: Bool
    }

    /// Chama a API; `nil` em erro de rede. Devolve (status, JSON).
    static func call(_ method: String, _ path: String, body: [String: Any]? = nil) async -> (Int, [String: Any])? {
        guard let base = baseURL, let url = URL(string: path, relativeTo: base) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.setValue("e2e-uitest", forHTTPHeaderField: "X-Poppy-Client")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return nil }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (http.statusCode, json)
    }

    static func windows() async -> [Window] {
        guard let (code, json) = await call("GET", "/api/v1/sessions/\(session)"), code == 200,
              let workspaces = json["workspaces"] as? [[String: Any]] else { return [] }
        return workspaces.flatMap { ($0["windows"] as? [[String: Any]]) ?? [] }.compactMap { w in
            guard let id = w["id"] as? String else { return nil }
            let name = (w["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (w["title"] as? String) ?? id
            return Window(id: id, name: name, focused: (w["focused"] as? Bool) ?? false)
        }
    }

    /// Pede ao semeador do runner uma aprovacao/pergunta NOVA (o hold do fork dura so 300 s).
    static func seed(_ kind: String, tag: String) async -> Bool {
        guard let s = ProcessInfo.processInfo.environment["E2E_SEED_URL"], let url = URL(string: s + "/seed/\(kind)/\(tag)") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 100)
        req.httpMethod = "POST"
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    static func focusedID() async -> String? { await windows().first(where: \.focused)?.id }

    static func inboxSummaries() async -> [String] {
        guard let (code, json) = await call("GET", "/api/v1/inbox"), code == 200,
              let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { $0["summary"] as? String }
    }

    /// Espera `check` ficar verdadeiro (ate `timeout` s).
    static func eventually(_ timeout: TimeInterval = 15, _ check: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if await check() { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return await check()
    }

    /// Confere por `seconds` que `check` continua verdadeiro (o foco nao pode mexer).
    static func holds(_ seconds: TimeInterval = 3, _ check: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            if !(await check()) { return false }
            try? await Task.sleep(nanoseconds: 300_000_000)
        } while Date() < end
        return true
    }
}

@MainActor
extension XCTestCase {
    /// Sobe o app; na primeira conexao preenche URL (e senha vazia) e toca Conectar.
    func launchConnected(extraArgs: [String] = [], file: StaticString = #filePath, line: UInt = #line) throws -> XCUIApplication {
        guard let url = E2E.baseURL else { throw XCTSkip("E2E_URL ausente: so roda contra o servidor real (scripts/e2e-server.sh)") }
        let app = XCUIApplication()
        app.launchArguments += extraArgs
        // Face ID: os E2E usam o stub de DEBUG (aceita tudo) a menos que o teste escolha outro modo.
        if !extraArgs.contains("-auth-stub") { app.launchArguments += ["-auth-stub", "allow"] }
        app.launch()
        let field = app.textFields["field-url"]
        if field.waitForExistence(timeout: 6) {
            field.tap()
            field.typeText(url.absoluteString)
            let connect = app.buttons["btn-conectar"]
            XCTAssertTrue(connect.waitForExistence(timeout: 5), "botao Conectar", file: file, line: line)
            connect.tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Sessões"].waitForExistence(timeout: 20), "TabView depois de conectar", file: file, line: line)
        return app
    }

    /// Primeiro elemento (qualquer tipo) cujo rotulo contem `text`.
    func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Balao do chat: o texto vai no valor de acessibilidade (o rotulo e "Claude"/"Voce").
    func bubble(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
    }

    func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Abre o detalhe da sessao do E2E na aba Sessoes.
    func openSession(_ app: XCUIApplication) {
        app.tabBars.buttons["Sessões"].tap()
        let row = element(app, containing: E2E.session)
        XCTAssertTrue(row.waitForExistence(timeout: 20), "sessao \(E2E.session) na lista")
        row.tap()
        XCTAssertTrue(app.buttons["btn-nova-janela"].waitForExistence(timeout: 10), "detalhe da sessao")
    }
}
