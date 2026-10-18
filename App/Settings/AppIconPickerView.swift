import SwiftUI
import UIKit

/// Escolha do icone do app: C (Guild, principal) ou A (Mocha, alternativo). So troca o icone; as cores
/// do app nao mudam (tema A completo fica para a v0.7).
struct AppIconPickerView: View {
    struct Choice: Identifiable {
        let id: String               // identificador de teste
        let alternateName: String?   // nil = icone principal
        let title: String
        let detail: String
        let preview: String
    }

    static let choices = [
        Choice(id: "guild", alternateName: nil, title: "Guild", detail: "Moldura de ouro. É o ícone principal.", preview: "IconPreviewC"),
        Choice(id: "mocha", alternateName: "AppIconA", title: "Mocha", detail: "Fundo azul-noite e o prompt.", preview: "IconPreviewA"),
    ]

    @State private var current: String? = UIApplication.shared.alternateIconName
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(Self.choices) { choice in
                    Button { select(choice) } label: { row(choice) }
                        .buttonStyle(.plain)
                        .guildListRow(.panel, tone: choice.alternateName == current ? Theme.Palette.accent : nil)
                        .accessibilityIdentifier("icone-\(choice.id)")
                        .accessibilityAddTraits(choice.alternateName == current ? .isSelected : [])
                }
                if let errorText {
                    GuildFootnoteRow { Text(errorText).foregroundStyle(AgentTone.error.color) }
                }
                GuildFootnoteRow {
                    Text("O iOS mostra um aviso ao trocar o ícone. As cores do app não mudam.")
                }
            } header: {
                GuildSectionHeader("Ícone do app")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.base)
        .navigationTitle("Ícone do app")
        .guildNavTitle("Ícone do app")
    }

    private func row(_ choice: Choice) -> some View {
        HStack(spacing: 14) {
            Image(choice.preview)
                .resizable()
                .interpolation(.none)
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.title).font(.body.weight(.semibold)).foregroundStyle(Theme.Palette.text)
                Text(choice.detail).font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 8)
            if choice.alternateName == current {
                Image(systemName: "checkmark.square.fill")
                    .foregroundStyle(Theme.Palette.accent)
                    .accessibilityLabel("Em uso")
            }
        }
        .guildRowPadding()
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func select(_ choice: Choice) {
        guard choice.alternateName != current else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            errorText = String(localized: "Este aparelho não aceita trocar o ícone.")
            return
        }
        errorText = nil
        UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
            Task { @MainActor in
                if let error {
                    errorText = String(localized: "Não consegui trocar o ícone: \(error.localizedDescription)")
                } else {
                    current = UIApplication.shared.alternateIconName
                }
            }
        }
    }
}
