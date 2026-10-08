import SwiftUI
import SwiftTerm
import PoppyKit

/// TerminalView que avisa o tamanho (celulas + pixels) a cada layout.
final class PoppyTerminalView: TerminalView {
    var onLayout: ((Int, Int, Int, Int) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        let t = getTerminal()
        let scale = traitCollection.displayScale
        onLayout?(t.cols, t.rows, Int(bounds.width * scale), Int(bounds.height * scale))
    }
}

struct TerminalContainer: UIViewRepresentable {
    let connection: SipConnection

    func makeCoordinator() -> Coordinator { Coordinator(connection: connection) }

    func makeUIView(context: Context) -> PoppyTerminalView {
        let coordinator = context.coordinator
        let view = PoppyTerminalView(frame: .zero)
        view.font = Theme.terminalFont(size: 14)
        view.nativeBackgroundColor = Theme.background
        view.nativeForegroundColor = Theme.foreground
        view.terminalDelegate = coordinator

        let conn = connection
        let bar = KeyBarView { bytes in conn.sendInput(bytes) }
        view.inputAccessoryView = bar
        coordinator.keyBar = bar

        view.onLayout = { cols, rows, w, h in
            conn.updateSize(cols: cols, rows: rows, widthPx: w, heightPx: h)
        }
        connection.onOutput = { [weak view] bytes in
            view?.feed(byteArray: bytes)
        }
        DispatchQueue.main.async { _ = view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: PoppyTerminalView, context: Context) {}

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
