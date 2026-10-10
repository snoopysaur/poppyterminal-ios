import Foundation

// Modelos do chat (`/api/v1/sessions/{s}/windows/{id}/chat`). Mesmo contrato do servidor
// (fixtures em Tests/PoppyKitTests/Fixtures/api e Fixtures/chat/esperado). Decodificacao
// tolerante: campo ausente, null ou de tipo inesperado vira o valor neutro.

public enum ChatRole: String, Sendable {
    case user, assistant, unknown
}

public enum ChatKind: String, Sendable {
    case text, toolUse = "tool_use", toolResult = "tool_result", image, interrupted, unknown
}

public struct ChatToolCall: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var summary: String

    public init(id: String, name: String, summary: String = "") {
        self.id = id; self.name = name; self.summary = summary
    }

    enum CodingKeys: String, CodingKey { case id, name, summary }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.val(.id, ""); name = c.val(.name, ""); summary = c.val(.summary, "")
    }
}

public struct ChatToolResult: Codable, Sendable, Equatable {
    public var toolUseId: String
    public var ok: Bool
    public var lines: Int

    public init(toolUseId: String, ok: Bool = true, lines: Int = 0) {
        self.toolUseId = toolUseId; self.ok = ok; self.lines = lines
    }

    enum CodingKeys: String, CodingKey { case toolUseId, ok, lines }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        toolUseId = c.val(.toolUseId, ""); ok = c.val(.ok, true); lines = c.val(.lines, 0)
    }
}

public struct ChatMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var cursor: String
    /// Milissegundos desde a epoca (0 se desconhecido).
    public var ts: Int64
    /// Chave `role` do servidor.
    public var roleRaw: String
    /// Chave `kind` do servidor.
    public var kindRaw: String
    /// So em `kind == .text`; `""` nos demais.
    public var text: String
    public var truncated: Bool
    public var tool: ChatToolCall?
    public var result: ChatToolResult?

    public var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .unknown }
    public var kind: ChatKind { ChatKind(rawValue: kindRaw) ?? .unknown }
    public var date: Date { Date(timeIntervalSince1970: Double(ts) / 1000) }

    public init(id: String, cursor: String = "", ts: Int64 = 0, role: String, kind: String, text: String = "",
                truncated: Bool = false, tool: ChatToolCall? = nil, result: ChatToolResult? = nil) {
        self.id = id; self.cursor = cursor; self.ts = ts; self.roleRaw = role; self.kindRaw = kind
        self.text = text; self.truncated = truncated; self.tool = tool; self.result = result
    }

    enum CodingKeys: String, CodingKey {
        case id, cursor, ts
        case roleRaw = "role"
        case kindRaw = "kind"
        case text, truncated, tool, result
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.val(.id, "")
        cursor = c.val(.cursor, "")
        ts = c.val(.ts, 0)
        roleRaw = c.val(.roleRaw, "")
        kindRaw = c.val(.kindRaw, "")
        text = c.val(.text, "")
        truncated = c.val(.truncated, false)
        tool = c.opt(.tool)
        result = c.opt(.result)
    }
}

public struct PendingPrompt: Codable, Sendable, Equatable {
    public var inboxId: String
    public var kind: String
    public var summary: String
    /// Se o servidor (v0.3.2) disser; `nil` = decidir pelo item da caixa de entrada.
    public var answerable: Bool?

    public init(inboxId: String, kind: String, summary: String = "", answerable: Bool? = nil) {
        self.inboxId = inboxId; self.kind = kind; self.summary = summary; self.answerable = answerable
    }

    enum CodingKeys: String, CodingKey { case inboxId, kind, summary, answerable }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inboxId = c.val(.inboxId, ""); kind = c.val(.kind, ""); summary = c.val(.summary, "")
        answerable = c.opt(.answerable)
    }

    /// O cartao pode mandar a pessoa responder pelo app? Campo do servidor, depois o item da
    /// caixa de entrada; sem nenhum dos dois (item ainda nao chegou) vale "sim" e o toque rebusca.
    public func isAnswerable(item: InboxItem?) -> Bool {
        // `false` do servidor e a palavra final, venha do cartao ou do item da caixa.
        if answerable == false || item?.answerableRaw == false { return false }
        return answerable ?? item?.answerable ?? true
    }
}

public enum ChatUnsupportedReason: String, Sendable {
    case noAgent = "no_agent", notClaude = "not_claude", noSessionId = "no_session_id"
    case transcriptNotFound = "transcript_not_found", sessionMismatch = "session_mismatch"
    case unknownFormat = "unknown_format", unreadable, remoteWindow = "remote_window", other

    /// Razao do servidor; texto desconhecido vira `.other`.
    public init(reason: String) {
        self = ChatUnsupportedReason(rawValue: reason) ?? .other
    }

    /// Aviso curto, pt-BR.
    public var userMessage: String {
        switch self {
        case .noAgent: return "Nenhum Claude rodando nesta janela."
        case .notClaude: return "Esta janela nao tem o Claude Code."
        case .noSessionId: return "O Claude ainda nao identificou a conversa."
        case .transcriptNotFound: return "Nao achei a conversa no PC."
        case .sessionMismatch: return "A conversa do PC nao bate com a janela."
        case .unknownFormat: return "Formato de conversa desconhecido."
        case .unreadable: return "Nao consegui ler a conversa no PC."
        case .remoteWindow: return "Janela de outra maquina: use o terminal."
        case .other: return "Chat indisponivel nesta janela."
        }
    }
}

