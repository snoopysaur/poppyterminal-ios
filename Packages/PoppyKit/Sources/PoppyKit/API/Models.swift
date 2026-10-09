import Foundation

// Modelos do contrato `/api/v1` (fixtures reais do servidor em
// Tests/PoppyKitTests/Fixtures/api). Decodificacao tolerante: campo ausente, null
// ou de tipo inesperado vira o valor neutro, nunca derruba a tela.

extension KeyedDecodingContainer {
    func list<T: Decodable>(_ key: Key) -> [T] {
        ((try? decodeIfPresent([T].self, forKey: key)) ?? nil) ?? []
    }
    func opt<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }
    func val<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: - info

public struct ServerInfo: Decodable, Sendable, Equatable {
    public var api: Int
    public var serverVersion: String
    public var defaultSession: String
    public var bootId: String
    public var daemonOk: Bool
    public var daemonVersion: String
    public var daemonError: String?
    public var missingVerbs: [String]
    /// true so com login Tailscale aceito: aprovar/responder/dispensar.
    public var humanActions: Bool
    /// Recursos do servidor (`chat`, `phone_view`). Ausente = servidor v0.2: `[]`.
    public var features: [String]

    public var supportsChat: Bool { features.contains("chat") }
    public var supportsPhoneView: Bool { features.contains("phone_view") }

    public init(api: Int = 1, serverVersion: String = "", defaultSession: String = "",
                bootId: String = "", daemonOk: Bool = true, daemonVersion: String = "",
                daemonError: String? = nil, missingVerbs: [String] = [], humanActions: Bool = true,
                features: [String] = []) {
        self.api = api; self.serverVersion = serverVersion; self.defaultSession = defaultSession
        self.bootId = bootId; self.daemonOk = daemonOk; self.daemonVersion = daemonVersion
        self.daemonError = daemonError; self.missingVerbs = missingVerbs; self.humanActions = humanActions
        self.features = features
    }

    enum CodingKeys: String, CodingKey {
        case api, serverVersion, defaultSession, bootId, daemonOk, daemonVersion, daemonError, missingVerbs, humanActions, features
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        api = c.val(.api, 1)
        serverVersion = c.val(.serverVersion, "")
        defaultSession = c.val(.defaultSession, "")
        bootId = c.val(.bootId, "")
        daemonOk = c.val(.daemonOk, true)
        daemonVersion = c.val(.daemonVersion, "")
        daemonError = c.opt(.daemonError)
        missingVerbs = c.list(.missingVerbs)
        humanActions = c.val(.humanActions, false)
        features = c.list(.features)
    }

    /// O daemon em execucao nao conhece verbos que o app usa.
    public var daemonTooOld: Bool { daemonOk && !missingVerbs.isEmpty }
}

// MARK: - sessoes

public struct AgentCounts: Decodable, Sendable, Equatable {
    public var working: Int
    public var needsInput: Int
    public var done: Int
    public var errored: Int
    public var idle: Int

    public init(working: Int = 0, needsInput: Int = 0, done: Int = 0, errored: Int = 0, idle: Int = 0) {
        self.working = working; self.needsInput = needsInput; self.done = done
        self.errored = errored; self.idle = idle
    }

    enum CodingKeys: String, CodingKey { case working, needsInput, done, errored, idle }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        working = c.val(.working, 0); needsInput = c.val(.needsInput, 0); done = c.val(.done, 0)
        errored = c.val(.errored, 0); idle = c.val(.idle, 0)
    }
}

public struct SessionSummary: Decodable, Sendable, Equatable, Identifiable {
    public var name: String
    /// Sessao em foco no PC (so informativo).
    public var current: Bool
    public var windows: Int
    public var agents: AgentCounts
    public var needsYou: Int

    public var id: String { name }

    public init(name: String, current: Bool = false, windows: Int = 0,
                agents: AgentCounts = AgentCounts(), needsYou: Int = 0) {
        self.name = name; self.current = current; self.windows = windows
        self.agents = agents; self.needsYou = needsYou
    }

    enum CodingKeys: String, CodingKey { case name, current, windows, agents, needsYou }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        current = c.val(.current, false)
        windows = c.val(.windows, 0)
        agents = c.val(.agents, AgentCounts())
        needsYou = c.val(.needsYou, 0)
    }
}

