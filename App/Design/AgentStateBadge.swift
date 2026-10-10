import SwiftUI

/// Selo redondo com o simbolo do estado (e contador opcional). Para linhas de lista e abas.
/// `haptics: true` dispara o haptic do estado (warning/error/success) quando o estado MUDA
/// para ele. Deixe `false` em linhas de lista que so sao carregadas.
struct AgentStateBadge: View {
    let tone: AgentTone
    var count: Int?
    var haptics: Bool

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ tone: AgentTone, count: Int? = nil, haptics: Bool = false) {
        self.tone = tone
        self.count = count
        self.haptics = haptics
    }

    var body: some View {
        Image(systemName: tone.symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(tone.color)
            .symbolEffect(.pulse, isActive: tone == .working && !reduceMotion)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(tone.color.opacity(0.18)))
            .overlay(alignment: .topTrailing) { countBubble }
            .sensoryFeedback(trigger: tone) { _, new in haptics ? new.feedback : nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var countBubble: some View {
        if let count, count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.onAccent)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(tone.color))
                .offset(x: 6, y: -6)
        }
    }

    private var accessibilityText: String {
        guard let count, count > 0 else { return tone.labelText }
        return tone.labelText(count: count)
    }
}

#Preview("AgentStateBadge") {
    HStack(spacing: 20) {
        ForEach(AgentTone.allCases) { AgentStateBadge($0, count: $0 == .needsYou ? 3 : nil) }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.Palette.base)
    .preferredColorScheme(.dark)
}
