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

final class KeyBarView: UIView {
    private static let rowHeight: CGFloat = 44
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

        // Botao fixo (fora da rolagem) para esconder o teclado do iOS.
        let hide = SlopButton(type: .system)
        hide.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        hide.tintColor = Theme.text
        hide.backgroundColor = Theme.surface0
        hide.layer.cornerRadius = 6
        hide.accessibilityIdentifier = "key-hide-keyboard"
        hide.accessibilityLabel = "Esconder teclado"
        hide.translatesAutoresizingMaskIntoConstraints = false
        hide.addAction(UIAction { [weak self] _ in self?.hideKeyboard() }, for: .touchUpInside)
        keyRow.addSubview(hide)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: keyRow.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: hide.leadingAnchor, constant: -4),
            hide.trailingAnchor.constraint(equalTo: keyRow.trailingAnchor, constant: -8),
            hide.centerYAnchor.constraint(equalTo: keyRow.centerYAnchor),
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
            b.titleLabel?.font = Theme.terminalFont(size: 15)
            b.layer.cornerRadius = 6
            b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 11, bottom: 0, right: 11)
            b.accessibilityIdentifier = "key-\(key.rawValue)"
            b.addAction(UIAction { [weak self] _ in self?.tap(key) }, for: .touchUpInside)
            stack.addArrangedSubview(b)
            buttons[key] = b
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) nao usado") }

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
            b.titleLabel?.font = Theme.terminalFont(size: 14)
            b.setTitleColor(Theme.text, for: .normal)
            b.backgroundColor = Theme.surface1
            b.layer.cornerRadius = 6
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
                b.backgroundColor = Theme.surface0
                b.setTitleColor(Theme.text, for: .normal)
            case .once:
                b.backgroundColor = Theme.mauve
                b.setTitleColor(Theme.crust, for: .normal)
            case .locked:
                b.backgroundColor = Theme.peach
                b.setTitleColor(Theme.crust, for: .normal)
            }
        }
    }
}