public struct SessionsResponse: Decodable, Sendable, Equatable {
    public var sessions: [SessionSummary]
    /// Verbos que falharam no daemon (dados parciais), ex.: `["list-agents"]`.
    public var warnings: [String]

    public init(sessions: [SessionSummary] = [], warnings: [String] = []) {
        self.sessions = sessions; self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey { case sessions, warnings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = c.list(.sessions)
        warnings = c.list(.warnings)
    }
}

public enum AgentState: String, Sendable, Equatable {
    case working, needsInput = "needs_input", done, errored, idle, unknown
}

public struct AgentInfo: Decodable, Sendable, Equatable {
    public var state: String
    public var harness: String
    public var needsYou: Bool
    public var blockedBy: String
    public var message: String

    public var stateKind: AgentState { AgentState(rawValue: state) ?? .unknown }

    public init(state: String = "idle", harness: String = "", needsYou: Bool = false,
                blockedBy: String = "", message: String = "") {
        self.state = state; self.harness = harness; self.needsYou = needsYou
        self.blockedBy = blockedBy; self.message = message
    }

    enum CodingKeys: String, CodingKey { case state, harness, needsYou, blockedBy, message }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = c.val(.state, "idle"); harness = c.val(.harness, "")
        needsYou = c.val(.needsYou, false); blockedBy = c.val(.blockedBy, "")
        message = c.val(.message, "")
    }
}

public struct WindowInfo: Decodable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var title: String
    /// Foco do PC (o celular tem foco proprio; nunca siga este valor).
    public var focused: Bool
    public var minimized: Bool
    public var host: String?
    public var runningCmdline: String?
    public var agent: AgentInfo?
    /// Tamanho do PTY do painel (0 = desconhecido ou janela remota).
    public var cols: Int
    public var rows: Int
    /// Janela com Claude Code e sessao valida: candidata ao chat (o `supported` real vem do GET chat).
    public var chat: Bool

    /// Nome para exibir: `name`, senao `title`, senao o id.
    public var displayName: String {
        if !name.isEmpty { return name }
        if !title.isEmpty { return title }
        return id
    }

    public init(id: String, name: String = "", title: String = "", focused: Bool = false,
                minimized: Bool = false, host: String? = nil, runningCmdline: String? = nil,
                agent: AgentInfo? = nil, cols: Int = 0, rows: Int = 0, chat: Bool = false) {
        self.id = id; self.name = name; self.title = title; self.focused = focused
        self.minimized = minimized; self.host = host; self.runningCmdline = runningCmdline
        self.agent = agent; self.cols = cols; self.rows = rows; self.chat = chat
    }

    enum CodingKeys: String, CodingKey {
        case id, name, title, focused, minimized, host, runningCmdline, agent, cols, rows, chat
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.val(.name, ""); title = c.val(.title, "")
        focused = c.val(.focused, false); minimized = c.val(.minimized, false)
        host = c.opt(.host); runningCmdline = c.opt(.runningCmdline); agent = c.opt(.agent)
        cols = c.val(.cols, 0); rows = c.val(.rows, 0); chat = c.val(.chat, false)
    }
}

public struct WorkspaceInfo: Decodable, Sendable, Equatable, Identifiable {
    public var n: Int
    public var name: String
    public var current: Bool
    public var windows: [WindowInfo]

    public var id: Int { n }
    public var displayName: String { name.isEmpty ? "Workspace \(n)" : name }

    public init(n: Int, name: String = "", current: Bool = false, windows: [WindowInfo] = []) {
        self.n = n; self.name = name; self.current = current; self.windows = windows
    }

    enum CodingKeys: String, CodingKey { case n, name, current, windows }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = c.val(.n, 0); name = c.val(.name, ""); current = c.val(.current, false)
        windows = c.list(.windows)
    }
}

public struct SessionDetail: Decodable, Sendable, Equatable, Identifiable {
    public var name: String
    public var currentWorkspace: Int
    public var workspaces: [WorkspaceInfo]
    public var warnings: [String]

    public var id: String { name }
    public var allWindows: [WindowInfo] { workspaces.flatMap(\.windows) }

    public func window(id: String) -> WindowInfo? { allWindows.first { $0.id == id } }

    /// Janela em foco no PC (referencia; o app nao muda isso).
    public var pcFocusedWindow: WindowInfo? { allWindows.first { $0.focused } }

