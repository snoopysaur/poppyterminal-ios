import SwiftUI
import PoppyKit

/// Chat de uma janela com o Claude Code (padrao do v0.3.0). O estado vive no `ChatStore`,
/// criado na primeira aparicao porque precisa do `ServerStore` do ambiente.
struct ChatView: View {
    let session: String
    let window: String
    let onShowTerminal: () -> Void

    @Environment(ServerStore.self) private var store
    @State private var chat: ChatStore?

    init(session: String, window: String, onShowTerminal: @escaping () -> Void) {
        self.session = session
        self.window = window
        self.onShowTerminal = onShowTerminal
    }

    var body: some View {
        Group {
            if let chat {
                ChatContent(chat: chat, onShowTerminal: onShowTerminal)
            } else {
                Theme.Palette.base
            }
        }
        .background(Theme.Palette.base)
        .task {
            if chat == nil { chat = ChatStore(session: session, window: window, store: store) }
            await chat?.start()
        }
        .onDisappear { chat?.stop() }
    }
}

private struct ChatContent: View {
    @Bindable var chat: ChatStore
    let onShowTerminal: () -> Void

    @Environment(ServerStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var atBottom = true
    @State private var sheetItem: InboxItem?
    @State private var openingPending = false
    @State private var pendingGone = false
    @State private var shownTerminal = false
    @State private var approvedTick = 0

    private static let bottomID = "chat-bottom"

    var body: some View {
        VStack(spacing: 0) {
            topBar
            banners
            content
            if showsComposer {
                ChatComposer(chat: chat, lock: composerLock)
            }
        }
        .background(Theme.Palette.base)
        .onChange(of: scenePhase) { _, new in chat.scenePhaseChanged(new) }
        .onChange(of: chat.phase) { _, new in
            if case .unsupported = new, !shownTerminal {
                shownTerminal = true
                onShowTerminal()
            }
        }
        .sheet(item: $sheetItem) { item in
            InboxActionSheet(item: item) { approved in
                if approved { approvedTick += 1 }
            }
        }
        .sensoryFeedback(.success, trigger: approvedTick)
        .sensoryFeedback(.warning, trigger: chat.pending?.inboxId) { old, new in old != new && new != nil }
    }

    // MARK: topo e avisos

    private var tone: AgentTone {
        switch chat.agentState {
        case "working": .working
        case "needs_input": .needsYou
        case "errored": .error
        case "done": .done
        default: .idle
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            StatusPill(tone)
            Spacer(minLength: 0)
            Button(action: onShowTerminal) {
                // Em tamanhos de acessibilidade o rótulo quebrava ("Termi-nal"): fica só o ícone.
                ViewThatFits(in: .horizontal) {
                    Label("Terminal", systemImage: "terminal")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                    Image(systemName: "terminal")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 44)
                .background(Capsule().fill(Theme.Palette.surfaceStrong))
            }
            .accessibilityLabel(Text("Terminal"))
            .accessibilityIdentifier("chat-show-terminal")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Theme.Palette.base)
    }

    @ViewBuilder private var banners: some View {
        VStack(spacing: 6) {
            if case let .offline(savedAt) = chat.phase {
                banner(Text("offline · salvo às \(savedAt, format: .dateTime.hour().minute())"),
                       symbol: "icloud.slash", tone: .idle)
            }
            if !store.humanActions, chat.phase != .loading {
                banner(Text("Login sem Tailscale: o chat fica só para leitura."), symbol: "eye", tone: .needsYou)
            }
            if pendingGone {
                banner(Text("Esse pedido não está mais na caixa de entrada. Pode já ter sido respondido."),
                       symbol: "questionmark.circle", tone: .idle)
            }
            if let error = chat.lastError {
                errorBanner(error)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func banner(_ text: Text, symbol: String, tone: AgentTone) -> some View {
        Label {
            text.foregroundStyle(Theme.Palette.text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tone.color)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Palette.surface))
        .accessibilityElement(children: .combine)
    }

    private func errorBanner(_ error: APIError) -> some View {
        HStack(spacing: 8) {
            Label {
                Text(error.userMessage).foregroundStyle(Theme.Palette.text)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(AgentTone.error.color)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                chat.clearError()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Dispensar aviso"))
        }
        .padding(.leading, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AgentTone.error.color.opacity(0.16)))
        .accessibilityElement(children: .contain)
    }

    // MARK: conteudo

    @ViewBuilder private var content: some View {
        switch chat.phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Abrindo a conversa...")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .unsupported(reason):
            unsupported(reason)
        case let .failed(message):
            failed(message)
        case .offline, .live:
            conversation
        }
    }

    private func unsupported(_ reason: ChatUnsupportedReason) -> some View {
        ContentUnavailableView {
            Label("Sem chat nesta janela", systemImage: "terminal")
                .foregroundStyle(Theme.Palette.text)
        } description: {
            Text(reason.userMessage)
                .foregroundStyle(Theme.Palette.textSecondary)
        } actions: {
            Button("Abrir terminal", action: onShowTerminal)
                .buttonStyle(.poppyProminent)
        }
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                PoppyView(.lost, size: 128)
                Text("Não consegui abrir a conversa")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.Palette.text)
            }
        } description: {
            Text(message)
                .foregroundStyle(Theme.Palette.textSecondary)
        } actions: {
            Button("Tentar de novo") { Task { await chat.retry() } }
                .buttonStyle(.poppyProminent)
            Button("Abrir terminal", action: onShowTerminal)
                .buttonStyle(.poppyNeutral)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if chat.hasMore { olderButton }
                    ForEach(chat.messages) { message in
                        row(message)
                    }
                    if let outgoing = chat.outgoing {
                        OutgoingBubble(text: outgoing.text)
                    }
                    if chat.agentState == "working", chat.pending == nil {
                        workingRow
                    }
                    if let pending = chat.pending {
                        PendingPromptCard(prompt: pending, busy: openingPending) {
                            Task { await openPending(pending) }
                        }
                        .padding(.top, 4)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if chat.messages.isEmpty, chat.outgoing == nil, chat.pending == nil, !chat.hasMore {
                    emptyConversation
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom {
                    Button {
                        scroll(proxy)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.Palette.text)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Theme.Palette.surfaceStrong))
                    }
                    .padding(12)
                    .accessibilityLabel(Text("Ir para o fim"))
                    .transition(.opacity)
                }
            }
            // So acompanha o fim se a pessoa ja estava no fim.
            .onChange(of: chat.messages.last?.id) { _, _ in followIfAtBottom(proxy) }
            .onChange(of: chat.outgoing?.id) { _, _ in followIfAtBottom(proxy) }
            .onChange(of: chat.pending) { _, _ in
                pendingGone = false
                followIfAtBottom(proxy)
            }
            .onChange(of: chat.agentState) { _, _ in followIfAtBottom(proxy) }
        }
    }

    private func row(_ message: ChatMessage) -> some View {
        Group {
            if message.kind == .toolUse, let tool = message.tool {
                ToolCallRow(tool: tool, result: chat.toolResults[tool.id], running: isRunning(message))
            } else {
                MessageBubble(message: message)
            }
        }
    }

    /// Rodando: sem resultado, o agente trabalha e e a ultima chamada de ferramenta.
    private func isRunning(_ message: ChatMessage) -> Bool {
        guard chat.agentState == "working", let tool = message.tool, chat.toolResults[tool.id] == nil else { return false }
        return chat.messages.last(where: { $0.kind == .toolUse })?.id == message.id
    }

    private var olderButton: some View {
        Button {
            Task { await chat.loadOlder() }
        } label: {
            HStack(spacing: 8) {
                if chat.isLoadingOlder { ProgressView().controlSize(.small) }
                Text("Carregar mensagens anteriores")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(Theme.Palette.surface))
        }
        .disabled(chat.isLoadingOlder)
        .padding(.bottom, 4)
    }

    private var workingRow: some View {
        HStack(spacing: 8) {
            Image(systemName: AgentTone.working.symbol)
                .foregroundStyle(AgentTone.working.color)
                .symbolEffect(.pulse, isActive: !reduceMotion)
            Text("Claude está trabalhando...")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var emptyConversation: some View {
        VStack(spacing: 8) {
            PoppyView(.waving, size: 128)
            Text("Nenhuma mensagem ainda")
                .font(.headline)
                .foregroundStyle(Theme.Palette.text)
            Text("Escreva abaixo para falar com o Claude.")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding()
    }

    // MARK: rolagem

    private func followIfAtBottom(_ proxy: ScrollViewProxy) {
        guard atBottom else { return }
        scroll(proxy)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        }
    }

    // MARK: compositor e pedido pendente

    private var showsComposer: Bool {
        switch chat.phase {
        case .offline, .live: true
        default: false
        }
    }

    private var composerLock: ChatComposer.Lock {
        if !store.humanActions { return .readOnly }
        return chat.pending != nil ? .pending : .none
    }

    /// Abre o sheet da caixa de entrada com o item do pedido; se ainda nao esta la, rebusca antes.
    private func openPending(_ pending: PendingPrompt) async {
        guard !openingPending else { return }
        openingPending = true
        pendingGone = false
        defer { openingPending = false }
        var item = store.inbox.first { $0.id == pending.inboxId }
        if item == nil {
            await store.refreshAll()
            item = store.inbox.first { $0.id == pending.inboxId }
        }
        if let item {
            sheetItem = item
        } else {
            pendingGone = true
        }
    }
}
