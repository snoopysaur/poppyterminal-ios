import Foundation

/// Atalho de texto da barra de snippets: um toque envia `text` ao terminal.
public struct Snippet: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var text: String
    /// Acrescenta Enter (CR) ao final.
    public var appendsReturn: Bool

    public init(id: String = UUID().uuidString, title: String, text: String, appendsReturn: Bool = true) {
        self.id = id
        self.title = title
        self.text = text
        self.appendsReturn = appendsReturn
    }

    /// Bytes enviados ao PTY: quebras de linha viram CR; Enter opcional no fim.
    public var payload: [UInt8] {
        var s = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        if appendsReturn && !s.hasSuffix("\r") { s += "\r" }
        return Array(s.utf8)
    }

    public var isSendable: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Lista de snippets (persistida como JSON em UserDefaults pelo app).
public enum SnippetList {
    public static let maxCount = 24
    public static let maxTextLength = 1024

    public static let defaults: [Snippet] = [
        Snippet(id: "claude", title: "claude", text: "claude"),
        Snippet(id: "ls", title: "ls -la", text: "ls -la"),
        Snippet(id: "git-status", title: "git status", text: "git status"),
    ]

    /// Remove vazios, corta tamanhos e limita a quantidade.
    public static func sanitized(_ list: [Snippet]) -> [Snippet] {
        var seen = Set<String>()
        var out: [Snippet] = []
        for var s in list where s.isSendable {
            s.title = String(s.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
            s.text = String(s.text.prefix(maxTextLength))
            if !seen.insert(s.id).inserted { s.id = UUID().uuidString }
            out.append(s)
            if out.count == maxCount { break }
        }
        return out
    }

    public static func encode(_ list: [Snippet]) -> Data? {
        try? JSONEncoder().encode(sanitized(list))
    }

    /// Dado ausente ou corrompido volta aos padroes; lista vazia salva e respeitada.
    public static func decode(_ data: Data?) -> [Snippet] {
        guard let data, let list = try? JSONDecoder().decode([Snippet].self, from: data) else { return defaults }
        return sanitized(list)
    }
}