    public init(name: String, currentWorkspace: Int = 1, workspaces: [WorkspaceInfo] = [],
                warnings: [String] = []) {
        self.name = name; self.currentWorkspace = currentWorkspace
        self.workspaces = workspaces; self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey { case name, currentWorkspace, workspaces, warnings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        currentWorkspace = c.val(.currentWorkspace, 1)
        workspaces = c.list(.workspaces)
        warnings = c.list(.warnings)
    }
}

public struct CreatedSession: Decodable, Sendable, Equatable {
    public var name: String
}

public struct CreatedWindow: Decodable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var workspace: Int

    enum CodingKeys: String, CodingKey { case id, name, workspace }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.val(.name, ""); workspace = c.val(.workspace, 0)
    }
}

// MARK: - inbox

public enum InboxKind: String, Sendable, Equatable {
    case approval, plan, ask, question, mail, errored, resume, finished, outbox, unknown

    /// Itens que bloqueiam um agente esperando a pessoa.
    public var needsYou: Bool {
        switch self {
        case .approval, .plan, .ask, .question, .errored: return true
        default: return false
        }
    }
}

public struct InboxItem: Decodable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kindRaw: String
    public var session: String
    public var window: String
    public var name: String
    public var harness: String
    public var summary: String
    public var options: [String]
    public var requestId: String?
    public var risk: [String]
    /// Nanossegundos desde a epoca Unix (como o servidor manda).
    public var since: Int64
    public var host: String?
    public var alwaysScope: [String]
    public var expires: Int64?
    public var planSha: String?
    public var planLines: [String]
    public var denyMessage: String?
    public var count: Int?
    public var workspace: Int?
    public var seq: UInt64?
    public var stale: Bool
    public var seenAt: Int64?
    /// O que o servidor v0.3.2 manda em `answerable`; `nil` = servidor antigo (campo ausente).
    public var answerableRaw: Bool?

    /// O app consegue responder este item? Servidor novo: vale o campo `answerable`. Servidor
    /// antigo: aprovacao/pergunta so e respondivel com `request_id` e opcoes (ha um hold);
    /// sem isso o item e so um aviso ("responda no terminal"). Plano e demais tipos: sim.
    public var answerable: Bool {
        if let answerableRaw { return answerableRaw }
        switch kind {
        case .approval, .ask, .question: return requestId != nil && !options.isEmpty
        default: return true
        }
    }

    public var kind: InboxKind { InboxKind(rawValue: kindRaw) ?? .unknown }
    public var sinceDate: Date { Date(timeIntervalSince1970: Double(since) / 1_000_000_000) }
    /// Aprovar com risco exige confirmacao explicita (`risk_ack`).
    public var hasRisk: Bool { !risk.isEmpty }

    public init(id: String, kind: String, session: String = "", window: String = "", name: String = "",
                harness: String = "", summary: String = "", options: [String] = [], requestId: String? = nil,
                risk: [String] = [], since: Int64 = 0, host: String? = nil, alwaysScope: [String] = [],
                expires: Int64? = nil, planSha: String? = nil, planLines: [String] = [],
                denyMessage: String? = nil, count: Int? = nil, workspace: Int? = nil, seq: UInt64? = nil,
                stale: Bool = false, seenAt: Int64? = nil, answerable: Bool? = nil) {
        self.answerableRaw = answerable
        self.id = id; self.kindRaw = kind; self.session = session; self.window = window
        self.name = name; self.harness = harness; self.summary = summary; self.options = options
        self.requestId = requestId; self.risk = risk; self.since = since; self.host = host
        self.alwaysScope = alwaysScope; self.expires = expires; self.planSha = planSha
        self.planLines = planLines; self.denyMessage = denyMessage; self.count = count
        self.workspace = workspace; self.seq = seq; self.stale = stale; self.seenAt = seenAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, session, window, name, harness, summary, options, requestId, risk, since, host
        case alwaysScope, expires, planSha, planLines, denyMessage, count, workspace, seq, stale, seenAt
        case answerableRaw = "answerable"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else {
            id = String(try c.decode(Int.self, forKey: .id))
        }
        kindRaw = c.val(.kind, "")
        session = c.val(.session, ""); window = c.val(.window, "")
        name = c.val(.name, ""); harness = c.val(.harness, ""); summary = c.val(.summary, "")
        options = c.list(.options)
        requestId = c.opt(.requestId)
        risk = c.list(.risk)
        since = c.val(.since, 0)
        host = c.opt(.host)
        alwaysScope = c.list(.alwaysScope)
        expires = c.opt(.expires)
        planSha = c.opt(.planSha)
        planLines = c.list(.planLines)
        denyMessage = c.opt(.denyMessage)
        count = c.opt(.count); workspace = c.opt(.workspace); seq = c.opt(.seq)
        stale = c.val(.stale, false); seenAt = c.opt(.seenAt)
        answerableRaw = c.opt(.answerableRaw)
    }
}

