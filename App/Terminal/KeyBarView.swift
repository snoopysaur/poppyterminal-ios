import UIKit
import PoppyKit

/// Barra de teclas acima do teclado: esc, tab, ctrl/alt grudentes, alt+esc,
/// setas, | ~ / e o lider do tuios. Acima, a fileira de snippets (toque envia).
/// Botao visualmente de 34 pt com area de toque de pelo menos 44 pt de altura.
private final class SlopButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let dy = max(0, (44 - bounds.height) / 2)
        return bounds.insetBy(dx: -4, dy: -dy).contains(point)
    }
}

/// Esmaecido da borda direita da barra de teclas: degrade do fundo transparente para o fundo da
/// barra (sem desfoque), para ficar claro que a barra rola e a ultima tecla nao esta "cortada por erro".
final class EdgeFadeView: UIView {
    static let width: CGFloat = 28
    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        gradient.colors = [Theme.mantle.withAlphaComponent(0).cgColor, Theme.mantle.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) nao usado") }

    /// Cores do degrade (inicio transparente, fim opaco), para os testes.
    var gradientColors: [CGColor] { (gradient.colors as? [CGColor]) ?? [] }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

final class KeyBarView: UIView, UIScrollViewDelegate {
    private static let rowHeight: CGFloat = 44
    /// Esmaecido da borda direita (some quando a barra ja foi rolada ate o fim).
    let fadeEdge = EdgeFadeView()
    private weak var keyScroll: UIScrollView?
    /// Toque no microfone: abre o ditado (o texto e revisado antes de entrar no terminal).
    var onDictate: () -> Void = {}
    private let keyRow = UIView()
    private let snippetScroll = UIScrollView()
    private let snippetStack = UIStackView()
    private var snippetHeight: NSLayoutConstraint?
    private(set) var snippets: [Snippet] = []

    private(set) var modifiers = StickyModifiers()
    private var buttons: [BarKey: UIButton] = [:]
    private let send: ([UInt8]) -> Void
    private let leader: [UInt8]
    private let hideKeyboard: () -> Void

    init(leader: [UInt8] = BarKey.defaultLeader,
         hideKeyboard: @escaping () -> Void = {},
         send: @escaping ([UInt8]) -> Void) {
        self.send = send
        self.hideKeyboard = hideKeyboard
        self.leader = leader
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.rowHeight))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = Theme.mantle

