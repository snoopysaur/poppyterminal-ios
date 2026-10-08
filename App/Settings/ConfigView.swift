import SwiftUI
import PoppyKit

/// Primeira conexao: Poppy, URL do servidor (sem valor padrao no codigo) e senha opcional.
struct ConfigView: View {
    @ObservedObject var settings: AppSettings
    var onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    PoppyView(.waving, size: 64)
                    Text("PoppyTerminal")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.Palette.accent)
                        .accessibilityIdentifier("title")
                        .accessibilityAddTraits(.isHeader)
                }
                Text("Conecte ao seu PC pela rede Tailscale. No tailnet o login Tailscale basta; a senha é opcional.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)

                ServerFields(settings: settings)

                Button("Conectar") {
                    settings.save()
                    onSave()
                }
                .buttonStyle(.poppyProminent)
                .frame(maxWidth: .infinity)
                .disabled(!settings.urlValid)
                .opacity(settings.urlValid ? 1 : 0.5)
                .accessibilityIdentifier("btn-conectar")
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// Campos de URL, usuario e senha (usados na primeira conexao e em Ajustes).
struct ServerFields: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Endereço do servidor") {
                TextField("https://", text: $settings.serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .accessibilityIdentifier("field-url")
            }
            if !settings.serverURL.isEmpty && !settings.urlValid {
                Text("Use um endereço https válido.")
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: Theme.red))
            }
            field("Usuário") {
                TextField("tuios", text: $settings.user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("field-usuario")
            }
            field("Senha (opcional)") {
                SecureField("senha", text: $settings.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("field-senha")
            }
        }
    }

    private func field<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
            content()
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