public struct InboxResponse: Decodable, Sendable, Equatable {
    public var items: [InboxItem]
    public var counts: [String: Int]
    public var seq: UInt64
    public var bootId: String

    public init(items: [InboxItem] = [], counts: [String: Int] = [:], seq: UInt64 = 0, bootId: String = "") {
        self.items = items; self.counts = counts; self.seq = seq; self.bootId = bootId
    }

    enum CodingKeys: String, CodingKey { case items, counts, seq, bootId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = c.list(.items)
        counts = c.val(.counts, [:])
        seq = c.val(.seq, 0)
        bootId = c.val(.bootId, "")
    }
}

public struct PromptOption: Decodable, Sendable, Equatable, Identifiable {
    public var n: Int
    public var label: String
    public var id: Int { n }
}

/// `GET /inbox/{id}/prompt`. Para `ask` o servidor sintetiza (answerable=false);
/// para os demais vem do peek-prompt.
public struct PromptInfo: Decodable, Sendable, Equatable {
    public var promptId: String
    public var kind: String
    public var message: String
    public var lines: [String]
    public var options: [PromptOption]
    /// `approve`, `approve_always`, `deny`, ...
    public var actions: [String]
    public var found: Bool
    public var answerable: Bool
    public var reason: String?
    public var waitingMs: Int?
    public var requestId: String?
    public var blocked: Bool
    public var state: String?
    public var harness: String?
    public var session: String?
    public var window: String?

    enum CodingKeys: String, CodingKey {
        case promptId, kind, message, lines, options, actions, found, answerable, reason
        case waitingMs, requestId, blocked, state, harness, session, window
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        promptId = c.val(.promptId, ""); kind = c.val(.kind, ""); message = c.val(.message, "")
        lines = c.list(.lines); options = c.list(.options); actions = c.list(.actions)
        found = c.val(.found, false); answerable = c.val(.answerable, false)
        reason = c.opt(.reason); waitingMs = c.opt(.waitingMs); requestId = c.opt(.requestId)
        blocked = c.val(.blocked, false); state = c.opt(.state); harness = c.opt(.harness)
        session = c.opt(.session); window = c.opt(.window)
    }
}

// MARK: - acoes de pessoa

public enum ReplyDecision: String, Codable, Sendable {
    case once, always, deny, ask
}

public struct ReplyRequest: Encodable, Sendable, Equatable {
    public var decision: ReplyDecision
    public var message: String?
    public var riskAck: [String]?
    /// Linha que a pessoa viu (o app preenche).
    public var summary: String?
    /// Obrigatorio em itens `plan`.
    public var planSha: String?

    public init(decision: ReplyDecision, message: String? = nil, riskAck: [String]? = nil,
                summary: String? = nil, planSha: String? = nil) {
        self.decision = decision; self.message = message; self.riskAck = riskAck
        self.summary = summary; self.planSha = planSha
    }
}

public struct ReplyResult: Decodable, Sendable, Equatable {
    public var applied: Bool
    public var decision: String?
    public var reason: String?
    public var requestId: String?

    enum CodingKeys: String, CodingKey { case applied, decision, reason, requestId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        applied = c.val(.applied, false); decision = c.opt(.decision)
        reason = c.opt(.reason); requestId = c.opt(.requestId)
    }
}

public struct AnswerResult: Decodable, Sendable, Equatable {
    public var applied: Bool
    public var answer: String?
    public var reason: String?
    public var requestId: String?

    enum CodingKeys: String, CodingKey { case applied, answer, reason, requestId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        applied = c.val(.applied, false); answer = c.opt(.answer)
        reason = c.opt(.reason); requestId = c.opt(.requestId)
    }
}

public struct RespondRequest: Encodable, Sendable, Equatable {
    public var action: String
    public var value: String?
    public var promptId: String
    public var riskAck: [String]?

    public init(action: String, value: String? = nil, promptId: String, riskAck: [String]? = nil) {
        self.action = action; self.value = value; self.promptId = promptId; self.riskAck = riskAck
    }
}

