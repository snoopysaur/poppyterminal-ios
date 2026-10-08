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

    // MARK: WebSocket

    /// `/ws?session=<s>&mode=satellite&window=<id>`. `session` vazio/nil = sessao
    /// padrao do servidor; `window` nil = foco do daemon. Nome invalido -> nil.
    public func wsURL(session: String?, window: String?) -> URL? {
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
