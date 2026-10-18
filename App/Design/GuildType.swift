import SwiftUI
import UIKit

/// Tipografia Guild. Pixelify Sans Bold (fonte de pixel, OFL; trocou a Silkscreen em 18/10/2026 porque N e M liam como H) so em titulo de tela, cabecalho de secao,
/// rotulo de aba e rotulo de botao (decisao do Gobby). Comando, risco, aviso e texto longo ficam em
/// SF (corpo) ou JetBrains Mono (terminal/comando). Em tamanhos de acessibilidade (AX1 ou maior) e
/// na paisagem compacta, a fonte de pixel cede lugar a SF.
/// O texto vai em caixa normal no codigo: a Pixelify Sans tem caixa alta e baixa; o VoiceOver le como palavra.
enum GuildType {
    static let pixelName = "PixelifySans-Bold"

    /// Fonte de pixel presente no pacote? (falso so se o recurso faltar)
    static var pixelAvailable: Bool { UIFont(name: pixelName, size: 12) != nil }

    /// Tamanho de texto de acessibilidade lido direto do sistema (UIKit). O titulo da barra de
    /// navegacao vive num item de barra do UIKit e nao recebe o `dynamicTypeSize` do ambiente
    /// SwiftUI; por isso o titulo olha tambem o tamanho que a pessoa escolheu no iPhone.
    @MainActor static var systemAccessibilitySize: Bool {
        UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
    }

    /// True quando a fonte de pixel deve ceder a SF.
    static func usesSystemFont(size: DynamicTypeSize, compactHeight: Bool) -> Bool {
        size >= .accessibility1 || compactHeight
    }

    /// Font de pixel que acompanha o Dynamic Type do estilo `relativeTo`.
    static func pixel(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(pixelName, size: size, relativeTo: style)
    }

    /// Mesma ideia em UIKit (aparencia global de abas e barra de navegacao).
    static func pixelUIFont(_ size: CGFloat, textStyle: UIFont.TextStyle) -> UIFont {
        guard let base = UIFont(name: pixelName, size: size) else {
            return UIFont.systemFont(ofSize: size, weight: .bold)
        }
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base)
    }
}

/// Papel tipografico em pixel.
enum GuildTextRole {
    case screenTitle      // titulo de tela
    case sectionHeader    // cabecalho de secao
    case tabLabel         // rotulo de aba
    case button           // rotulo de botao

    var pixelSize: CGFloat {
        switch self {
        case .screenTitle: 22
        case .sectionHeader: 15
        case .tabLabel: 11
        case .button: 17
        }
    }

    var style: Font.TextStyle {
        switch self {
        case .screenTitle: .title2
        case .sectionHeader: .footnote
        case .tabLabel: .caption2
        case .button: .body
        }
    }

    /// Fonte SF usada quando o pixel cede.
    var systemFont: Font {
        switch self {
        case .screenTitle: .title2.weight(.bold)
        case .sectionHeader: .footnote.weight(.bold)
        case .tabLabel: .caption2.weight(.bold)
        case .button: .body.weight(.semibold)
        }
    }
}

private struct GuildTextModifier: ViewModifier {
    let role: GuildTextRole
    @Environment(\.dynamicTypeSize) var typeSize
    @Environment(\.verticalSizeClass) var verticalSizeClass

    func body(content: Content) -> some View {
        content.font(usesSystem ? role.systemFont : GuildType.pixel(role.pixelSize, relativeTo: role.style))
    }

    private var usesSystem: Bool {
        !GuildType.pixelAvailable
            || GuildType.usesSystemFont(size: typeSize, compactHeight: verticalSizeClass == .compact)
    }
}

/// Marca (para os testes de interface) qual fonte o titulo esta usando: "titulo-pixel" ou "titulo-sf".
private struct GuildTitleMarker: ViewModifier {
    @Environment(\.dynamicTypeSize) var typeSize
    @Environment(\.verticalSizeClass) var verticalSizeClass

    func body(content: Content) -> some View {
        let sf = !GuildType.pixelAvailable
            || GuildType.usesSystemFont(size: typeSize, compactHeight: verticalSizeClass == .compact)
        content.accessibilityIdentifier(sf ? "titulo-sf" : "titulo-pixel")
    }
}

/// Titulo de tela dentro da barra de navegacao: decide a fonte sozinho (ambiente SwiftUI OU tamanho
/// do sistema, porque o item de barra nao recebe o ambiente) e marca "titulo-pixel"/"titulo-sf".
struct GuildBarTitle: View {
    let title: LocalizedStringKey
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var systemAX = GuildType.systemAccessibilitySize

    private var usesSystem: Bool {
        !GuildType.pixelAvailable || systemAX
            || GuildType.usesSystemFont(size: typeSize, compactHeight: verticalSizeClass == .compact)
    }

    var body: some View {
        Text(title)
            .font(usesSystem ? GuildTextRole.screenTitle.systemFont
                             : GuildType.pixel(GuildTextRole.screenTitle.pixelSize, relativeTo: .title2))
            .accessibilityIdentifier(usesSystem ? "titulo-sf" : "titulo-pixel")
            .onReceive(NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification)) { _ in
                systemAX = GuildType.systemAccessibilitySize
            }
    }
}

extension View {
    /// Aplica o papel tipografico Guild (pixel, ou SF em AX/paisagem compacta).
    func guildText(_ role: GuildTextRole) -> some View {
        modifier(GuildTextModifier(role: role))
    }

    /// Como `guildText(.screenTitle)` e tambem expoe "titulo-pixel"/"titulo-sf" para o UITest.
    func guildScreenTitle() -> some View {
        modifier(GuildTextModifier(role: .screenTitle)).modifier(GuildTitleMarker())
    }
}