public struct RespondResult: Decodable, Sendable, Equatable {
    public var settledBy: String?
    public var state: String?
    public var sent: String?
    public var message: String?
    public var promptId: String?

    enum CodingKeys: String, CodingKey { case settledBy, state, sent, message, promptId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settledBy = c.opt(.settledBy); state = c.opt(.state); sent = c.opt(.sent)
        message = c.opt(.message); promptId = c.opt(.promptId)
    }
}

public struct DismissResult: Decodable, Sendable, Equatable {
    public var dismissed: Bool
}

// MARK: - erros

/// Erro tipado do app. Respostas do servidor: `{"error":{"code","message"}}`.
public enum APIError: Error, Equatable, Sendable {
    /// `reason`: motivo do `hold_ended` (`disabled`, `timeout`, `answered`, `gone`); `nil` nos demais.
    case api(status: Int, code: String, message: String, retryAfter: Double?, reason: String? = nil)
    case network(ConnectionFailure)
    case invalidResponse
    case decoding(String)
    case invalidArgument(String)
    case unsupported

    public enum Kind: Sendable, Equatable {
        case daemonTooOld, daemonUnreachable
        case needsAttach, promptChanged, sessionExists, remoteItem
        case humanRequiresTailscale, rateLimited, itemNotFound, sessionNotFound
        case clientHeaderRequired, invalidParams
        case pendingPrompt, cursorStale, tooManyStreams, remoteWindow, notChat, agentGone
        case holdEnded
        case accessDenied
        case networkUnreachable
        case other
    }

    public var kind: Kind {
        switch self {
        case let .api(status, code, _, _, _):
            switch code {
            case "daemon_too_old": return .daemonTooOld
            case "daemon_unreachable": return .daemonUnreachable
            case "needs_attach": return .needsAttach
            case "prompt_changed": return .promptChanged
            case "hold_ended": return .holdEnded
            case "session_exists": return .sessionExists
            case "remote_item": return .remoteItem
            case "human_requires_tailscale": return .humanRequiresTailscale
            case "rate_limited": return .rateLimited
            case "item_not_found": return .itemNotFound
            case "session_not_found": return .sessionNotFound
            case "client_header_required": return .clientHeaderRequired
            case "invalid_params": return .invalidParams
            case "pending_prompt": return .pendingPrompt
            case "cursor_stale": return .cursorStale
            case "too_many_streams": return .tooManyStreams
            case "remote_window": return .remoteWindow
            case "not_chat": return .notChat
            case "agent_gone": return .agentGone
            default:
                if status == 401 || status == 403 { return .accessDenied }
                return .other
            }
        case let .network(f):
            switch f {
            case .networkUnreachable: return .networkUnreachable
            case .denied: return .accessDenied
            case .other: return .other
            }
        default: return .other
        }
    }

    public var code: String? {
        if case let .api(_, code, _, _, _) = self { return code }
        return nil
    }

    public var retryAfter: Double? {
        if case let .api(_, _, _, r, _) = self { return r }
        return nil
    }

    /// Motivo do fim do hold (`hold_ended`).
    public enum HoldEndedReason: Sendable, Equatable {
        case disabled, timeout, answered, gone, unknown
    }

    /// Campo `reason` do erro (so `hold_ended` traz).
    public var reasonRaw: String? {
        if case let .api(_, _, _, _, reason) = self { return reason }
        return nil
    }

    public var holdEndedReason: HoldEndedReason {
        switch reasonRaw {
        case "disabled": return .disabled
        case "timeout": return .timeout
        case "answered": return .answered
        case "gone": return .gone
        default: return .unknown
        }
    }

    /// Como `userMessage`, mas um `pending_prompt` sem cartao respondivel nao manda "responder
    /// pelo cartao": diz que o app nao enxerga o que o Claude espera.
    public func pendingMessage(answerable pendingAnswerable: Bool) -> String {
        if kind == .pendingPrompt, !pendingAnswerable {
            return "O Claude espera algo que o app não consegue responder. Atualize ou responda no terminal."
        }
        return userMessage
    }

