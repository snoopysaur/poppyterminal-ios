#if DEBUG
import SwiftUI
import PoppyKit

/// Tela catalogo (so Debug) com cada componente de `App/Design`, para revisar e capturar.
/// Para abrir: o app raiz pode mostrar `DesignCatalogView()` quando `DesignCatalog.isRequested`
/// (argumento de lancamento `-design-catalog`).
enum DesignCatalog {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-design-catalog")
    }
}

struct DesignCatalogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Catálogo visual")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)

                section("Pedido pendente (v0.3.2)") {
                    VStack(spacing: 12) {
                        PendingPromptCard(
                            prompt: PendingPrompt(inboxId: "17", kind: "approval", summary: "Bash: rm -rf build/"),
                            busy: false, action: {})
                        PendingInfoCard(
                            prompt: PendingPrompt(inboxId: "219", kind: "approval", summary: "PowerShell: Get-ChildItem",
                                                  answerable: false),
                            onOpenTerminal: {})
                        PendingStaleBanner(
                            message: APIError.api(status: 409, code: "pending_prompt", message: "", retryAfter: nil)
                                .pendingMessage(answerable: false),
                            onRefresh: {}, onOpenTerminal: {}, onDismiss: {})
                    }
                }

                section("Papéis de cor") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        swatch("base", Theme.Palette.base)
                        swatch("surface", Theme.Palette.surface)
                        swatch("surfaceStrong", Theme.Palette.surfaceStrong)
                        swatch("text", Theme.Palette.text)
                        swatch("textSecondary", Theme.Palette.textSecondary)
                        swatch("accent (Mauve)", Theme.Palette.accent)
                        ForEach(AgentTone.allCases) { swatch($0.labelText, $0.color) }
                    }
                }

                section("StatusPill") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(AgentTone.allCases) { StatusPill($0) }
                        StatusPill(.needsYou, count: 2)
                    }
                }

                section("AgentStateBadge") {
                    HStack(spacing: 20) {
                        ForEach(AgentTone.allCases) {
                            AgentStateBadge($0, count: $0 == .needsYou ? 3 : nil)
                        }
                    }
                }

                section("Linha de lista") {
                    VStack(spacing: 0) {
                        ForEach(AgentTone.allCases) { tone in
                            HStack(spacing: 12) {
                                AgentStateBadge(tone)
                                VStack(alignment: .leading) {
                                    Text("sessão \(tone.rawValue)").font(.body.weight(.semibold))
                                    Text("2 janelas").font(.footnote).foregroundStyle(Theme.Palette.textSecondary)
                                }
                                Spacer()
                                StatusPill(tone)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .foregroundStyle(Theme.Palette.text)
                            if tone != AgentTone.allCases.last { Divider().overlay(Theme.Palette.surfaceStrong) }
                        }
                    }
                    .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                section("Comando (mono)") {
                    Text("$ xcodebuild test\n~/Desktop/Teste/poppyterminal-ios")
                        .font(.custom(Theme.fontRegular, size: 14, relativeTo: .callout))
                        .foregroundStyle(Theme.Palette.text)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Palette.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                section("PoppyView") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                        ForEach(PoppyMood.allCases) { mood in
                            VStack(spacing: 4) {
                                PoppyView(mood, size: 64)
                                Text(mood.rawValue).font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                    }
                }

                section("EmptyStateView") {
                    VStack(spacing: 16) {
                        ForEach(kinds, id: \.self) { kind in
                            EmptyStateView(kind, primary: {}, secondary: {})
                                .frame(minHeight: 420)
                                .background(Theme.Palette.base, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        EmptyStateView(.allCaughtUp)
                            .frame(minHeight: 320)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.Palette.base)
        .preferredColorScheme(.dark)
    }

    private var kinds: [EmptyStateView.Kind] {
        [.noSessions, .connecting, .tailscaleOff, .accessDenied, .serverUnreachable]
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color).frame(height: 28)
            Text(name).font(.footnote).foregroundStyle(Theme.Palette.text)
        }
        .padding(10)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview("Catálogo") {
    DesignCatalogView()
}
#endif
