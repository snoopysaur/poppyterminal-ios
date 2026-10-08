import Foundation

/// Evento SSE ja montado.
public struct SSEEvent: Sendable, Equatable {
    public var id: String?
    public var event: String
    public var data: String
    public var retry: Int?

    public init(id: String? = nil, event: String = "message", data: String = "", retry: Int? = nil) {
        self.id = id
        self.event = event
        self.data = data
        self.retry = retry
    }
}

/// Parser incremental de `text/event-stream` (WHATWG): aceita bytes em qualquer
/// fatia, fim de linha LF/CRLF/CR, `data:` multilinha, comentarios (`: ping`),
/// BOM inicial e campos desconhecidos. Evento sem `data` mas com `event:` (ex.: `gap`)
/// tambem e entregue.
public struct SSEParser: Sendable {
    private var buffer: [UInt8] = []
    private var sawCR = false
    private var started = false

    private var eventName: String?
    private var dataLines: [String] = []
    private var pendingID: String?
    private var pendingRetry: Int?
    /// Ultimo `id` visto (persiste entre eventos, como no padrao).
    public private(set) var lastEventID: String?

    public init() {}

    /// Alimenta com bytes novos; devolve os eventos completados.
    public mutating func feed(_ chunk: Data) -> [SSEEvent] {
        feed(bytes: [UInt8](chunk))
    }

    public mutating func feed(_ text: String) -> [SSEEvent] {
        feed(bytes: Array(text.utf8))
    }

    public mutating func feed(bytes: [UInt8]) -> [SSEEvent] {
        var out: [SSEEvent] = []
        for byte in bytes {
            if sawCR {
                sawCR = false
                if byte == 0x0A { continue } // CRLF: o LF ja foi tratado como fim de linha
            }
            switch byte {
            case 0x0D:
                sawCR = true
                endLine(&out)
            case 0x0A:
                endLine(&out)
            default:
                buffer.append(byte)
            }
        }
        return out
    }

    /// Fim do fluxo: descarta evento incompleto (padrao), mas entrega o que ja tem
    /// nome de evento (ex.: `event: gap` sem linha em branco final).
    public mutating func finish() -> [SSEEvent] {
        var out: [SSEEvent] = []
        if !buffer.isEmpty { endLine(&out) }
        if eventName != nil && dataLines.isEmpty { dispatch(&out) }
        reset()
        return out
    }

    private mutating func endLine(_ out: inout [SSEEvent]) {
        var line = buffer
        buffer.removeAll(keepingCapacity: true)
        if !started {
            started = true
            if line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) }
        }
        if line.isEmpty {
            dispatch(&out)
            return
        }
        if line[0] == 0x3A { return } // ':' comentario / keep-alive
        let name: String
        var value: String
        if let colon = line.firstIndex(of: 0x3A) {
            name = String(decoding: line[..<colon], as: UTF8.self)
            var rest = Array(line[(colon + 1)...])
            if rest.first == 0x20 { rest.removeFirst() }
            value = String(decoding: rest, as: UTF8.self)
        } else {
            name = String(decoding: line, as: UTF8.self)
            value = ""
        }
        switch name {
        case "event": eventName = value
        case "data": dataLines.append(value)
        case "id":
            if !value.contains("\u{0}") { pendingID = value; lastEventID = value }
        case "retry":
            if !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(value) {
                pendingRetry = n
            }
        default: break
        }
    }

    private mutating func dispatch(_ out: inout [SSEEvent]) {
        defer { reset() }
        // retry sozinho (sem data/event) nao gera evento.
        guard eventName != nil || !dataLines.isEmpty else { return }
        out.append(SSEEvent(
            id: pendingID ?? lastEventID,
            event: (eventName?.isEmpty == false) ? eventName! : "message",
            data: dataLines.joined(separator: "\n"),
            retry: pendingRetry
        ))
    }

    private mutating func reset() {
        eventName = nil
        dataLines = []
        pendingID = nil
        pendingRetry = nil
    }
}

/// Evento do servidor, decodificado de forma tolerante (campos extras sao ignorados).
public struct ServerEvent: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case ready, gap, attention, notification
        case agentState = "agent-state"
        case sessionCreated = "session-created"
        case sessionClosed = "session-closed"
        case windowCreated = "window-created"
        case windowClosed = "window-closed"
        case windowRetitled = "window-retitled"
        case windowFocused = "window-focused"
        case workspaceSwitched = "workspace-switched"
        case unknown
    }

    public var kind: Kind
    public var name: String
    public var seq: UInt64?
    public var bootID: String?
    public var session: String?
    public var window: String?
    public var state: String?
    public var action: String?
    public var attentionID: String?
    public var attentionKind: String?
    public var reason: String?
    public var replayed: Int?

    public init(_ sse: SSEEvent) {
        name = sse.event
        kind = Kind(rawValue: sse.event) ?? .unknown
        seq = sse.id.flatMap { UInt64($0) }
        let obj = (try? JSONSerialization.jsonObject(with: Data(sse.data.utf8))) as? [String: Any] ?? [:]
        if let n = ServerEvent.uint(obj["seq"]) { seq = n }
        bootID = obj["boot_id"] as? String
        session = obj["session"] as? String
        window = obj["window"] as? String
        state = obj["state"] as? String
        action = obj["action"] as? String
        reason = obj["reason"] as? String
        replayed = ServerEvent.uint(obj["replayed"]).map { Int($0) }
        if let a = obj["attention"] as? [String: Any] {
            attentionID = (a["id"] as? String) ?? ServerEvent.uint(a["id"]).map { String($0) }
            attentionKind = a["kind"] as? String
            if session == nil { session = a["session"] as? String }
        }
    }

    private static func uint(_ v: Any?) -> UInt64? {
        if let n = v as? UInt64 { return n }
        if let n = v as? Int { return n >= 0 ? UInt64(n) : nil }
        if let d = v as? Double { return d >= 0 ? UInt64(d) : nil }
        if let n = v as? NSNumber { return n.uint64Value }
        if let s = v as? String { return UInt64(s) }
        return nil
    }
}

/// Posicao de retomada do SSE (`after_seq` + `boot_id`) e regra de refetch.
public struct EventCursor: Sendable, Equatable {
    public private(set) var seq: UInt64?
    public private(set) var bootID: String?

    public enum Outcome: Sendable, Equatable {
        /// Evento normal (ou ignorado).
        case event
        /// `ready` recebido: conexao viva. `replayed` = eventos reenviados.
        case ready(replayed: Int)
        /// Lacuna (gap) ou daemon reiniciado: refaca os GETs.
        case refetch
    }

    public init(seq: UInt64? = nil, bootID: String? = nil) {
        self.seq = seq
        self.bootID = bootID
    }

    public mutating func reset() { seq = nil; bootID = nil }

    @discardableResult
    public mutating func apply(_ event: SSEEvent) -> Outcome {
        let ev = ServerEvent(event)
        switch ev.kind {
        case .ready:
            let newBoot = ev.bootID ?? ""
            if let old = bootID, !old.isEmpty, !newBoot.isEmpty, old != newBoot {
                // Daemon reiniciou: a numeracao recomeca.
                bootID = newBoot
                seq = ev.seq
                return .refetch
            }
            if !newBoot.isEmpty { bootID = newBoot }
            if let s = ev.seq, s > (seq ?? 0) { seq = s }
            return .ready(replayed: ev.replayed ?? 0)
        case .gap:
            return .refetch
        default:
            if let s = ev.seq, s > (seq ?? 0) { seq = s }
            return .event
        }
    }
}
