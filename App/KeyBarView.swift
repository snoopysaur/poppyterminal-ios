import UIKit
import PoppyKit

/// Barra de teclas acima do teclado: esc, tab, ctrl/alt grudentes, alt+esc,
/// setas, | ~ / e o lider do tuios.
final class KeyBarView: UIView {
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
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = Theme.mantle

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        // Botao fixo (fora da rolagem) para esconder o teclado do iOS.
        let hide = UIButton(type: .system)
        hide.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        hide.tintColor = Theme.text
        hide.backgroundColor = Theme.surface0
        hide.layer.cornerRadius = 6
        hide.accessibilityIdentifier = "key-hide-keyboard"
        hide.accessibilityLabel = "Esconder teclado"
        hide.translatesAutoresizingMaskIntoConstraints = false
        hide.addAction(UIAction { [weak self] _ in self?.hideKeyboard() }, for: .touchUpInside)
        addSubview(hide)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: hide.leadingAnchor, constant: -4),
            hide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            hide.centerYAnchor.constraint(equalTo: centerYAnchor),
            hide.widthAnchor.constraint(equalToConstant: 44),
            hide.heightAnchor.constraint(equalToConstant: 34),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -5),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -10),
        ])

        for key in BarKey.allCases {
            let b = UIButton(type: .system)
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

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }

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
