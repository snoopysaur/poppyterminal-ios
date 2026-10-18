import SwiftUI
import PoppyKit

/// Aba Ajustes: servidor, estado da conexao, snippets e sobre.
struct SettingsView: View {
    @Environment(ServerStore.self) private var store
    @ObservedObject var settings: AppSettings
    @State private var chatCacheBytes = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ServerFields(settings: settings)
                        .guildRowPadding()
                        .guildListRow()
                    Button("Salvar e reconectar") {
                        settings.save()
                        settings.apply(to: store)
                    }
                    .buttonStyle(.poppyProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!settings.urlValid || !settings.hasChanges)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("btn-salvar")
                    GuildFootnoteRow {
                        footnote("A senha fica no Keychain do aparelho. No tailnet o login Tailscale basta.")
                    }
                } header: {
                    GuildSectionHeader("Servidor")
                
                }

                Section {
                    LabeledContent("Estado") {
                        Text(statusText).foregroundStyle(Theme.Palette.text)
                    }
                    .guildRowPadding()
                    .guildListRow(.panel, tone: statusTone)
                    if let info = store.info {
                        LabeledContent("Servidor", value: info.serverVersion)
                            .guildRowPadding()
                            .guildListRow()
                    }
                    Button("Tentar de novo") { store.start() }
                        .buttonStyle(.poppyNeutral)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    GuildSectionHeader("Conexão")
                }

                Section {
                    NavigationLink("Snippets") { SnippetsView() }
                        .guildRowPadding()
                        .guildListRow()
                } header: {
                    GuildSectionHeader("Terminal")
                }

                Section {
                    Button("Apagar cache do chat") {
                        ChatCache.shared.removeAll()
                        chatCacheBytes = ChatCache.shared.totalBytes()
                    }
                    .disabled(chatCacheBytes == 0)
                    .buttonStyle(.poppyNeutral)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityValue(Text(Self.sizeText(chatCacheBytes)))
                    .accessibilityIdentifier("btn-apagar-cache-chat")
                    LabeledContent("Tamanho atual", value: Self.sizeText(chatCacheBytes))
                        .guildRowPadding()
                        .guildListRow()
                    GuildFootnoteRow {
                        footnote("Guarda só o texto já filtrado das últimas mensagens, neste aparelho, por até 7 dias.")
                    }
                } header: {
                    GuildSectionHeader("Chat")
                
                }

                Section {
                    LabeledContent("Versão", value: Self.version)
                        .guildRowPadding()
                        .guildListRow()
                    NavigationLink("Ícone do app") { AppIconPickerView() }
                        .guildRowPadding()
                        .guildListRow()
                        .accessibilityIdentifier("linha-icone")
                    NavigationLink("Licenças") { LicensesView() }
                        .guildRowPadding()
                        .guildListRow()
                        .accessibilityIdentifier("linha-licencas")
                } header: {
                    GuildSectionHeader("Sobre")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 24, for: .scrollContent) // o fim da lista nao fica sob a barra de abas
            .background(Theme.Palette.base)
            .navigationTitle("Ajustes")
            .guildNavTitle("Ajustes")
            .scrollDismissesKeyboard(.interactively)
            .task { chatCacheBytes = ChatCache.shared.totalBytes() }
        }
    }

    private static func sizeText(_ bytes: Int) -> String {
        bytes == 0 ? String(localized: "vazio") : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var statusText: String {
        switch store.connection {
        case .unconfigured: String(localized: "Sem endereço")
        case .connecting: String(localized: "Conectando...")
        case .online: String(localized: "Conectado")
        case .tailscaleOff: String(localized: "Tailscale desligado")
        case .accessDenied: String(localized: "Acesso negado")
        case .daemonOld: String(localized: "Servidor desatualizado")
        case .daemonDown: String(localized: "Daemon fora do ar")
        case .failed(let m): m
        }
    }

    /// Cor do fio da moldura da linha de estado (o texto fica em `text`; cor nunca e o unico sinal).
    private var statusTone: Color? {
        switch store.connection {
        case .online: AgentTone.done.color
        case .connecting, .unconfigured: nil
        case .tailscaleOff, .daemonOld: AgentTone.needsYou.color
        case .accessDenied, .daemonDown, .failed: AgentTone.error.color
        }
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
    }

    private static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
