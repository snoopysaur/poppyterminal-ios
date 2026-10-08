import Foundation

/// Endereco do servidor informado pelo usuario em runtime (nunca no repo).
/// Aceita `host`, `https://host` ou `https://host/ws`; devolve a URL wss do /ws.
public enum ServerEndpoint {
    public static func parse(_ raw: String) -> URL? {
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
