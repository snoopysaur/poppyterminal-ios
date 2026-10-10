import Foundation

/// Deep link do push (`poppyterminal://inbox/<id>`), com parser ESTRITO.
///
/// O push do ntfy so leva um id opaco. O app nunca usa texto vindo do push: valida o formato exato,
/// pergunta ao servidor de que item se trata (`GET /api/v1/push/{id}`) e SO navega.
/// Aceita exatamente `poppyterminal://inbox/` + 32 hex minusculo. Qualquer outra coisa (host ou
/// caminho diferente, maiuscula, 31/33 caracteres, `..`, `%2e%2e`, query, fragmento, barra final,
/// URL longa) devolve nil e o app nao faz nada.
public enum DeepLink: Hashable, Sendable {
    /// `pushID`: o id opaco do push (NAO e o id do item da Inbox).
    case inbox(pushID: String)

    public static let scheme = "poppyterminal"
    /// Limite da URL inteira (a valida tem 54 caracteres). Maior que isso nem e analisada.
    public static let maxLength = 128
    static let prefix = "poppyterminal://inbox/"
    static let idLength = 32

    public static func parse(_ url: URL) -> DeepLink? { parse(url.absoluteString) }

    public static func parse(_ raw: String) -> DeepLink? {
        let bytes = Array(raw.utf8)
        guard bytes.count <= maxLength, raw.hasPrefix(prefix) else { return nil }
        let id = bytes.dropFirst(prefix.utf8.count)
        guard id.count == idLength, id.allSatisfy(isLowerHex) else { return nil }
        return .inbox(pushID: String(decoding: id, as: UTF8.self))
    }

    /// `^[0-9a-f]{32}$` (o mesmo formato que o servidor aceita em `/api/v1/push/{id}`).
    public static func isValidPushID(_ s: String) -> Bool {
        let u = Array(s.utf8)
        return u.count == idLength && u.allSatisfy(isLowerHex)
    }

    private static func isLowerHex(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x66)
    }
}

/// Resposta de `GET /api/v1/push/{id}`: o item da Inbox a que o push se refere.
public struct PushTarget: Decodable, Sendable, Equatable {
    public var inboxId: String
    public init(inboxId: String) { self.inboxId = inboxId }
}
