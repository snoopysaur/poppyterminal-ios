import SwiftUI

struct ContentView: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var connection = SipConnection()
    @State private var configured = false
    @State private var showSettings = false
    @State private var copyText: CopyPayload?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(uiColor: Theme.background).ignoresSafeArea()
            if configured {
                terminal
            } else {
                ConfigView(settings: settings) { connect() }
            }
        }
        .onAppear {
            if settings.endpoint != nil, !configured { connect() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, configured, connection.status != .connected {
                connection.reconnectNow()
            }
        }
        .sheet(item: $copyText) { payload in
            CopySheet(rawText: payload.text)
        }
        .sheet(isPresented: $showSettings) {
            ConfigView(settings: settings) {
                showSettings = false
                connect()
            }
        }
    }

    private var terminal: some View {
        ZStack(alignment: .topTrailing) {
            TerminalContainer(connection: connection, onCopyRequest: { copyText = CopyPayload(text: $0) })
                .accessibilityIdentifier("terminal")
            statusBadge
            if connection.status == .tailscaleOff {
                TailscaleOffView(retry: { connection.reconnectNow() },
                                 openSettings: { showSettings = true })
            }
            if connection.status == .denied {
                deniedView
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 8) {
            switch connection.status {
            case .connecting: Text("conectando...")
            case .reconnecting(let n): Text("reconectando (\(n))...")
            case .failed(let m): Text(m)
            default: EmptyView()
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityIdentifier("btn-ajustes")
        }
        .font(.custom(Theme.fontRegular, size: 12))
        .foregroundStyle(Color(uiColor: Theme.overlay1))
        .padding(.horizontal, 8).padding(.top, 2)
    }

    private var deniedView: some View {
        VStack(spacing: 12) {
            Text("Acesso negado")
                .font(.custom(Theme.fontRegular, size: 20))
                .foregroundStyle(Color(uiColor: Theme.red))
            Text("O servidor recusou a conexao. Confira a senha e o endereco.")
                .font(.custom(Theme.fontRegular, size: 14))
                .foregroundStyle(Color(uiColor: Theme.subtext1))
                .multilineTextAlignment(.center)
            Button("Ajustes") { showSettings = true }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: Theme.background).opacity(0.96))
    }

    private func connect() {
        guard let url = settings.endpoint else { return }
        configured = true
        connection.start(endpoint: url, user: settings.user, password: settings.password)
    }
}
