import SwiftUI

/// Humores da Poppy. Cada um tem 2 quadros reais da folha da mascote
/// (Assets: `poppy_<humor>_1` e `_2`, 64x64).
enum PoppyMood: String, CaseIterable, Identifiable, Sendable {
    case idle, working, attention, done, failed, lost, sleeping, waving

    var id: String { rawValue }

    init(_ tone: AgentTone) {
        switch tone {
        case .needsYou: self = .attention
        case .error: self = .failed
        case .working: self = .working
        case .done: self = .done
        case .idle: self = .idle
        }
    }
}

/// Poppy em pixel art: 2 quadros alternando a 2 Hz, sem interpolacao.
/// Com Reduce Motion fica parada no quadro 1. Decorativa para VoiceOver (passe `label` para anunciar).
/// Use `size` multiplo de 64 (64, 128, 192) para os pixels ficarem inteiros.
struct PoppyView: View {
    let mood: PoppyMood
    var size: CGFloat
    var label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ mood: PoppyMood, size: CGFloat = 128, label: String? = nil) {
        self.mood = mood
        self.size = size
        self.label = label
    }

    var body: some View {
        Group {
            if reduceMotion {
                frame(1)
            } else {
                TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 0.5)) { context in
                    let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.5)
                    frame(tick % 2 + 1)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }

    private func frame(_ index: Int) -> some View {
        Image("poppy_\(mood.rawValue)_\(index)")
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .scaledToFit()
    }
}

#Preview("PoppyView") {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
        ForEach(PoppyMood.allCases) { PoppyView($0, size: 64) }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.Palette.base)
    .preferredColorScheme(.dark)
}