        snippetScroll.showsHorizontalScrollIndicator = false
        snippetScroll.translatesAutoresizingMaskIntoConstraints = false
        snippetStack.axis = .horizontal
        snippetStack.spacing = 6
        snippetStack.translatesAutoresizingMaskIntoConstraints = false
        snippetScroll.addSubview(snippetStack)
        addSubview(snippetScroll)
        keyRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyRow)
        let heightC = snippetScroll.heightAnchor.constraint(equalToConstant: 0)
        snippetHeight = heightC
        NSLayoutConstraint.activate([
            snippetScroll.topAnchor.constraint(equalTo: topAnchor),
            snippetScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            snippetScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightC,
            keyRow.topAnchor.constraint(equalTo: snippetScroll.bottomAnchor),
            keyRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            keyRow.bottomAnchor.constraint(equalTo: bottomAnchor),
            keyRow.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            snippetStack.leadingAnchor.constraint(equalTo: snippetScroll.contentLayoutGuide.leadingAnchor, constant: 8),
            snippetStack.trailingAnchor.constraint(equalTo: snippetScroll.contentLayoutGuide.trailingAnchor, constant: -8),
            snippetStack.topAnchor.constraint(equalTo: snippetScroll.contentLayoutGuide.topAnchor, constant: 5),
            snippetStack.bottomAnchor.constraint(equalTo: snippetScroll.contentLayoutGuide.bottomAnchor, constant: -5),
            snippetStack.heightAnchor.constraint(equalTo: snippetScroll.frameLayoutGuide.heightAnchor, constant: -10),
        ])

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        keyRow.addSubview(scroll)

        // Botao fixo (fora da rolagem) para esconder o teclado do iOS. Fica numa caixa propria,
        // com fundo e fio separador: as teclas que rolam por tras nao parecem cortadas por erro.
        let hideBox = UIView()
        hideBox.backgroundColor = Theme.mantle
        hideBox.translatesAutoresizingMaskIntoConstraints = false
        keyRow.addSubview(hideBox)
        let separator = UIView()
        separator.backgroundColor = Theme.border
        separator.translatesAutoresizingMaskIntoConstraints = false
        hideBox.addSubview(separator)
        let hide = SlopButton(type: .system)
        hide.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        hide.tintColor = Theme.text
        hide.backgroundColor = Theme.surface1
        Self.frameStyle(hide)
        hide.accessibilityIdentifier = "key-hide-keyboard"
        hide.accessibilityLabel = "Esconder teclado"
        hide.translatesAutoresizingMaskIntoConstraints = false
        hide.addAction(UIAction { [weak self] _ in self?.hideKeyboard() }, for: .touchUpInside)
        hideBox.addSubview(hide)

        // Microfone fixo ao lado do botao de esconder o teclado: ditado para o terminal.
        let mic = SlopButton(type: .system)
        mic.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        mic.tintColor = Theme.text
        mic.backgroundColor = Theme.surface1
        Self.frameStyle(mic)
        mic.accessibilityIdentifier = "key-dictate"
        mic.accessibilityLabel = "Ditar por voz"
        mic.translatesAutoresizingMaskIntoConstraints = false
        mic.addAction(UIAction { [weak self] _ in self?.onDictate() }, for: .touchUpInside)
        hideBox.addSubview(mic)

        fadeEdge.translatesAutoresizingMaskIntoConstraints = false
        keyRow.addSubview(fadeEdge)
        scroll.delegate = self
        keyScroll = scroll

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: keyRow.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: hideBox.leadingAnchor),
            hideBox.trailingAnchor.constraint(equalTo: keyRow.trailingAnchor),
            hideBox.topAnchor.constraint(equalTo: keyRow.topAnchor),
            hideBox.bottomAnchor.constraint(equalTo: keyRow.bottomAnchor),
            hideBox.widthAnchor.constraint(equalToConstant: 110),
            mic.trailingAnchor.constraint(equalTo: hide.leadingAnchor, constant: -6),
            mic.centerYAnchor.constraint(equalTo: hideBox.centerYAnchor),
            mic.widthAnchor.constraint(equalToConstant: 44),
            mic.heightAnchor.constraint(equalToConstant: 34),
            fadeEdge.trailingAnchor.constraint(equalTo: hideBox.leadingAnchor),
            fadeEdge.topAnchor.constraint(equalTo: keyRow.topAnchor),
            fadeEdge.bottomAnchor.constraint(equalTo: keyRow.bottomAnchor),
            fadeEdge.widthAnchor.constraint(equalToConstant: EdgeFadeView.width),
            separator.leadingAnchor.constraint(equalTo: hideBox.leadingAnchor),
            separator.topAnchor.constraint(equalTo: hideBox.topAnchor, constant: 5),
            separator.bottomAnchor.constraint(equalTo: hideBox.bottomAnchor, constant: -5),
            separator.widthAnchor.constraint(equalToConstant: 1),
            hide.trailingAnchor.constraint(equalTo: hideBox.trailingAnchor, constant: -8),
            hide.centerYAnchor.constraint(equalTo: hideBox.centerYAnchor),
            hide.widthAnchor.constraint(equalToConstant: 44),
            hide.heightAnchor.constraint(equalToConstant: 34),
            scroll.topAnchor.constraint(equalTo: keyRow.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: keyRow.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -5),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -10),
        ])

        for key in BarKey.allCases {
            let b = SlopButton(type: .system)
            b.setTitle(key.label, for: .normal)
            b.titleLabel?.font = Self.scaled(Theme.terminalFont(size: 15))
            b.titleLabel?.adjustsFontForContentSizeCategory = true
            Self.frameStyle(b)
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 11, bottom: 0, right: 11)
            b.accessibilityIdentifier = "key-\(key.rawValue)"
            b.addAction(UIAction { [weak self] _ in self?.tap(key) }, for: .touchUpInside)
            stack.addArrangedSubview(b)
            buttons[key] = b
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) nao usado") }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateFade() }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFade()
        // O tamanho do conteudo da rolagem so fica pronto depois deste layout.
        DispatchQueue.main.async { [weak self] in self?.updateFade() }
    }

    /// Mostra o esmaecido enquanto ainda ha teclas escondidas a direita.
    private func updateFade() {
        guard let scroll = keyScroll else { return }
        let hiddenRight = scroll.contentSize.width - (scroll.contentOffset.x + scroll.bounds.width)
        fadeEdge.alpha = hiddenRight > 1 || scroll.contentSize.width == 0 ? 1 : 0
    }

    /// A letra das teclas acompanha o tamanho de texto do iPhone (ate 22 pt, para caber nos 44 pt da fileira).
    private static func scaled(_ font: UIFont) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: font, maximumPointSize: 22)
    }

    /// Canto reto e fio bronze: o mesmo vocabulario da moldura Guild, em UIKit.
    private static func frameStyle(_ b: UIView) {
        b.layer.cornerRadius = 0
        b.layer.borderWidth = 1
        b.layer.borderColor = Theme.borderStrong.cgColor
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.rowHeight + (snippets.isEmpty ? 0 : Self.rowHeight))
    }

    /// Atualiza a fileira de snippets. Devolve true se a altura mudou
    /// (quem chama faz `reloadInputViews()`).
    @discardableResult
    func setSnippets(_ list: [Snippet]) -> Bool {
        guard list != snippets else { return false }
        let hadRow = !snippets.isEmpty
        snippets = list
        snippetStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, sn) in list.enumerated() {
            let b = SlopButton(type: .system)
            b.setTitle(sn.title, for: .normal)
            b.titleLabel?.font = Self.scaled(Theme.terminalFont(size: 14))
            b.titleLabel?.adjustsFontForContentSizeCategory = true
            b.setTitleColor(Theme.text, for: .normal)
            b.backgroundColor = Theme.surface1
            Self.frameStyle(b)
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 11, bottom: 0, right: 11)
            b.accessibilityIdentifier = "snippet-\(i)"
            b.accessibilityLabel = "Snippet \(sn.title)"
            b.addAction(UIAction { [weak self] _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self?.send(sn.payload)
            }, for: .touchUpInside)
            snippetStack.addArrangedSubview(b)
        }
        snippetHeight?.constant = list.isEmpty ? 0 : Self.rowHeight
        let changed = hadRow != !list.isEmpty
        if changed {
            frame.size.height = intrinsicContentSize.height
            invalidateIntrinsicContentSize()
        }
        return changed
    }

    /// Passa os bytes digitados no teclado de software pelos modificadores grudentes.
    func transform(_ bytes: [UInt8]) -> [UInt8] {
        let out = modifiers.apply(to: bytes)
        refresh()
        return out
    }

    private func tap(_ key: BarKey) {
        switch key {
        case .ctrl:
            modifiers.tapCtrl()
        case .alt:
            modifiers.tapAlt()
        case .leader, .altEsc:
            if let b = key.bytes(leader: leader) { send(b) }
        default:
            if let b = key.bytes(leader: leader) { send(modifiers.apply(to: b)) }
        }
        refresh()
    }

    private func refresh() {
        for (key, b) in buttons {
            let state: StickyModifiers.State
            switch key {
            case .ctrl: state = modifiers.ctrl
            case .alt: state = modifiers.alt
            default: state = .off
            }
            switch state {
            case .off:
                b.backgroundColor = Theme.surface1
                b.setTitleColor(Theme.text, for: .normal)
            case .once:
                b.backgroundColor = Theme.accent
                b.setTitleColor(Theme.onAccent, for: .normal)
            case .locked:
                b.backgroundColor = Theme.peach
                b.setTitleColor(Theme.onAccent, for: .normal)
            }
        }
    }
}