    /// Mensagem curta para a pessoa (pt-BR).
    public var userMessage: String {
        switch kind {
        case .daemonTooOld: return "O daemon do PC e antigo demais para este app."
        case .daemonUnreachable: return "O servidor nao conseguiu falar com o daemon do PC."
        case .needsAttach: return "O servidor ainda nao tem o anexo de controle (rode o tuios-web fora do TUIOS)."
        case .promptChanged: return "O pedido mudou. Confira de novo."
        case .holdEnded:
            // "Expirou" so quando o motivo e mesmo o prazo; os outros motivos dizem a verdade.
            switch holdEndedReason {
            case .disabled: return "Este pedido não pode ser respondido pelo app. Responda no terminal."
            case .timeout: return "O pedido expirou. Responda no terminal."
            case .answered: return "Este pedido já foi respondido."
            case .gone: return "O pedido não existe mais: o Claude seguiu em frente."
            case .unknown: return "A espera acabou, responda pelo terminal."
            }
        case .sessionExists: return "Ja existe uma sessao com esse nome."
        case .remoteItem: return "Este item e de outra maquina e nao pode ser respondido aqui."
        case .humanRequiresTailscale: return "Aprovar e responder so valem entrando pelo endereco Tailscale."
        case .rateLimited: return "Calma: no maximo 1 acao por segundo."
        case .itemNotFound: return "O item nao esta mais na caixa de entrada."
        case .sessionNotFound: return "Sessao nao encontrada."
        case .clientHeaderRequired, .invalidParams, .other:
            if case let .api(_, _, message, _, _) = self, !message.isEmpty { return message }
            return "Algo deu errado."
        case .pendingPrompt: return "Responda o pedido pendente antes de enviar."
        case .cursorStale: return "A conversa mudou. Recarregando."
        case .tooManyStreams: return "Chats abertos demais no servidor. Tente de novo em instantes."
        case .remoteWindow: return "Esta janela e de outra maquina; abra o terminal."
        case .notChat: return "Esta janela nao tem o Claude Code."
        case .agentGone: return "O Claude saiu desta janela."
        case .accessDenied: return "Acesso negado pelo servidor."
        case .networkUnreachable: return "Sem rede. O Tailscale esta ligado?"
        }
    }

    /// Converte erros do Foundation (URLError) em `APIError`.
    public static func from(_ error: Error) -> APIError {
        if let e = error as? APIError { return e }
        if let u = error as? URLError {
            return .network(ConnectionFailure.classify(urlErrorCode: u.errorCode))
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return .network(ConnectionFailure.classify(urlErrorCode: ns.code))
        }
        return .decoding(String(describing: error))
    }

    /// Monta o erro a partir de status + corpo (JSON do servidor, se houver).
    public static func parse(status: Int, body: Data, retryAfter: Double?) -> APIError {
        struct Envelope: Decodable {
            struct Inner: Decodable { var code: String?; var message: String?; var reason: String? }
            var error: Inner?
            var reason: String?
        }
        if let env = try? JSONDecoder().decode(Envelope.self, from: body), let inner = env.error {
            // `reason` vem dentro de `error` (contrato v0.3.2); aceita tambem no topo do corpo.
            let reason = [inner.reason, env.reason].compactMap { $0 }.first { !$0.isEmpty }
            return .api(status: status, code: inner.code ?? "unknown", message: inner.message ?? "",
                        retryAfter: retryAfter, reason: reason)
        }
        let code: String
        switch status {
        case 401: code = "unauthorized"
        case 403: code = "forbidden"
        default: code = "http_\(status)"
        }
        return .api(status: status, code: code, message: "", retryAfter: retryAfter)
    }
}

// MARK: - estado de conexao

/// Estado que a UI mostra (Poppy na tela de conexao).
public enum ConnectionState: Sendable, Equatable {
    case unconfigured
    case connecting
    case online
    case tailscaleOff
    case accessDenied
    case daemonOld(missing: [String])
    case daemonDown
    case failed(String)

    public var isOnline: Bool { self == .online }

    /// Estado correspondente a uma falha de rede/servidor.
    public static func from(_ error: APIError) -> ConnectionState {
        switch error.kind {
        case .networkUnreachable: return .tailscaleOff
        case .accessDenied: return .accessDenied
        case .daemonTooOld: return .daemonOld(missing: [])
        case .daemonUnreachable: return .daemonDown
        default: return .failed(error.userMessage)
        }
    }

    /// Estado a partir do `/info` (daemon antigo / fora do ar), ou `.online`.
    public static func from(_ info: ServerInfo) -> ConnectionState {
        if !info.daemonOk { return .daemonDown }
        if info.daemonTooOld { return .daemonOld(missing: info.missingVerbs) }
        return .online
    }
}
