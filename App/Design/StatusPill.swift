import SwiftUI

/// Pastilha informativa de estado: selo escuro quadrado com simbolo colorido + rotulo em `text`.
/// O texto fica em `Palette.text` (AA sobre o selo); a cor do estado vai so no simbolo e no fio da moldura.
/// Ocioso: so o icone e cinza; o rotulo usa o texto secundario.
/// Nao e botao: se precisar tocar, envolva num `Button` com alvo de 44 pt.
struct StatusPill: View {
    let tone: AgentTone
    var text: String?
    var count: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ tone: AgentTone, text: String? = nil, count: Int? = nil) {
        self.tone = tone
        self.text = text
        self.count = count
    }

    private var title: String {
        guard let count else { return text ?? tone.labelText }
        if let text { return "\(count) \(text)" }
        return tone.labelText(count: count)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tone.symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(tone.color)
                .symbolEffect(.pulse, isActive: tone == .working && !reduceMotion)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tone == .idle ? Theme.Palette.textSecondary : Theme.Palette.text)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                .multilineTextAlignment(.leading)
        }
        // Tamanho normal: a pastilha nunca quebra em varias linhas. Texto de acessibilidade: ela passa a
        // caber na largura da tela e o texto quebra (antes saia pela borda e empurrava o resto).
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
        .padding(.vertical, 8)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .background(background)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var background: some View {
        GuildFrameBackground(kind: .seal, tone: tone == .idle ? Theme.Palette.border : tone.color)
    }
}

#Preview("StatusPill") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(AgentTone.allCases) { StatusPill($0) }
        StatusPill(.needsYou, count: 2)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.Palette.surface)
    .preferredColorScheme(.dark)
}
