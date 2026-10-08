import Foundation

/// Endereco do servidor informado pelo usuario em runtime (nunca no repo).
/// Aceita `host`, `https://host` ou `https://host/ws`; devolve a URL wss do /ws.
public enum ServerEndpoint {
    public static func parse(_ raw: String, session: String = "") -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var comps = URLComponents(string: text),
              comps.scheme?.lowercased() == "https",
              let host = comps.host, !host.isEmpty
        else { return nil }
        comps.scheme = "wss"
        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/ws") { path += "/ws" }
        comps.path = path
        comps.query = nil
        let name = SessionName.normalize(session)
        if !name.isEmpty {
            guard SessionName.isValid(name) else { return nil }
            comps.queryItems = [URLQueryItem(name: "session", value: name)]
        }
        comps.fragment = nil
        comps.user = nil
        comps.password = nil
        return comps.url
    }
}

/// Cabecalho Basic (fallback de senha do tuios-web).
public enum BasicAuth {
    public static func header(user: String, password: String) -> String {
        "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }
}

/// Atraso de reconexao: 1, 2, 4, 8, 16, 30 s (teto).
public struct ReconnectPolicy: Sendable, Equatable {
    public var maxDelay: Double
    public init(maxDelay: Double = 30) { self.maxDelay = maxDelay }

    public func delay(forAttempt attempt: Int) -> Double {
        let a = max(0, min(attempt, 10))
        return min(maxDelay, Double(1 << a))
    }
}

/// Classifica falhas de rede (codigos de URLError) para decidir a tela.
public enum ConnectionFailure: Sendable, Equatable {
    case networkUnreachable   // provavel Tailscale desligado
    case denied               // 401/403 no upgrade
    case other

    public static func classify(urlErrorCode code: Int) -> ConnectionFailure {
        switch code {
        case -1001, -1003, -1004, -1005, -1006, -1009, -1200, -1202:
            return .networkUnreachable
        case -1011, -1013:
            return .denied
        default:
            return .other
        }
    }
}

/// Nome de sessao do servidor: ^[A-Za-z0-9_-]{1,32}$. Vazio = sessao padrao.
public enum SessionName {
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Valida um nome ja normalizado (nao vazio).
    public static func isValid(_ name: String) -> Bool {
        let u = Array(name.utf8)
        guard (1...32).contains(u.count) else { return false }
        return u.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) ||
            ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x5F || $0 == 0x2D
        }
    }

    /// Campo do app: vazio e valido (sessao padrao).
    public static func isAcceptable(_ raw: String) -> Bool {
        let n = normalize(raw)
        return n.isEmpty || isValid(n)
    }
}
