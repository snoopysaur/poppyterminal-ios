import Foundation
import PoppyKit

/// Conexao WebSocket sip (tuios-web). Tudo roda no MainActor.
@MainActor
final class SipConnection: ObservableObject {
    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case reconnecting(Int)
        case tailscaleOff
        case denied
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    /// Chamado com a saida do terminal remoto (tipo 1).
    var onOutput: (@MainActor (ArraySlice<UInt8>) -> Void)?
    /// Chamado a cada socket novo, antes da 1a saida (limpa a tela local).
    var onSessionStart: (@MainActor () -> Void)?
    private var pendingSize: SipResize?
    private var resizeTask: Task<Void, Never>?

    private let policy = ReconnectPolicy()
    private let urlSession = URLSession(configuration: .default)

    private var endpoint: URL?
    private var authHeader: String?
    private var size: SipResize?
    private var wantRun = false
    private var runTask: Task<Void, Never>?
    private var wsTask: URLSessionWebSocketTask?
    private var outbox: AsyncStream<Data>.Continuation?
    private var attempt = 0
    private var hadConnected = false
    private var generation = 0

    // MARK: API

    /// Compatibilidade com o ContentView antigo (A1 remove na integracao).
    func start(endpoint: URL, user: String, password: String) {
        start(url: endpoint, authHeader: password.isEmpty ? nil : BasicAuth.header(user: user, password: password))
    }

    /// `url` vem de `ServerStore.terminalURL(session:window:)` (`/ws?...&mode=satellite&window=`).
    func start(url: URL, authHeader: String?) {
        stop()
        self.endpoint = url
        self.authHeader = authHeader
        wantRun = true
        attempt = 0
        hadConnected = false
        status = .connecting
        launchIfReady()
    }

    func stop() {
        wantRun = false
        generation += 1
        runTask?.cancel()
        runTask = nil
        teardownSocket()
        status = .idle
    }

    /// Troca a janela do celular: refaz o socket em outra URL (foco so local),
    /// mantendo o tamanho ja medido.
    func switchTo(url: URL) {
        endpoint = url
        hadConnected = true
        reconnectNow()
    }

    /// Reconecta ja (botao "tentar de novo" ou volta ao primeiro plano).
    func reconnectNow() {
        guard let endpoint else { return }
        let header = authHeader
        generation += 1
        runTask?.cancel()
        runTask = nil
        teardownSocket()
        self.endpoint = endpoint
        authHeader = header
        wantRun = true
        attempt = 0
        status = hadConnected ? .reconnecting(0) : .connecting
        launchIfReady()
    }

    /// Tamanho do terminal em celulas e pixels. O 1o valor dispara a conexao
    /// e vai como 1o quadro; os seguintes vao como quadros de resize.
    func updateSize(cols: Int, rows: Int, widthPx: Int, heightPx: Int) {
        guard cols > 0, rows > 0 else { return }
        let new = SipResize(cols: cols, rows: rows, widthPx: widthPx, heightPx: heightPx)
        guard new != (pendingSize ?? size) else { return }
        if size == nil {
            // 1o tamanho: sem espera, dispara a conexao.
            size = new
            pendingSize = nil
            launchIfReady()
            return
        }
        // Animacao do teclado gera varios layouts: so o ultimo tamanho
        // (estavel por 200 ms) vai ao servidor.
        pendingSize = new
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, let latest = self.pendingSize else { return }
            self.pendingSize = nil
            guard latest != self.size else { return }
            self.size = latest
            if let outbox = self.outbox, let frame = try? SipCodec.resize(latest) {
                outbox.yield(frame)
            }
        }
    }

    func sendInput(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, status == .connected || outbox != nil else { return }
        outbox?.yield(SipCodec.input(Data(bytes)))
    }

    // MARK: Laco de conexao

    private func launchIfReady() {
        guard wantRun, runTask == nil, size != nil, endpoint != nil else { return }
        generation += 1
        let gen = generation
        runTask = Task { [weak self] in
            await self?.loop(gen)
        }
    }

    private func teardownSocket() {
        outbox?.finish()
        outbox = nil
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
    }

    private func alive(_ gen: Int) -> Bool {
        wantRun && gen == generation && !Task.isCancelled
    }

    private func loop(_ gen: Int) async {
        while alive(gen) {
            let failure = await runOnce()
            guard alive(gen) else { return }
            teardownSocket()
            switch failure {
            case .denied:
                status = .denied
                wantRun = false
                runTask = nil
                return
            case .networkUnreachable where !hadConnected:
                status = .tailscaleOff
            default:
                status = .reconnecting(attempt)
            }
            let delay = policy.delay(forAttempt: attempt)
            attempt += 1
            try? await Task.sleep(for: .seconds(delay))
        }
        if gen == generation { runTask = nil }
    }

    /// Uma sessao de socket, da abertura ate cair. Devolve o motivo.
    private func runOnce() async -> ConnectionFailure {
        guard let endpoint, let size else { return .other }
        onSessionStart?()
        var request = URLRequest(url: endpoint)
        request.setValue("iPhone Mobile", forHTTPHeaderField: "User-Agent")
        if let authHeader {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        let task = urlSession.webSocketTask(with: request)
        task.maximumMessageSize = 4 * 1024 * 1024
        wsTask = task

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        outbox = continuation
        // 1o quadro: resize, para o servidor criar a janela do tamanho certo.
        if let first = try? SipCodec.resize(size) {
            continuation.yield(first)
        }
        task.resume()

        let writer = Task { [task] in
            for await frame in stream {
                do { try await task.send(.data(frame)) } catch { return }
            }
        }
        let pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { return }
                self?.outbox?.yield(SipCodec.ping())
            }
        }
        defer {
            writer.cancel()
            pinger.cancel()
        }

        do {
            while true {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .data(let d): data = d
                case .string(let s): data = Data(s.utf8)
                @unknown default: continue
                }
                if status != .connected {
                    status = .connected
                    attempt = 0
                    hadConnected = true
                }
                guard let frame = try? SipCodec.decode(data) else { continue }
                switch frame.type {
                case .output:
                    onOutput?(ArraySlice([UInt8](frame.payload)))
                case .ping:
                    outbox?.yield(SipCodec.pong())
                case .close:
                    return .other
                default:
                    break
                }
            }
        } catch {
            if Task.isCancelled { return .other }
            let code = (error as? URLError)?.code.rawValue ?? 0
            return ConnectionFailure.classify(urlErrorCode: code)
        }
    }
}