public struct ChatPage: Decodable, Sendable, Equatable {
    public var supported: Bool
    public var reason: String
    public var conversationId: String
    public var agentVersion: String
    public var messages: [ChatMessage]
    public var hasMore: Bool
    public var oldestCursor: String
    public var newestCursor: String
    public var state: String
    public var pending: PendingPrompt?

    /// nil quando `supported`.
    public var unsupportedReason: ChatUnsupportedReason? {
        supported ? nil : ChatUnsupportedReason(reason: reason)
    }

    public init(supported: Bool = true, reason: String = "", conversationId: String = "", agentVersion: String = "",
                messages: [ChatMessage] = [], hasMore: Bool = false, oldestCursor: String = "",
                newestCursor: String = "", state: String = "idle", pending: PendingPrompt? = nil) {
        self.supported = supported; self.reason = reason; self.conversationId = conversationId
        self.agentVersion = agentVersion; self.messages = messages; self.hasMore = hasMore
        self.oldestCursor = oldestCursor; self.newestCursor = newestCursor; self.state = state
        self.pending = pending
    }

    enum CodingKeys: String, CodingKey {
        case supported, reason, conversationId, agentVersion, messages, hasMore
        case oldestCursor, newestCursor, state, pending
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        supported = c.val(.supported, false)
        reason = c.val(.reason, "")
        conversationId = c.val(.conversationId, "")
        agentVersion = c.val(.agentVersion, "")
        messages = c.list(.messages)
        hasMore = c.val(.hasMore, false)
        oldestCursor = c.val(.oldestCursor, "")
        newestCursor = c.val(.newestCursor, "")
        state = c.val(.state, "idle")
        pending = c.opt(.pending)
    }
}

public struct ChatSendResult: Decodable, Sendable, Equatable {
    public var sent: Bool
    public var at: Int64

    public init(sent: Bool = true, at: Int64 = 0) { self.sent = sent; self.at = at }

    enum CodingKeys: String, CodingKey { case sent, at }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sent = c.val(.sent, false); at = c.val(.at, 0)
    }
}

// MARK: - stream

public enum ChatEvent: Sendable, Equatable {
    case ready(conversationId: String, cursor: String, state: String, pending: PendingPrompt?)
    case message(ChatMessage)
    case reset(conversationId: String, reason: String, cursor: String)
    case state(state: String, pending: PendingPrompt?)
    case ping
    case unsupported(reason: String)
    case unknown(name: String)

    /// Dado ilegivel (JSON quebrado) ou evento de nome desconhecido vira `.unknown`.
    public init(_ sse: SSEEvent) {
        struct Ready: Decodable {
            var conversationId: String?; var cursor: String?; var state: String?; var pending: PendingPrompt?
        }
        struct Reset: Decodable { var conversationId: String?; var reason: String?; var cursor: String? }
        struct StateEv: Decodable { var state: String?; var pending: PendingPrompt? }
        struct Unsupported: Decodable { var reason: String? }

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let data = Data(sse.data.utf8)
        switch sse.event {
        case "ping":
            self = .ping
        case "ready":
            guard let r = try? dec.decode(Ready.self, from: data) else { self = .unknown(name: sse.event); return }
            self = .ready(conversationId: r.conversationId ?? "", cursor: r.cursor ?? sse.id ?? "",
                          state: r.state ?? "idle", pending: r.pending)
        case "message":
            guard let m = try? dec.decode(ChatMessage.self, from: data), !m.id.isEmpty else {
                self = .unknown(name: sse.event); return
            }
            self = .message(m)
        case "reset":
            guard let r = try? dec.decode(Reset.self, from: data) else { self = .unknown(name: sse.event); return }
            self = .reset(conversationId: r.conversationId ?? "", reason: r.reason ?? "", cursor: r.cursor ?? "")
        case "state":
            guard let s = try? dec.decode(StateEv.self, from: data) else { self = .unknown(name: sse.event); return }
            self = .state(state: s.state ?? "idle", pending: s.pending)
        case "unsupported":
            let u = try? dec.decode(Unsupported.self, from: data)
            self = .unsupported(reason: u?.reason ?? "")
        default:
            self = .unknown(name: sse.event)
        }
    }
}

// MARK: - validacao do texto

/// Validacao do texto antes de enviar (espelha o servidor, §4.2). nil = ok; senao, a mensagem pt-BR.
public enum ChatText {
    public static let maxRunes = 4000

    public static func validate(_ text: String) -> String? {
        // CRLF e CR viram LF, como no servidor.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Escreva uma mensagem antes de enviar."
        }
        let scalars = normalized.unicodeScalars
        if scalars.count > maxRunes {
            return "Mensagem longa demais: no maximo \(maxRunes) caracteres."
        }
        for u in scalars {
            let v = u.value
            let c0 = v < 0x20 && v != 0x0A && v != 0x09
            let del = v == 0x7F
            let c1 = (0x80...0x9F).contains(v)
            if c0 || del || c1 { return "A mensagem tem caracteres de controle que nao podem ser enviados." }
        }
        return nil
    }
}
