import Foundation

/// Modificadores "grudentes" da barra de teclas: toque liga para uma tecla,
/// segundo toque trava, terceiro desliga.
public struct StickyModifiers: Sendable, Equatable {
    public enum State: Sendable, Equatable { case off, once, locked }

    public var ctrl: State = .off
    public var alt: State = .off

    public init() {}

    public static func next(_ s: State) -> State {
        switch s {
        case .off: return .once
        case .once: return .locked
        case .locked: return .off
        }
    }

    public mutating func tapCtrl() { ctrl = Self.next(ctrl) }
    public mutating func tapAlt() { alt = Self.next(alt) }

    /// Aplica ctrl/alt aos bytes que vao ao servidor e consome os "once".
    public mutating func apply(to bytes: [UInt8]) -> [UInt8] {
        guard !bytes.isEmpty else { return bytes }
        var out = bytes
        if ctrl != .off, out.count == 1, let c = Self.controlByte(out[0]) {
            out = [c]
        }
        if alt != .off {
            out.insert(0x1B, at: 0)
        }
        if ctrl == .once { ctrl = .off }
        if alt == .once { alt = .off }
        return out
    }

    /// Ctrl+letra etc. nil se nao ha equivalente.
    public static func controlByte(_ b: UInt8) -> UInt8? {
        switch b {
        case 0x61...0x7A: return b - 0x60          // a-z
        case 0x40...0x5F: return b - 0x40          // @ A-Z [ \ ] ^ _
        case 0x20: return 0x00                     // espaco
        case 0x3F: return 0x7F                     // ?
        default: return nil
        }
    }
}

/// Teclas da barra. `bytes` e o que vai ao terminal remoto.
public enum BarKey: String, CaseIterable, Sendable {
    case esc, tab, ctrl, alt, altEsc, up, down, left, right, pipe, tilde, slash, leader

    public var label: String {
        switch self {
        case .esc: return "esc"
        case .tab: return "tab"
        case .ctrl: return "ctrl"
        case .alt: return "alt"
        case .altEsc: return "alt+esc"
        case .up: return "\u{2191}"
        case .down: return "\u{2193}"
        case .left: return "\u{2190}"
        case .right: return "\u{2192}"
        case .pipe: return "|"
        case .tilde: return "~"
        case .slash: return "/"
        case .leader: return "lider"
        }
    }

    /// Bytes enviados; nil para modificadores (ctrl/alt) que so mudam estado.
    public func bytes(leader: [UInt8] = BarKey.defaultLeader) -> [UInt8]? {
        switch self {
        case .esc: return [0x1B]
        case .tab: return [0x09]
        case .altEsc: return [0x1B, 0x1B]
        case .up: return [0x1B, 0x5B, 0x41]
        case .down: return [0x1B, 0x5B, 0x42]
        case .right: return [0x1B, 0x5B, 0x43]
        case .left: return [0x1B, 0x5B, 0x44]
        case .pipe: return [0x7C]
        case .tilde: return [0x7E]
        case .slash: return [0x2F]
        case .leader: return leader
        case .ctrl, .alt: return nil
        }
    }

    /// Lider padrao do tuios do Gobby: ctrl+\ (0x1C).
    public static let defaultLeader: [UInt8] = [0x1C]
}
