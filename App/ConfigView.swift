import SwiftUI
import PoppyKit

/// Tela de configuracao: URL https do servidor (sem valor padrao no codigo) e senha opcional.
struct ConfigView: View {
    @ObservedObject var settings: AppSettings
    var onSave: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: Theme.background).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Image("Poppy")
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .accessibilityIdentifier("poppy")
                        Text("PoppyTerminal")
                            .font(.custom(Theme.fontRegular, size: 22))
                            .foregroundStyle(Color(uiColor: Theme.accent))
                            .accessibilityIdentifier("title")
                    }
                    label("URL do servidor (https)")
                    TextField("https://", text: $settings.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .modifier(Field())
                        .accessibilityIdentifier("field-url")
                    label("Senha (opcional; no tailnet o login Tailscale basta)")
                    SecureField("senha", text: $settings.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .modifier(Field())
                        .accessibilityIdentifier("field-senha")
                    label("Sessao (opcional; vazio = sessao padrao)")
                    TextField("padrao", text: $settings.session)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .modifier(Field())
                        .accessibilityIdentifier("field-sessao")
                    if !settings.sessionValid {
                        Text("Sessao: 1 a 32 caracteres, so letras, numeros, _ e -.")
                            .font(.custom(Theme.fontRegular, size: 13))
                            .foregroundStyle(Color(uiColor: Theme.red))
                    } else if settings.endpoint == nil && !settings.serverURL.isEmpty {
                        Text("Use um endereco https valido.")
                            .font(.custom(Theme.fontRegular, size: 13))
                            .foregroundStyle(Color(uiColor: Theme.red))
                    }
                    Button {
                        settings.save()
                        onSave()
                    } label: {
                        Text("Conectar")
                            .font(.custom(Theme.fontRegular, size: 17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: settings.endpoint == nil ? Theme.surface1 : Theme.mauve))
                            .foregroundStyle(Color(uiColor: Theme.crust))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(settings.endpoint == nil)
                    .accessibilityIdentifier("btn-conectar")
                }
                .padding()
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.custom(Theme.fontRegular, size: 13))
            .foregroundStyle(Color(uiColor: Theme.subtext0))
    }

    private struct Field: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.custom(Theme.fontRegular, size: 16))
                .foregroundStyle(Color(uiColor: Theme.text))
                .padding(10)
                .background(Color(uiColor: Theme.surface0))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Tela "Tailscale desligado": a conexao esta inalcancavel; segue tentando sozinha.
struct TailscaleOffView: View {
    var retry: () -> Void
    var openSettings: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: Theme.background).opacity(0.96).ignoresSafeArea()
            VStack(spacing: 14) {
                Image("Poppy")
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Tailscale desligado?")
                    .font(.custom(Theme.fontRegular, size: 20))
                    .foregroundStyle(Color(uiColor: Theme.peach))
                    .accessibilityIdentifier("tailscale-off")
                Text("Nao consegui falar com o servidor. Ligue o Tailscale (VPN) e eu reconecto sozinha.")
                    .font(.custom(Theme.fontRegular, size: 14))
                    .foregroundStyle(Color(uiColor: Theme.subtext1))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                HStack(spacing: 12) {
                    pill("Abrir Tailscale", Theme.surface1) {
                        if let url = URL(string: "tailscale://") { UIApplication.shared.open(url) }
                    }
                    pill("Tentar de novo", Theme.mauve, action: retry)
                }
                pill("Ajustes", Theme.surface0, action: openSettings)
            }
        }
    }

    private func pill(_ title: String, _ color: UIColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom(Theme.fontRegular, size: 15))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color(uiColor: color))
                .foregroundStyle(Color(uiColor: color == Theme.mauve ? Theme.crust : Theme.text))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
}
