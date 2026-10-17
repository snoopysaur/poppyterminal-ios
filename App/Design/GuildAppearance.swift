import SwiftUI
import UIKit

/// Aparencia global (UIKit) das abas, da barra de navegacao e do seletor segmentado, nas cores Guild.
/// Definida uma vez e reaplicada ao mudar o tamanho do texto: em AX1 ou maior os rotulos voltam a SF.
@MainActor
enum GuildAppearance {
    static func apply(accessibilitySize: Bool) {
        let tabFont = accessibilitySize
            ? UIFont.preferredFont(forTextStyle: .caption2).withBold()
            : GuildType.pixelUIFont(10, textStyle: .caption2)
        let titleFont = accessibilitySize
            ? UIFont.preferredFont(forTextStyle: .headline)
            : GuildType.pixelUIFont(14, textStyle: .headline)
        let largeFont = accessibilitySize
            ? UIFont.preferredFont(forTextStyle: .largeTitle).withBold()
            : GuildType.pixelUIFont(24, textStyle: .largeTitle)

        // Abas: fundo mantle, traco superior bronze, ouro no selecionado, contador vermelho com texto escuro.
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = Theme.mantle
        tab.shadowColor = Theme.border
        let item = UITabBarItemAppearance()
        item.normal.iconColor = Theme.subtext0
        item.normal.titleTextAttributes = [.foregroundColor: Theme.subtext0, .font: tabFont]
        item.selected.iconColor = Theme.accent
        item.selected.titleTextAttributes = [.foregroundColor: Theme.accent, .font: tabFont]
        for state in [item.normal, item.selected, item.focused, item.disabled] {
            state.badgeBackgroundColor = Theme.red
            state.badgeTextAttributes = [.foregroundColor: Theme.onBadge]
        }
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Barra de navegacao: fundo mantle, linha bronze embaixo, titulos em pixel (ou SF em AX).
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = Theme.mantle
        nav.shadowColor = Theme.border
        nav.titleTextAttributes = [.foregroundColor: Theme.text, .font: titleFont]
        nav.largeTitleTextAttributes = [.foregroundColor: Theme.text, .font: largeFont]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        // Seletor Chat/Terminal: ouro no escolhido, texto escuro sobre ele.
        let seg = UISegmentedControl.appearance()
        seg.backgroundColor = Theme.surface1
        seg.selectedSegmentTintColor = Theme.accent
        seg.setTitleTextAttributes([.foregroundColor: Theme.text], for: .normal)
        seg.setTitleTextAttributes([.foregroundColor: Theme.onAccent], for: .selected)

        refreshLiveBars(tab: tab, nav: nav)
    }

    /// As barras que ja estao na tela nao leem o proxy de novo: atualiza as existentes.
    private static func refreshLiveBars(tab: UITabBarAppearance, nav: UINavigationBarAppearance) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { walk(window, tab: tab, nav: nav) }
        }
    }

    private static func walk(_ view: UIView, tab: UITabBarAppearance, nav: UINavigationBarAppearance) {
        if let bar = view as? UITabBar {
            bar.standardAppearance = tab
            bar.scrollEdgeAppearance = tab
        } else if let bar = view as? UINavigationBar {
            bar.standardAppearance = nav
            bar.scrollEdgeAppearance = nav
            bar.compactAppearance = nav
        }
        for child in view.subviews { walk(child, tab: tab, nav: nav) }
    }
}

private extension UIFont {
    func withBold() -> UIFont {
        guard let d = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: d, size: 0)
    }
}

private struct GuildAppearanceModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.onChange(of: typeSize, initial: true) { _, size in
            GuildAppearance.apply(accessibilitySize: size >= .accessibility1)
        }
    }
}

extension View {
    /// Aplica a aparencia global Guild e a reaplica quando o tamanho do texto muda.
    func guildAppearance() -> some View { modifier(GuildAppearanceModifier()) }
}
