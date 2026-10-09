import SwiftUI
import SwiftTerm
import PoppyKit

/// Conta da fonte da visao de celular: cabe `cols` colunas na largura util.
enum TerminalFit {
    static let minPoints: CGFloat = 6
    static let maxPoints: CGFloat = 14
    /// Avanco de uma celula do JetBrains Mono, em fracao do corpo da fonte.
    static let advanceRatio: CGFloat = 0.6

    /// `clamp(floor(largura / (cols x 0,6)), 6...14)`; nil com `cols <= 0` ou largura invalida
    /// (fica o comportamento de antes). Usa `largura x 10 / (cols x 6)` para nao errar no floor.
    static func fontSize(width: CGFloat, cols: Int) -> CGFloat? {
        guard cols > 0, width.isFinite, width > 0 else { return nil }
        let raw = (width * 10 / CGFloat(cols * 6)).rounded(.down)
        return min(max(raw, minPoints), maxPoints)
    }
}

/// TerminalView que avisa o tamanho (celulas + pixels) a cada layout.
final class PoppyTerminalView: TerminalView {
    var onLayout: ((Int, Int, Int, Int) -> Void)?
    /// Long-press: entrega o texto visivel da tela (copia por folha, sem selecao no terminal).
    var onLongPressText: ((String) -> Void)?
    /// Long-press parado = folha Copiar; long-press arrastando = setas (cursor).
    var onArrowBytes: (([UInt8]) -> Void)?
    /// Dois dedos para o lado: +1 proxima janela, -1 anterior (so foco local).
    var onWindowSwipe: ((Int) -> Void)?
    /// Pinca terminou: novo tamanho da fonte em pontos.
    var onFontSizeChange: ((CGFloat) -> Void)?
    private(set) var fontPoints: CGFloat = 14
    /// Colunas do PTY (visao de celular): com valor > 0 a fonte e calculada pela largura e a pinca fica desligada.
    var fitCols: Int = 0 {
        didSet { if fitCols != oldValue { setNeedsLayout() } }
    }
    private var copyPress: UILongPressGestureRecognizer?
    private var pinchBase: CGFloat = 14
    private var dragAnchor: CGPoint = .zero
    private var dragMoved = false
    private var gesturesInstalled = false
    static let minFont: CGFloat = 9
    static let maxFont: CGFloat = 24

    func applyFontSize(_ size: CGFloat) {
        let clamped = min(max(size.rounded(), Self.minFont), Self.maxFont)
        guard clamped != fontPoints else { return }
        fontPoints = clamped
        font = Theme.terminalFont(size: clamped)
    }

    /// Ajusta a fonte para caber `fitCols` colunas (recalculado a cada layout, inclusive ao girar).
    private func applyFit() {
        guard fitCols > 0 else { return }
        let usable = bounds.width - safeAreaInsets.left - safeAreaInsets.right
        guard let size = TerminalFit.fontSize(width: usable, cols: fitCols), size != fontPoints else { return }
        fontPoints = size
        font = Theme.terminalFont(size: size)
    }

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
        let t = getTerminal()
        switch g.state {
        case .began:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dragAnchor = g.location(in: self)
            dragMoved = false
        case .changed:
            guard t.cols > 0, t.rows > 0 else { return }
            let cellW = bounds.width / CGFloat(t.cols)
            let cellH = bounds.height / CGFloat(t.rows)
            let p = g.location(in: self)
            let dx = Int((p.x - dragAnchor.x) / cellW)
            let dy = Int((p.y - dragAnchor.y) / cellH)
            var out: [UInt8] = []
            if dx != 0, let k = (dx > 0 ? BarKey.right : BarKey.left).bytes() {
                for _ in 0..<min(abs(dx), 20) { out += k }
                dragAnchor.x += CGFloat(dx) * cellW
            }
            if dy != 0, let k = (dy > 0 ? BarKey.down : BarKey.up).bytes() {
                for _ in 0..<min(abs(dy), 20) { out += k }
                dragAnchor.y += CGFloat(dy) * cellH
            }
            if !out.isEmpty {
                dragMoved = true
                onArrowBytes?(out)
            }
        case .ended:
            if !dragMoved { onLongPressText?(visibleText()) }
        default:
            break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard fitCols == 0 else { return }
        switch g.state {
        case .began:
            pinchBase = fontPoints
        case .changed:
            applyFontSize(pinchBase * g.scale)
        case .ended, .cancelled:
            onFontSizeChange?(fontPoints)
        default:
            break
        }
    }

    @objc private func handleSwipe(_ g: UISwipeGestureRecognizer) {
        guard g.state == .ended else { return }
        onWindowSwipe?(g.direction == .left ? 1 : -1)
    }

    private func installExtraGestures() {
        guard !gesturesInstalled else { return }
        gesturesInstalled = true
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))
        for dir in [UISwipeGestureRecognizer.Direction.left, .right] {
            let s = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            s.direction = dir
            s.numberOfTouchesRequired = 2
            addGestureRecognizer(s)
        }
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
            if g === copyPress || g is UIPinchGestureRecognizer || g is UISwipeGestureRecognizer { continue }
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
        installExtraGestures()
        applyFit()
        let t = getTerminal()
        let scale = traitCollection.displayScale
        onLayout?(t.cols, t.rows, Int(bounds.width * scale), Int(bounds.height * scale))
    }
}

struct TerminalContainer: UIViewRepresentable {
    let connection: SipConnection
    var fontSize: CGFloat = 14
    /// Colunas do PTY quando a visao de celular esta ativa (0 = fonte da pessoa, como antes).
    var fitCols: Int = 0
    var snippets: [Snippet] = []
    var onCopyRequest: (String) -> Void = { _ in }
    var onWindowSwipe: (Int) -> Void = { _ in }
    var onFontSizeChange: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(connection: connection) }

    func makeUIView(context: Context) -> PoppyTerminalView {
        let coordinator = context.coordinator
        let view = PoppyTerminalView(frame: .zero)
        view.fitCols = fitCols
        if fitCols == 0 { view.applyFontSize(fontSize) }
        view.nativeBackgroundColor = Theme.background
        view.nativeForegroundColor = Theme.foreground
        view.terminalDelegate = coordinator

        let conn = connection
        view.keyboardDismissMode = .interactive
        let bar = KeyBarView(hideKeyboard: { [weak view] in _ = view?.resignFirstResponder() },
                             send: { bytes in conn.sendInput(bytes) })
        view.inputAccessoryView = bar
        coordinator.keyBar = bar
        bar.setSnippets(snippets)

        view.onArrowBytes = { bytes in conn.sendInput(bytes) }
        view.onWindowSwipe = onWindowSwipe
        view.onFontSizeChange = onFontSizeChange
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
        uiView.onWindowSwipe = onWindowSwipe
        uiView.onFontSizeChange = onFontSizeChange
        uiView.fitCols = fitCols
        if fitCols == 0 { uiView.applyFontSize(fontSize) }
        if context.coordinator.keyBar?.setSnippets(snippets) == true {
            uiView.reloadInputViews()
        }
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
