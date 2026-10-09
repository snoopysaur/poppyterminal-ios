import Foundation

/// Rotas do servidor (`/api/v1` + `/ws`) a partir do endereco informado pelo usuario.
/// Nao existe rota de foco: o celular nunca muda o foco do PC; a janela do terminal
/// e escolhida no `/ws` com `window=<id>`.
public struct Endpoints: Sendable, Equatable {
    /// Origem http(s) (com prefixo de caminho opcional), sem barra final e sem `/ws`.
    public let base: URL

    public init(base: URL) { self.base = base }

    /// Aceita `host`, `https://host`, `https://host/ws`. So https, exceto loopback
    /// (`localhost`, `127.0.0.1`, `::1`) que aceita http (E2E no simulador).
    public init?(serverURL raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var comps = URLComponents(string: text),
              let scheme = comps.scheme?.lowercased(),
              let host = comps.host, !host.isEmpty
        else { return nil }
        switch scheme {
        case "https": break
        case "http":
            guard Endpoints.isLoopback(host) else { return nil }
        default: return nil
        }
        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/ws") { path.removeLast(3) }
        while path.hasSuffix("/") { path.removeLast() }
        comps.path = path
        comps.query = nil
        comps.fragment = nil
        comps.user = nil
        comps.password = nil
        guard let url = comps.url else { return nil }
        self.base = url
    }

    static func isLoopback(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "localhost" || h == "127.0.0.1" || h == "::1" || h == "[::1]"
    }

    /// Identificador seguro para virar segmento de caminho / parametro `window`.
    public static func isValidID(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard (1...64).contains(u.count) else { return false }
        return u.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) ||
            ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F || $0 == 0x2D
        }
    }

    /// Janela do `/ws`: `^[A-Za-z0-9_-]{1,64}$`.
    public static func isValidWindowID(_ s: String) -> Bool { isValidID(s) }

    // MARK: URLs REST

    public var info: URL { rest(["info"]) }
    public var sessions: URL { rest(["sessions"]) }
    public var inbox: URL { rest(["inbox"]) }

    public func session(_ name: String) -> URL? {
        guard SessionName.isValid(name) else { return nil }
        return rest(["sessions", name])
    }

    public func windows(session: String) -> URL? {
        guard SessionName.isValid(session) else { return nil }
        return rest(["sessions", session, "windows"])
    }

    public func window(session: String, id: String) -> URL? {
        guard SessionName.isValid(session), Endpoints.isValidID(id) else { return nil }
        return rest(["sessions", session, "windows", id])
    }

    public enum InboxAction: String, Sendable {
        case prompt, reply, answer, respond, dismiss
    }

    public func inbox(id: String, _ action: InboxAction) -> URL? {
        guard Endpoints.isValidID(id) else { return nil }
        return rest(["inbox", id, action.rawValue])
    }

    /// SSE. `bootID` so vale junto com `afterSeq` (o servidor devolve 400 sem ele).
    public func events(afterSeq: UInt64?, bootID: String?) -> URL {
        var items: [URLQueryItem] = []
        if let afterSeq {
            items.append(URLQueryItem(name: "after_seq", value: String(afterSeq)))
            if let bootID, !bootID.isEmpty {
                items.append(URLQueryItem(name: "boot_id", value: bootID))
            }
        }
        return rest(["events"], query: items)
    }

    // MARK: chat

    /// Cursor opaco do servidor: `^[0-9a-f]{16}\.[0-9]{1,15}$`.
    public static func isValidCursor(_ s: String) -> Bool {
        let parts = s.utf8.split(separator: 0x2E, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 16, (1...15).contains(parts[1].count) else { return false }
        let hex = parts[0].allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
        let dec = parts[1].allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
        return hex && dec
    }

    private func windowSegments(_ session: String, _ window: String) -> [String]? {
        guard SessionName.isValid(session), Endpoints.isValidID(window) else { return nil }
        return ["sessions", session, "windows", window]
    }

    /// `GET .../chat?before=<cursor>&limit=<1..200>`. Cursor malformado ou limite fora de 1...200 -> nil.
    public func chat(session: String, window: String, before: String? = nil, limit: Int? = nil) -> URL? {
        guard let base = windowSegments(session, window) else { return nil }
        var items: [URLQueryItem] = []
        if let before {
            guard Endpoints.isValidCursor(before) else { return nil }
            items.append(URLQueryItem(name: "before", value: before))
        }
        if let limit {
            guard (1...200).contains(limit) else { return nil }
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return rest(base + ["chat"], query: items)
    }

    /// `GET .../chat/stream?after=<cursor>` (SSE). Cursor malformado -> nil.
    public func chatStream(session: String, window: String, after: String?) -> URL? {
        guard let base = windowSegments(session, window) else { return nil }
        var items: [URLQueryItem] = []
        if let after {
            guard Endpoints.isValidCursor(after) else { return nil }
            items.append(URLQueryItem(name: "after", value: after))
        }
        return rest(base + ["chat", "stream"], query: items)
    }

    public func chatSend(session: String, window: String) -> URL? {
        windowSegments(session, window).map { rest($0 + ["chat", "send"]) }
    }

    public func chatInterrupt(session: String, window: String) -> URL? {
        windowSegments(session, window).map { rest($0 + ["chat", "interrupt"]) }
    }

    // MARK: WebSocket

    /// `/ws?session=<s>&mode=satellite&window=<id>`. `session` vazio/nil = sessao
    /// padrao do servidor; `window` nil = foco do daemon. Nome invalido -> nil.
    public func wsURL(session: String?, window: String?) -> URL? {
        wsURL(session: session, window: window, phoneView: false)
    }

    /// Com `phoneView`, acrescenta `view=phone` (o servidor desenha so o painel em foco, no tamanho do PTY).
    public func wsURL(session: String?, window: String?, phoneView: Bool) -> URL? {
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        comps.scheme = (base.scheme?.lowercased() == "http") ? "ws" : "wss"
        comps.percentEncodedPath = comps.percentEncodedPath + "/ws"
        var items: [URLQueryItem] = []
        let s = SessionName.normalize(session ?? "")
        if !s.isEmpty {
            guard SessionName.isValid(s) else { return nil }
            items.append(URLQueryItem(name: "session", value: s))
        }
        items.append(URLQueryItem(name: "mode", value: "satellite"))
        if let window, !window.isEmpty {
            guard Endpoints.isValidWindowID(window) else { return nil }
            items.append(URLQueryItem(name: "window", value: window))
        }
        if phoneView { items.append(URLQueryItem(name: "view", value: "phone")) }
        comps.queryItems = items
        return comps.url
    }

    // MARK: interno

    private func rest(_ segments: [String], query: [URLQueryItem] = []) -> URL {
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let tail = segments
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
            .joined(separator: "/")
        comps.percentEncodedPath = comps.percentEncodedPath + "/api/v1/" + tail
        comps.queryItems = query.isEmpty ? nil : query
        return comps.url ?? base
    }
}
