import Foundation

/// Limpeza do texto da folha "Copiar": tira ruido grafico do terminal
/// (meio-bloco, molduras, powerline/Nerd Font) e arruma espacos e linhas vazias.
public enum CopyText {
    /// Caracteres que so servem de desenho: block elements, box drawing e uso privado (PUA).
    static func isNoise(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x2500...0x257F,      // box drawing
             0x2580...0x259F,      // block elements
             0xE000...0xF8FF,      // PUA (powerline, Nerd Font)
             0xF0000...0xFFFFD,    // PUA suplementar-A (Nerd Font v3)
             0x100000...0x10FFFD:  // PUA suplementar-B
            return true
        default:
            return false
        }
    }

    public static func clean(_ raw: String) -> String {
        var out: [String] = []
        var lastBlank = true // descarta linhas vazias no inicio
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            var scalars = String.UnicodeScalarView()
            for s in line.unicodeScalars where !isNoise(s) { scalars.append(s) }
            var text = String(scalars)
            while let last = text.last, last == " " || last == "\t" || last == "\u{00A0}" {
                text.removeLast()
            }
            if text.isEmpty {
                if lastBlank { continue }
                lastBlank = true
            } else {
                lastBlank = false
            }
            out.append(text)
        }
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n")
    }
}
