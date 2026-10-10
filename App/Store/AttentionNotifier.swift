import UIKit
import UserNotifications
import PoppyKit

/// Avisos locais de "precisa de voce": haptic + notificacao local. Sem push.
/// Vale com o app aberto ou recem-fechado (o iOS segura o app por ~30 s em segundo
/// plano via `beginGrace`; depois disso o SSE cai e nao ha como avisar).
@MainActor
final class AttentionNotifier {
    /// A UI de Agentes pode desligar o haptic daqui se tocar o proprio `.sensoryFeedback`.
    var hapticEnabled = true

    private var graceID: UIBackgroundTaskIdentifier = .invalid
    private var authorizationAsked = false

    /// Pede permissao de notificacao uma vez (chamar quando o usuario ja conectou).
    func requestAuthorizationIfNeeded() async {
        guard !authorizationAsked else { return }
        authorizationAsked = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Itens novos que pedem a pessoa. `appIsActive`: com o app na frente so vibra
    /// (a UI mostra o banner); fora dele, notificacao local.
    func notify(newItems: [InboxItem], appIsActive: Bool) {
        let relevant = newItems.filter { $0.kind.needsYou }
        guard !relevant.isEmpty else { return }
        if hapticEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        guard !appIsActive else { return }
        for item in relevant.prefix(3) {
            let content = Self.content(for: item)
            let request = UNNotificationRequest(identifier: "attn-\(item.id)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { _ in }
        }
    }

    /// Item resolvido (aprovado/dispensado/sumiu): tira a notificacao da central.
    func clear(itemIDs: [String]) {
        guard !itemIDs.isEmpty else { return }
        let ids = itemIDs.map { "attn-\($0)" }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Segura o app vivo alguns segundos ao ir para segundo plano.
    func beginGrace(onExpire: @escaping @MainActor () -> Void) {
        endGrace()
        graceID = UIApplication.shared.beginBackgroundTask(withName: "poppy-attention") { [weak self] in
            Task { @MainActor in
                onExpire()
                self?.endGrace()
            }
        }
    }

    func endGrace() {
        guard graceID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(graceID)
        graceID = .invalid
    }

    /// Texto FIXO da notificacao local (aparece na tela bloqueada): nada do item entra nela (nem resumo,
    /// nem nome do agente, nem sessao, nem janela). So o id do item vai no `userInfo`, que a tela nao mostra.
    static let fixedTitle = "PoppyTerminal"
    static let fixedBody = "Poppy precisa de você"
    static let fixedThread = "poppy-attention"

    static func content(for item: InboxItem) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = fixedTitle
        content.body = fixedBody
        content.sound = .default
        content.threadIdentifier = fixedThread
        content.userInfo = ["inboxID": item.id]
        return content
    }
}
