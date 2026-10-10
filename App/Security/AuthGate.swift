import Foundation
import LocalAuthentication
import Observation
import SwiftUI
import PoppyKit

// MARK: - configuracao (um lugar so)

/// Regras do Face ID da v0.4. Tudo que o Gobby pode querer trocar fica aqui.
enum AuthConfig {
    /// RESERVA DO FACE ID (decisao 6 do plano; padrao ate o Gobby decidir):
    /// `.deviceOwnerAuthentication` = Face ID e, se falhar (capacete, mascara), a SENHA do iPhone.
    /// Para exigir SO biometria, troque por `.deviceOwnerAuthenticationWithBiometrics`
    /// (sem biometria cadastrada, as ordens ficam bloqueadas com aviso).
    static let policy: LAPolicy = .deviceOwnerAuthentication

    /// Uma autenticacao vale por 30 s para acoes de risco baixo (nao reabrir).
    static let graceSeconds: TimeInterval = 30
    /// Depois de tanto tempo em segundo plano, o app abre travado de novo.
    static let relockAfterBackgroundSeconds: TimeInterval = 300
}

// MARK: - autenticador (costura para teste)

enum AuthOutcome: Equatable, Sendable {
    case success
    /// A pessoa cancelou (ou o sistema interrompeu).
    case cancelled
    /// Biometria/senha recusadas.
    case failed
    /// Sem biometria nem senha configuradas no aparelho.
    case unavailable
}

protocol Authenticating: Sendable {
    func authenticate(reason: String) async -> AuthOutcome
}

/// Implementacao real, em cima do `LAContext`.
struct LocalAuthenticator: Authenticating {
    func authenticate(reason: String) async -> AuthOutcome {
        let context = LAContext()
        var probe: NSError?
        guard context.canEvaluatePolicy(AuthConfig.policy, error: &probe) else {
            if let raw = probe?.code, let code = LAError.Code(rawValue: raw),
               code == .userCancel || code == .appCancel || code == .systemCancel {
                return .cancelled
            }
            return .unavailable
        }
        do {
            let ok = try await context.evaluatePolicy(AuthConfig.policy, localizedReason: reason)
            return ok ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled: return .unavailable
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}

// MARK: - o portao

/// Face ID num ponto so: toda ordem (aprovar, responder, enviar no chat) passa por `authorize`.
///
/// - Graca de 30 s para risco baixo; risco alto (`InboxItem.hasRisk`) pede sempre.
/// - A graca zera quando o app vai para segundo plano; apos 5 min la, o app abre travado.
/// - Negar/Interromper NAO passam por aqui (nao pedem Face ID).
/// - Sem biometria nem senha: o app abre so para leitura e as ordens falham com `.unavailable`.
@MainActor
@Observable
final class AuthGate {
    enum Failure: Error, Equatable, LocalizedError {
        case denied, cancelled, unavailable

        var errorDescription: String? {
            switch self {
            case .denied: "Não foi possível confirmar que é você. Nada foi enviado."
            case .cancelled: "Confirmação cancelada. Nada foi enviado."
            case .unavailable: "Configure Face ID ou uma senha no iPhone para enviar ordens pelo app. Nada foi enviado."
            }
        }
    }

    /// Erro mostrado pela UI (mesmo caminho dos erros de acao). `userMessage` devolve o texto em pt-BR.
    static func apiError(for error: Error) -> APIError {
        let text = (error as? LocalizedError)?.errorDescription ?? "Confirmação necessária. Nada foi enviado."
        return .api(status: 0, code: "face_id_required", message: text, retryAfter: nil)
    }

    /// Motivo mostrado ao desbloquear (o stub de teste `unlock-only` reconhece este texto).
    nonisolated static let unlockReason = "Abrir o PoppyTerminal"

    private(set) var isLocked: Bool
    /// O aparelho nao tem Face ID nem senha: as ordens ficam bloqueadas (a UI mostra o aviso).
    private(set) var ordersBlocked = false

    @ObservationIgnored private let authenticator: any Authenticating
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var lastAuthAt: Date?
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var inFlight: Task<AuthOutcome, Never>?

    init(authenticator: any Authenticating, now: @escaping @Sendable () -> Date = { Date() }, startLocked: Bool = true) {
        self.authenticator = authenticator
        self.now = now
        self.isLocked = startLocked
    }

    /// Autenticador de producao; em DEBUG, o stub de teste so entra com o argumento `-auth-stub`.
    static func live() -> AuthGate {
        #if DEBUG
        if let stub = StubAuthenticator.fromLaunchArguments() { return AuthGate(authenticator: stub) }
        #endif
        return AuthGate(authenticator: LocalAuthenticator())
    }

    // MARK: ordens

    /// Chame ANTES de mandar uma ordem. Lanca `Failure` se nao puder prosseguir.
    func authorize(highRisk: Bool, reason: String = "Confirmar a ordem para o agente") async throws {
        if !highRisk, graceIsValid { return }
        switch await evaluate(reason: reason) {
        case .success:
            lastAuthAt = now()
            ordersBlocked = false
        case .cancelled:
            throw Failure.cancelled
        case .failed:
            throw Failure.denied
        case .unavailable:
            ordersBlocked = true
            throw Failure.unavailable
        }
    }

    private var graceIsValid: Bool {
        guard let at = lastAuthAt else { return false }
        let elapsed = now().timeIntervalSince(at)
        return elapsed >= 0 && elapsed < AuthConfig.graceSeconds
    }

    // MARK: trava ao abrir

    /// Tela de trava: autentica e, se der certo, libera. Sem biometria nem senha, libera so a leitura.
    @discardableResult
    func unlock() async -> AuthOutcome {
        let outcome = await evaluate(reason: Self.unlockReason)
        switch outcome {
        case .success:
            lastAuthAt = now()
            ordersBlocked = false
            isLocked = false
        case .unavailable:
            ordersBlocked = true
            isLocked = false
        case .cancelled, .failed:
            break
        }
        return outcome
    }

    func lock() {
        isLocked = true
        lastAuthAt = nil
    }

    /// Ligar ao `scenePhase`: segundo plano zera a graca; voltar apos 5 min ou mais trava o app.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            lastAuthAt = nil
            if backgroundedAt == nil { backgroundedAt = now() }
        case .active:
            if let since = backgroundedAt {
                let elapsed = now().timeIntervalSince(since)
                if elapsed < 0 || elapsed >= AuthConfig.relockAfterBackgroundSeconds { lock() }
            }
            backgroundedAt = nil
        default:
            break
        }
    }

