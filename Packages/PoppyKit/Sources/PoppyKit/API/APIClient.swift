import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - transporte (injetavel nos testes)

public protocol APITransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Resposta em fluxo (SSE): cabecalho primeiro, depois os bytes conforme chegam.
    func stream(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>)
}

public struct URLSessionTransport: APITransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 20
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: cfg)
        }
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    }

    public func stream(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        #if canImport(FoundationNetworking)
        throw APIError.unsupported // URLSession.bytes nao existe no Linux; o SSE roda so no iOS/macOS
        #else
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        nonisolated(unsafe) let unsafeBytes = bytes // lido por uma unica Task
        let chunks = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                do {
                    var buf = Data()
                    for try await b in unsafeBytes {
                        buf.append(b)
                        // Entrega a cada fim de linha (o SSE e orientado a linha) ou 4 KB.
                        if b == 0x0A || buf.count >= 4096 {
                            continuation.yield(buf)
                            buf.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buf.isEmpty { continuation.yield(buf) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (http, chunks)
        #endif
    }
}

// MARK: - cliente

/// Cliente REST/SSE do `/api/v1` do tuios-web. Sem estado; barato de recriar.
/// Todo POST/DELETE leva `X-Poppy-Client` (o servidor recusa sem ele).
public struct APIClient: Sendable {
    public let endpoints: Endpoints
    /// Valor do cabecalho `Authorization` (Basic), ou nil (login Tailscale).
    public let authHeader: String?
    public let clientName: String
    private let transport: any APITransport

    public init(endpoints: Endpoints, authHeader: String? = nil,
                clientName: String = "PoppyTerminal-iOS",
                transport: any APITransport = URLSessionTransport()) {
        self.endpoints = endpoints
        self.authHeader = authHeader
        self.clientName = clientName
        self.transport = transport
    }

    // MARK: leitura

    public func info() async throws -> ServerInfo {
        try await send(.get, endpoints.info)
    }

    public func sessions() async throws -> SessionsResponse {
        try await send(.get, endpoints.sessions)
    }

    public func session(_ name: String) async throws -> SessionDetail {
        try await send(.get, try url(endpoints.session(name), "sessao"))
    }

    public func inbox() async throws -> InboxResponse {
        try await send(.get, endpoints.inbox)
    }

    public func prompt(itemID: String) async throws -> PromptInfo {
        try await send(.get, try url(endpoints.inbox(id: itemID, .prompt), "item"))
    }

    /// De que item da Inbox e este push? `nil` = 404 (servidor antigo, id desconhecido ou expirado em
    /// 24 h): resultado NORMAL, o app so abre a Inbox. Outros erros sobem.
    public func push(id: String) async throws -> PushTarget? {
        let u = try url(endpoints.push(id: id), "push")
        do {
            let target: PushTarget = try await send(.get, u)
            guard Endpoints.isValidID(target.inboxId) else { return nil }
            return target
        } catch let error as APIError {
            if case .api(let status, _, _, _, _) = error, status == 404 { return nil }
            throw error
        }
    }

    // MARK: sessoes e janelas (nunca mexem no foco do PC)

    public func createSession(name: String) async throws -> CreatedSession {
        guard SessionName.isValid(name) else {
            throw APIError.invalidArgument("Nome de sessao invalido: use 1 a 32 caracteres de A-Z, a-z, 0-9, _ e -.")
        }
        return try await send(.post, endpoints.sessions, body: ["name": name])
    }

    public func createWindow(session: String, name: String? = nil, workspace: Int? = nil) async throws -> CreatedWindow {
        struct Body: Encodable { var name: String?; var workspace: Int? }
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await send(.post, try url(endpoints.windows(session: session), "sessao"),
                              body: Body(name: (n?.isEmpty == false) ? n : nil, workspace: workspace))
    }

    public func closeWindow(session: String, id: String) async throws {
        try await sendVoid(.delete, try url(endpoints.window(session: session, id: id), "janela"))
    }

    // MARK: acoes de pessoa (so com `human_actions`)

    public func reply(itemID: String, _ request: ReplyRequest) async throws -> ReplyResult {
        try await send(.post, try url(endpoints.inbox(id: itemID, .reply), "item"), body: request)
    }

    public func answer(itemID: String, answer: String, question: String? = nil) async throws -> AnswerResult {
        struct Body: Encodable { var answer: String; var question: String? }
        return try await send(.post, try url(endpoints.inbox(id: itemID, .answer), "item"),
                              body: Body(answer: answer, question: question))
    }

    public func respond(itemID: String, _ request: RespondRequest) async throws -> RespondResult {
        try await send(.post, try url(endpoints.inbox(id: itemID, .respond), "item"), body: request)
    }

    public func dismiss(itemID: String) async throws {
        let _: DismissResult = try await send(.post, try url(endpoints.inbox(id: itemID, .dismiss), "item"),
                                              body: Empty())
    }

    // MARK: SSE

    /// Uma conexao SSE. Termina (sem erro) quando o servidor fecha; lanca em falha.
    /// Quem reconecta e o chamador, com `EventCursor` e `ReconnectPolicy`.
    public func events(afterSeq: UInt64? = nil, bootID: String? = nil) -> AsyncThrowingStream<SSEEvent, Error> {
        let request = makeRequest(.get, endpoints.events(afterSeq: afterSeq, bootID: bootID),
                                  body: nil, accept: "text/event-stream", timeout: 75)
        let transport = self.transport
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (http, chunks) = try await transport.stream(for: request)
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await c in chunks { body.append(c); if body.count > 8192 { break } }
                        throw APIError.parse(status: http.statusCode, body: body, retryAfter: Self.retryAfter(http))
                    }
                    var parser = SSEParser()
                    for try await chunk in chunks {
                        for ev in parser.feed(chunk) { continuation.yield(ev) }
                    }
                    for ev in parser.finish() { continuation.yield(ev) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: chat (enviar/interromper so com `human_actions`)

    public func chat(session: String, window: String, before: String? = nil, limit: Int = 50) async throws -> ChatPage {
        let target = try chatURL(endpoints.chat(session: session, window: window, before: before, limit: limit),
                                 before: before, limit: limit)
        return try await send(.get, target)
    }

    public func sendChat(session: String, window: String, text: String) async throws -> ChatSendResult {
        if let problem = ChatText.validate(text) { throw APIError.invalidArgument(problem) }
        struct Body: Encodable { var text: String }
        return try await send(.post, try url(endpoints.chatSend(session: session, window: window), "janela"),
                              body: Body(text: text))
    }

    public func interruptChat(session: String, window: String) async throws -> ChatSendResult {
        try await send(.post, try url(endpoints.chatInterrupt(session: session, window: window), "janela"),
                       body: Empty())
    }

    /// Uma conexao SSE do chat. Termina (sem erro) quando o servidor fecha (ex.: `unsupported`);
    /// lanca em falha. Quem reconecta (1, 2, 4... 30 s, `after` = ultimo cursor) e o chamador.
    public func chatEvents(session: String, window: String, after: String?) -> AsyncThrowingStream<ChatEvent, Error> {
        guard let target = endpoints.chatStream(session: session, window: window, after: after) else {
            let badCursor = after.map { !Endpoints.isValidCursor($0) } ?? false
            let why = badCursor ? "Cursor do chat invalido." : "Identificador de janela invalido."
            return AsyncThrowingStream { $0.finish(throwing: APIError.invalidArgument(why)) }
        }
        let request = makeRequest(.get, target, body: nil, accept: "text/event-stream", timeout: 75)
        let transport = self.transport
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (http, chunks) = try await transport.stream(for: request)
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await c in chunks { body.append(c); if body.count > 8192 { break } }
                        throw APIError.parse(status: http.statusCode, body: body, retryAfter: Self.retryAfter(http))
                    }
                    var parser = SSEParser()
                    for try await chunk in chunks {
                        for ev in parser.feed(chunk) { continuation.yield(ChatEvent(ev)) }
                    }
                    for ev in parser.finish() { continuation.yield(ChatEvent(ev)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: interno

    private func chatURL(_ u: URL?, before: String?, limit: Int) throws -> URL {
        if let u { return u }
        if let before, !Endpoints.isValidCursor(before) { throw APIError.invalidArgument("Cursor do chat invalido.") }
        if !(1...200).contains(limit) { throw APIError.invalidArgument("O limite do chat vai de 1 a 200.") }
        throw APIError.invalidArgument("Identificador de sessao ou janela invalido.")
    }

    private enum Method: String { case get = "GET", post = "POST", delete = "DELETE" }
    private struct Empty: Encodable {}

    private func url(_ u: URL?, _ what: String) throws -> URL {
        guard let u else { throw APIError.invalidArgument("Identificador de \(what) invalido.") }
        return u
    }

    private func makeRequest(_ method: Method, _ url: URL, body: Data?, accept: String = "application/json",
                             timeout: TimeInterval = 20) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method.rawValue
        r.timeoutInterval = timeout
        r.setValue(accept, forHTTPHeaderField: "Accept")
        if let authHeader { r.setValue(authHeader, forHTTPHeaderField: "Authorization") }
        if method != .get { r.setValue(clientName, forHTTPHeaderField: "X-Poppy-Client") }
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    private static func retryAfter(_ http: HTTPURLResponse) -> Double? {
        http.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func perform(_ method: Method, _ url: URL, body: (any Encodable)?) async throws -> Data {
        var payload: Data?
        if let body {
            let enc = JSONEncoder()
            enc.keyEncodingStrategy = .convertToSnakeCase
            payload = try enc.encode(AnyEncodable(body))
        } else if method == .post {
            payload = Data("{}".utf8)
        }
        let request = makeRequest(method, url, body: payload)
        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport.data(for: request)
        } catch {
            throw APIError.from(error)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.parse(status: http.statusCode, body: data, retryAfter: Self.retryAfter(http))
        }
        return data
    }

    private func send<T: Decodable>(_ method: Method, _ url: URL, body: (any Encodable)? = nil) async throws -> T {
        let data = try await perform(method, url, body: body)
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try dec.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func sendVoid(_ method: Method, _ url: URL, body: (any Encodable)? = nil) async throws {
        _ = try await perform(method, url, body: body)
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
