import SwiftUI

/// Ajudantes de lista e de bloco no estilo Guild (so token de cor, canto reto, sem sombra).
extension View {
    /// Linha de `List` com moldura Guild no fundo. A linha precisa dar o recuo interno com
    /// `guildRowPadding()`. Mantem `List` (deslizar, puxar para atualizar, VoiceOver).
    func guildListRow(_ kind: GuildFrameKind = .panel, tone: Color? = nil) -> some View {
        listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(
                GuildFrameBackground(kind: kind, tone: tone)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
            )
    }

    /// Recuo interno de uma linha emoldurada (a moldura tem 4 pt de espessura).
    func guildRowPadding() -> some View {
        padding(.horizontal, 12).padding(.vertical, 10)
    }

    /// Bloco avulso com moldura (fora de `List`).
    func guildPanel(_ kind: GuildFrameKind = .panel, tone: Color? = nil, padding: CGFloat = 12) -> some View {
        self.padding(padding + 4).guildFrame(kind, tone: tone)
    }
}

/// Cabecalho de secao em letra de pixel (volta para SF em AX/paisagem compacta).
struct GuildSectionHeader: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .guildText(.sectionHeader)
            .foregroundStyle(Theme.Palette.textSecondary)
            .textCase(nil)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Titulo de tela em pixel na barra de navegacao (modo compacto, sem o titulo grande vazio).
struct GuildNavTitle: ViewModifier {
    let title: LocalizedStringKey
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .guildScreenTitle()
                        .foregroundStyle(Theme.Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}

extension View {
    /// Titulo Guild (pixel) no alto da tela. Mantenha tambem `.navigationTitle` para o botao Voltar.
    func guildNavTitle(_ title: LocalizedStringKey) -> some View { modifier(GuildNavTitle(title: title)) }
}
