import SwiftUI
import SwiftTerm

/// TerminalView local (sem rede) que imprime ANSI colorido: prova SwiftTerm + fonte.
struct DemoTerminalView: UIViewRepresentable {
    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.font = Theme.terminalFont(size: 14)
        view.nativeBackgroundColor = Theme.background
        view.nativeForegroundColor = Theme.foreground
        view.feed(text: DemoTerminalView.demoText)
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    static let demoText: String = {
        let e = "\u{1B}["
        var s = ""
        s += "\(e)1;35mPoppyTerminal\(e)0m \(e)90m-- demo local\(e)0m\r\n"
        s += "\(e)32m\u{276F}\(e)0m echo \"ola, Gobby\"\r\n"
        s += "ola, Gobby\r\n"
        for (i, name) in ["red", "green", "yellow", "blue", "magenta", "cyan"].enumerated() {
            s += "\(e)\(31 + i)m\(name)\(e)0m "
        }
        s += "\r\n"
        for c in 0..<8 { s += "\(e)4\(c)m  \(e)0m" }
        s += "\r\n"
        s += "\(e)1mbold\(e)0m \(e)3mitalic\(e)0m \(e)4munderline\(e)0m\r\n"
        s += "Nerd Font: \u{F121} \u{F09B} \u{E725} \u{F015} \u{F0E7}\r\n"
        s += "\(e)38;2;203;166;247mmauve truecolor\(e)0m\r\n"
        s += "\(e)32m\u{276F}\(e)0m \(e)7m \(e)0m"
        return s
    }()
}
