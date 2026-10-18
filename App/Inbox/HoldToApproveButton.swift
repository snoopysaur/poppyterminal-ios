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

/// "Aprovar" + "segure 0,8 s": pedido com risco so e aprovado depois de 0,8 s com o dedo no botao.
/// Mostra o progresso enchendo o botao, da um retorno tatil ao comecar e ao concluir, e reinicia se
/// a pessoa solta antes. Quem usa VoiceOver ou Controle por Botao ativa o botao normalmente e cai na
/// confirmacao explicita (mesmo caminho de antes). Rotulo em letra de pixel (volta para SF em AX).
struct HoldToApproveButton: View {
    let token: String
    var title: LocalizedStringKey = "Aprovar"
    let onHoldComplete: () -> Void
    let onAssistiveApprove: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressStart: Date?
    @State private var armedToken: String?
    @State private var pressTick = 0
    @State private var completedTick = 0
    @State private var shortTapTick = 0
    /// Soltou antes de 0,8 s: a segunda linha do botao lembra "segure até encher" por um instante.
    @State private var showReleaseHint = false

    init(token: String, title: LocalizedStringKey = "Aprovar",
         onHoldComplete: @escaping () -> Void, onAssistiveApprove: @escaping () -> Void) {
        self.token = token
        self.title = title
        self.onHoldComplete = onHoldComplete
        self.onAssistiveApprove = onAssistiveApprove
    }

    var body: some View {
        Group {
            if reduceMotion {
                // Reduzir Movimento: sem animacao continua. O botao so muda de estado ao apertar
                // ("Segurando..."); o tempo de 0,8 s e o retorno tatil continuam iguais.
                content(progress: pressStart == nil ? 0 : 1, steady: true)
            } else {
                TimelineView(.animation(minimumInterval: nil, paused: pressStart == nil)) { context in
                    content(progress: progress(at: context.date), steady: false)
                }
            }
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
                flashReleaseHint()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: pressTick)
        .sensoryFeedback(.success, trigger: completedTick)
        .sensoryFeedback(.warning, trigger: shortTapTick)
        .accessibilityElement(children: .ignore)
        // Mesmo texto que esta escrito no botao ("Aprovar"): o Controle de Voz diz "toque em Aprovar".
        .accessibilityLabel(Text("Aprovar"))
        .accessibilityHint(Text("Segure por 0,8 segundo. Com VoiceOver, toque duas vezes para abrir a confirmação; não precisa segurar."))
        .accessibilityValue(Text(showReleaseHint ? "Segure até encher" : ""))
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

    /// Segunda linha do botao (SF pequeno, nunca em pixel): diz o que fazer, sem parenteses.
    private func hintLine(steady: Bool) -> LocalizedStringKey {
        if pressStart != nil { return steady ? "Segurando…" : "Segure até encher" }
        return showReleaseHint ? "Segure até encher" : "segure 0,8 s"
    }

    private func content(progress: Double, steady: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .guildText(.button)
            Text(hintLine(steady: steady))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(isEnabled ? Theme.Palette.onAccent : Theme.Palette.textSecondary)
        .multilineTextAlignment(.center)
        // Altura ideal do texto (nunca espremida pelo rodape): o botao cresce em vez de o texto vazar.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: PoppyActionStyle.thumbHeight)
        .padding(.horizontal, 12)
        .background {
            ZStack(alignment: .leading) {
                GuildFrameBackground(kind: isEnabled ? .button : .neutralButton, pressed: pressStart != nil)
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.Palette.sunken.opacity(steady ? 0.25 : 0.45))
                        .frame(width: max(0, geo.size.width - 8) * progress)
                        .padding(4)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func flashReleaseHint() {
        showReleaseHint = true
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            showReleaseHint = false
        }
    }

    private func pressChanged(_ pressing: Bool) {
        if pressing {
            pressStart = Date()
            armedToken = token
            pressTick += 1
        } else {
            // Soltou antes de encher: lembra o que fazer (sem aprovar nada).
            if let start = pressStart, Date().timeIntervalSince(start) < Motion.holdToApproveSeconds {
                flashReleaseHint()
            }
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