    // MARK: interno

    /// Uma avaliacao por vez: toques repetidos esperam a mesma resposta do sistema.
    private func evaluate(reason: String) async -> AuthOutcome {
        if let running = inFlight { return await running.value }
        let auth = authenticator
        let task = Task { await auth.authenticate(reason: reason) }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        return outcome
    }
}

// MARK: - stub de teste (somente DEBUG)

#if DEBUG
/// STUB DE TESTE: existe so em builds Debug. O Release (IPA) nao pode conter este codigo nem esta
/// marca; a S10 confere com grep_ipa: POPPY_AUTH_STUB_DEBUG_ONLY
struct StubAuthenticator: Authenticating {
    static let marker = "POPPY_AUTH_STUB_DEBUG_ONLY"
    static let launchArgument = "-auth-stub"

    /// `unlock-only`: aceita so o desbloqueio ao abrir e recusa toda ordem (para testar o bloqueio).
    enum Mode: String, Sendable { case allow, deny, unavailable, unlockOnly = "unlock-only" }
    let mode: Mode

    func authenticate(reason: String) async -> AuthOutcome {
        switch mode {
        case .allow: return .success
        case .deny: return .failed
        case .unavailable: return .unavailable
        case .unlockOnly: return reason == AuthGate.unlockReason ? .success : .failed
        }
    }

    /// `-auth-stub allow|deny|unavailable|unlock-only`. Ausente: nil (usa o autenticador real).
    static func fromLaunchArguments(_ args: [String] = ProcessInfo.processInfo.arguments) -> StubAuthenticator? {
        guard let i = args.firstIndex(of: launchArgument), args.indices.contains(i + 1),
              let mode = Mode(rawValue: args[i + 1]) else { return nil }
        return StubAuthenticator(mode: mode)
    }
}
#endif
