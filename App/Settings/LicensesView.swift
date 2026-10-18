import SwiftUI

/// Licencas de terceiros usadas pelo app. Cada linha abre o texto da licenca.
/// As fontes OFL levam o texto completo do arquivo empacotado (`OFL.txt`, `OFL-Pixelify.txt`).
struct LicenseEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let use: String
    let kind: String
    let url: String
    let holder: String
    /// Nome do arquivo `.txt` empacotado com o texto completo (so as fontes OFL).
    let bundledText: String?

    /// Texto exibido: o arquivo empacotado ou, na falta dele, o aviso MIT com o titular.
    var text: String {
        if let file = bundledText,
           let u = Bundle.main.url(forResource: file, withExtension: "txt"),
           let s = try? String(contentsOf: u, encoding: .utf8) {
            return s
        }
        if kind == "MIT" { return Self.mit(holder: holder) }
        return "\(holder)\n\(kind)\n\(url)"
    }

    static func mit(holder: String) -> String {
        """
        MIT License

        Copyright (c) \(holder)

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and \
        associated documentation files (the "Software"), to deal in the Software without restriction, \
        including without limitation the rights to use, copy, modify, merge, publish, distribute, \
        sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or \
        substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING \
        BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND \
        NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, \
        DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    }

    static let all: [LicenseEntry] = [
        LicenseEntry(id: "pixelify", name: "Pixelify Sans", use: "Letra de pixel dos títulos e botões",
                     kind: "SIL OFL 1.1", url: "https://github.com/eifetx/Pixelify-Sans",
                     holder: "Copyright 2021 The Pixelify Sans Project Authors", bundledText: "OFL-Pixelify"),
        LicenseEntry(id: "jetbrains", name: "JetBrains Mono", use: "Letra do terminal e dos comandos",
                     kind: "SIL OFL 1.1", url: "https://github.com/JetBrains/JetBrainsMono",
                     holder: "The JetBrains Mono Project Authors", bundledText: "OFL"),
        LicenseEntry(id: "nerd", name: "Nerd Fonts", use: "Símbolos extras do terminal",
                     kind: "MIT", url: "https://github.com/ryanoasis/nerd-fonts",
                     holder: "Ryan L McIntyre and the Nerd Fonts contributors", bundledText: nil),
        LicenseEntry(id: "swiftterm", name: "SwiftTerm", use: "Motor do terminal",
                     kind: "MIT", url: "https://github.com/migueldeicaza/SwiftTerm",
                     holder: "Miguel de Icaza", bundledText: nil),
        LicenseEntry(id: "catppuccin", name: "Catppuccin", use: "Paleta reserva (tema Mocha)",
                     kind: "MIT", url: "https://github.com/catppuccin/catppuccin",
                     holder: "Catppuccin", bundledText: nil),
    ]
}

/// Tela Ajustes > Licenças.
struct LicensesView: View {
    var body: some View {
        List {
            Section {
                ForEach(LicenseEntry.all) { entry in
                    NavigationLink {
                        LicenseDetailView(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.body.weight(.semibold))
                            Text("\(entry.use) · \(entry.kind)")
                                .font(.footnote)
                                .foregroundStyle(Theme.Palette.textSecondary)
                        }
                    }
                    .guildRowPadding()
                    .guildListRow()
                    .accessibilityIdentifier("licenca-\(entry.id)")
                }
                GuildFootnoteRow {
                    Text("O app usa estas obras de terceiros. Toque para ler a licença completa.")
                }
            } header: {
                GuildSectionHeader("Código e fontes de terceiros")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.base)
        .navigationTitle("Licenças")
        .guildNavTitle("Licenças")
        .accessibilityIdentifier("licencas-lista")
    }
}

struct LicenseDetailView: View {
    let entry: LicenseEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.headline).foregroundStyle(Theme.Palette.text)
                    Text(entry.holder).font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                    if let link = URL(string: entry.url) {
                        Link(entry.url, destination: link)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .guildPanel()

                Text(entry.text)
                    .font(.custom(Theme.fontRegular, size: 12, relativeTo: .caption))
                    .foregroundStyle(Theme.Palette.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.Palette.sunken)
                    .accessibilityIdentifier("licenca-texto")
            }
            .padding(16)
        }
        .background(Theme.Palette.base)
        .navigationTitle(entry.name)
        .guildNavTitle(LocalizedStringKey(entry.name))
    }
}
