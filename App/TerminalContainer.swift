import SwiftUI
import SwiftTerm
import PoppyKit

/// TerminalView que avisa o tamanho (celulas + pixels) a cada layout.
final class PoppyTerminalView: TerminalView {
    var onLayout: ((Int, Int, Int, Int) -> Void)?
    /// Long-press: entrega o texto visivel da tela (copia por folha, sem selecao no terminal).
    var onLongPressText: ((String) -> Void)?
    private var copyPress: UILongPressGestureRecognizer?

    /// Texto atualmente visivel (linhas da tela), sem espacos a direita.
    func visibleText() -> String {
        let t = getTerminal()
        var lines: [String] = []
        for row in 0..<t.rows {
            lines.append(t.getLine(row: row)?.translateToString(trimRight: true) ?? "")
        }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    @objc private func handleCopyPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPressText?(visibleText())
    }

    private func installCopyPress() {
        guard copyPress == nil else { return }
        let g = UILongPressGestureRecognizer(target: self, action: #selector(handleCopyPress(_:)))
        g.minimumPressDuration = 0.6
        addGestureRecognizer(g)
        copyPress = g
    }

    /// O tuios manda LF puro entre as linhas e conta com o terminal para
    /// voltar a coluna (o xterm.js do navegador faz isso). Sem o modo LNM
    /// (ESC[20h) as linhas descem em escada e a tela fica embaralhada.
    /// O RIS limpa restos de uma sessao anterior (reconexao).
    func resetForNewSession() {
        feed(byteArray: [0x1b, 0x63, 0x1b, 0x5b, 0x32, 0x30, 0x68][...])
    }

    /// Selecao por toque/arrasto desligada: com o mouse do tuios ativo, o
    /// toque vai para o servidor; selecao do SwiftTerm so atrapalha (manchas).
    private func stripSelectionGestures() {
        for g in gestureRecognizers ?? [] {
            if g === copyPress { continue }
            if g is UILongPressGestureRecognizer {
                removeGestureRecognizer(g)
            } else if let t = g as? UITapGestureRecognizer, t.numberOfTapsRequired > 1 {
                removeGestureRecognizer(t)
            } else if let p = g as? UIPanGestureRecognizer, p !== panGestureRecognizer,
                      p.maximumNumberOfTouches > 1 {
                removeGestureRecognizer(p)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stripSelectionGestures()
        installCopyPress()
        let t = getTerminal()
        let scale = traitCollection.displayScale
        onLayout?(t.cols, t.rows, Int(bounds.width * scale), Int(bounds.height * scale))
    }
}

struct TerminalContainer: UIViewRepresentable {
    let connection: SipConnection
    var onCopyRequest: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(connection: connection) }

    func makeUIView(context: Context) -> PoppyTerminalView {
        let coordinator = context.coordinator
        let view = PoppyTerminalView(frame: .zero)
        view.font = Theme.terminalFont(size: 14)
        view.nativeBackgroundColor = Theme.background
        view.nativeForegroundColor = Theme.foreground
        view.terminalDelegate = coordinator

        let conn = connection
        view.keyboardDismissMode = .interactive
        let bar = KeyBarView(hideKeyboard: { [weak view] in _ = view?.resignFirstResponder() },
                             send: { bytes in conn.sendInput(bytes) })
        view.inputAccessoryView = bar
        coordinator.keyBar = bar

        view.onLongPressText = onCopyRequest
        view.onLayout = { cols, rows, w, h in
            conn.updateSize(cols: cols, rows: rows, widthPx: w, heightPx: h)
        }
        connection.onSessionStart = { [weak view] in view?.resetForNewSession() }
        connection.onOutput = { [weak view] bytes in
            view?.feed(byteArray: bytes)
        }
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: PoppyTerminalView, context: Context) {
        uiView.onLongPressText = onCopyRequest
    }

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        let connection: SipConnection
        var keyBar: KeyBarView?

        init(connection: SipConnection) {
            self.connection = connection
        }

        nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            MainActor.assumeIsolated {
                let scale = source.traitCollection.displayScale
                connection.updateSize(
                    cols: newCols, rows: newRows,
                    widthPx: Int(source.bounds.width * scale),
                    heightPx: Int(source.bounds.height * scale)
                )
            }
        }

        nonisolated func setTerminalTitle(source: TerminalView, title: String) {}

        nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            MainActor.assumeIsolated {
                let out = keyBar?.transform(bytes) ?? bytes
                connection.sendInput(out)
            }
        }

        nonisolated func scrolled(source: TerminalView, position: Double) {}

        nonisolated func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}

        nonisolated func bell(source: TerminalView) {}

        nonisolated func clipboardCopy(source: TerminalView, content: Data) {
            if let text = String(data: content, encoding: .utf8) {
                DispatchQueue.main.async { UIPasteboard.general.string = text }
            }
        }

        nonisolated func clipboardRead(source: TerminalView) -> Data? { nil }

        nonisolated func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
