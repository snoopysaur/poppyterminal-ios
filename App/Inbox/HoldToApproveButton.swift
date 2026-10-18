import SwiftUI
import UIKit

/// Tecnologia assistiva ligada? Com VoiceOver, Controle por Botao ou AssistiveTouch a pessoa nao
/// consegue segurar o dedo: o botao de aprovar vira um toque que pede confirmacao (e Face ID).
enum AssistiveAccess {
    static var isActive: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-assistive-stub") { return true }
        #endif
        return UIAccessibility.isVoiceOverRunning
            || UIAccessibility.isSwitchControlRunning
            || UIAccessibility.isAssistiveTouchRunning
    }
}

/// Agrupa o que o botao de segurar precisa (usado pela sheet e pelo catalogo).
struct HoldConfig {
    /// Muda quando o pedido ou o risco mudam: o botao recomeca do zero.
    var token: String
    /// A pessoa segurou 0,8 s.
    var onComplete: () -> Void
    /// Alternativa de acessibilidade: abre a confirmacao explicita, sem segurar.
    var onAssistive: () -> Void
}

/// "Segurar para aprovar": pedido com risco so e aprovado depois de 0,8 s com o dedo no botao.
/// Mostra o progresso enchendo o botao, da um retorno tatil ao comecar e ao concluir, e reinicia se
/// a pessoa solta antes. Quem usa VoiceOver ou Controle por Botao ativa o botao normalmente e cai na
/// confirmacao explicita (mesmo caminho de antes). Rotulo em letra de pixel (volta para SF em AX).
struct HoldToApproveButton: View {
    let token: String
    var title: LocalizedStringKey = "Segurar para aprovar"
    let onHoldComplete: () -> Void
    let onAssistiveApprove: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var pressStart: Date?
    @State private var armedToken: String?
    @State private var pressTick = 0
    @State private var completedTick = 0
    @State private var shortTapTick = 0

    init(token: String, title: LocalizedStringKey = "Segurar para aprovar",
         onHoldComplete: @escaping () -> Void, onAssistiveApprove: @escaping () -> Void) {
        self.token = token
        self.title = title
        self.onHoldComplete = onHoldComplete
        self.onAssistiveApprove = onAssistiveApprove
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: pressStart == nil)) { context in
            content(progress: progress(at: context.date))
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: Motion.holdToApproveSeconds, maximumDistance: 40) {
            complete()
        } onPressingChanged: { pressing in
            pressChanged(pressing)
        }
        .onTapGesture {
            // Toque curto: nao aprova. Com tecnologia assistiva, o toque e a ativacao do botao.
            if AssistiveAccess.isActive {
                onAssistiveApprove()
            } else {
                shortTapTick += 1
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: pressTick)
        .sensoryFeedback(.success, trigger: completedTick)
        .sensoryFeedback(.warning, trigger: shortTapTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Aprovar uma vez"))
        .accessibilityHint(Text("Abre a confirmação. Não precisa segurar."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onAssistiveApprove() }
        .accessibilityIdentifier("inbox-uma-vez")
    }

    private func progress(at date: Date) -> Double {
        #if DEBUG
        if let fixed = Self.debugProgress { return fixed }
        #endif
        guard let start = pressStart else { return 0 }
        return HoldPolicy.progress(elapsed: date.timeIntervalSince(start))
    }

    private func content(progress: Double) -> some View {
        Text(title)
            .guildText(.button)
            .foregroundStyle(isEnabled ? Theme.Palette.onAccent : Theme.Palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: PoppyActionStyle.thumbHeight)
            .padding(.horizontal, 16)
            .background {
                ZStack(alignment: .leading) {
                    GuildFrameBackground(kind: isEnabled ? .button : .neutralButton, pressed: pressStart != nil)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.Palette.sunken.opacity(0.45))
                            .frame(width: max(0, geo.size.width - 8) * progress)
                            .padding(4)
                    }
                    .allowsHitTesting(false)
                }
            }
    }

    private func pressChanged(_ pressing: Bool) {
        if pressing {
            pressStart = Date()
            armedToken = token
            pressTick += 1
        } else {
            pressStart = nil
        }
    }

    private func complete() {
        // Se o pedido ou o risco mudaram durante o gesto, nada e enviado.
        guard armedToken == token else {
            pressStart = nil
            return
        }
        pressStart = nil
        armedToken = nil
        completedTick += 1
        onHoldComplete()
    }

    #if DEBUG
    /// `-fixture-hold-meio`: congela o progresso em 50% (so para a captura de tela).
    private static var debugProgress: Double? {
        ProcessInfo.processInfo.arguments.contains("-fixture-hold-meio") ? 0.5 : nil
    }
    #endif
}
