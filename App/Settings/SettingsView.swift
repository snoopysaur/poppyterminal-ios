import SwiftUI
import PoppyKit

/// Aba Ajustes: servidor, estado da conexao, snippets e sobre.
struct SettingsView: View {
    @Environment(ServerStore.self) private var store
    @ObservedObject var settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ServerFields(settings: settings)
                        .listRowBackground(Theme.Palette.surface)
                    Button("Salvar e reconectar") {
                        settings.save()
                        settings.apply(to: store)
                    }
                    .disabled(!settings.urlValid || !settings.hasChanges)
                    .listRowBackground(Theme.Palette.surface)
                    .accessibilityIdentifier("btn-salvar")
                } header: {
                    Text("Servidor")
                } footer: {
                    Text("A senha fica no Keychain do aparelho. No tailnet o login Tailscale basta.")
                }

                Section("Conexão") {
                    LabeledContent("Estado") {
                        Text(statusText).foregroundStyle(statusColor)
                    }
                    .listRowBackground(Theme.Palette.surface)
                    if let info = store.info {
                        LabeledContent("Servidor", value: info.serverVersion)
                            .listRowBackground(Theme.Palette.surface)
                    }
                    Button("Tentar de novo") { store.start() }
                        .listRowBackground(Theme.Palette.surface)
                }

                Section("Terminal") {
                    NavigationLink("Snippets") { SnippetsView() }
                        .listRowBackground(Theme.Palette.surface)
                }

                Section("Sobre") {
                    LabeledContent("Versão", value: Self.version)
                        .listRowBackground(Theme.Palette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.base)
            .navigationTitle("Ajustes")
            .scrollDismissesKeyboard(.interactively)
        }
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

    private var statusColor: Color {
        switch store.connection {
        case .online: AgentTone.done.color
        case .connecting, .unconfigured: Theme.Palette.textSecondary
        case .tailscaleOff, .daemonOld: AgentTone.needsYou.color
        case .accessDenied, .daemonDown, .failed: AgentTone.error.color
        }
    }

    private static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
