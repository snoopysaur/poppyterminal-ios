import XCTest
import UIKit
@testable import PoppyTerminal

/// Contraste WCAG por par de cores do tema ativo (Guild) e das 16 cores do terminal.
/// Texto normal >= 4,5:1; elementos graficos (icones, bordas) >= 3:1.
final class ThemeContrastTests: XCTestCase {
    typealias T = ThemeTokens

    static func luminance(_ hex: UInt32) -> Double {
        func lin(_ c: UInt32) -> Double {
            let v = Double(c) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin((hex >> 16) & 0xFF) + 0.7152 * lin((hex >> 8) & 0xFF) + 0.0722 * lin(hex & 0xFF)
    }

    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    struct Pair { let name: String; let fg: UInt32; let bg: UInt32; let min: Double }

    /// Devolve as descricoes dos pares que NAO atingem o minimo.
    static func failures(_ pairs: [Pair]) -> [String] {
        pairs.compactMap { p in
            let r = ratio(p.fg, p.bg)
            return r >= p.min ? nil : "\(p.name): \(String(format: "%.2f", r)) < \(p.min)"
        }
    }

    static var pairs: [Pair] {
        [
            Pair(name: "texto / fundo", fg: T.text, bg: T.base, min: 4.5),
            Pair(name: "texto / cartao", fg: T.text, bg: T.surface, min: 4.5),
            Pair(name: "secundario / fundo", fg: T.textSecondary, bg: T.base, min: 4.5),
            Pair(name: "secundario / cartao", fg: T.textSecondary, bg: T.surface, min: 4.5),
            Pair(name: "secundario / cartao alerta", fg: T.textSecondary, bg: T.tintAlert, min: 4.5),
            Pair(name: "texto do botao / acento", fg: T.onAccent, bg: T.accent, min: 4.5),
            Pair(name: "acento / fundo", fg: T.accent, bg: T.base, min: 3),
            Pair(name: "acento / cartao", fg: T.accent, bg: T.surface, min: 3),
            Pair(name: "precisa de voce / fundo", fg: T.peach, bg: T.base, min: 3),
            Pair(name: "erro / fundo", fg: T.red, bg: T.base, min: 3),
            Pair(name: "trabalhando / fundo", fg: T.blue, bg: T.base, min: 3),
            Pair(name: "terminou / fundo", fg: T.green, bg: T.base, min: 3),
            Pair(name: "ocioso (so icone) / fundo", fg: T.idle, bg: T.base, min: 3),
            Pair(name: "texto / terminal", fg: T.text, bg: T.crust, min: 4.5),
            Pair(name: "secundario / terminal", fg: T.textSecondary, bg: T.crust, min: 4.5),
            Pair(name: "cursor ouro / terminal", fg: T.accent, bg: T.crust, min: 3),
            Pair(name: "texto / selecao do terminal", fg: T.text, bg: T.terminalSelection, min: 4.5),
            Pair(name: "texto / cartao alerta", fg: T.text, bg: T.tintAlert, min: 4.5),
            Pair(name: "texto / cartao perigo", fg: T.text, bg: T.tintDanger, min: 4.5),
            Pair(name: "texto / bloco de risco", fg: T.text, bg: T.riskBlock, min: 4.5),
            Pair(name: "texto / botao aprovar mesmo assim", fg: T.text, bg: T.riskButton, min: 4.5),
            Pair(name: "icone pessego / cartao alerta", fg: T.peach, bg: T.tintAlert, min: 3),
            Pair(name: "icone vermelho / cartao perigo", fg: T.red, bg: T.tintDanger, min: 3),
            Pair(name: "borda vermelha / bloco de risco", fg: T.red, bg: T.riskBlock, min: 3),
            Pair(name: "texto / selo", fg: T.text, bg: T.seal, min: 4.5),
            Pair(name: "icone pessego / selo", fg: T.peach, bg: T.seal, min: 3),
            Pair(name: "icone azul / selo", fg: T.blue, bg: T.seal, min: 3),
            Pair(name: "icone verde / selo", fg: T.green, bg: T.seal, min: 3),
            Pair(name: "icone vermelho / selo", fg: T.red, bg: T.seal, min: 3),
            Pair(name: "icone ocioso / selo", fg: T.idle, bg: T.seal, min: 3),
            Pair(name: "contador vermelho (texto escuro)", fg: T.onBadge, bg: T.red, min: 4.5),
            Pair(name: "aba nao selecionada / barra", fg: T.textSecondary, bg: T.mantle, min: 4.5),
            Pair(name: "aba selecionada / barra", fg: T.accent, bg: T.mantle, min: 3),
            Pair(name: "texto / barra", fg: T.text, bg: T.mantle, min: 4.5),
            Pair(name: "seletor: texto / fundo", fg: T.text, bg: T.surfaceStrong, min: 4.5),
            Pair(name: "botao desabilitado: texto / fundo", fg: T.textSecondary, bg: T.surfaceStrong, min: 4.5),
            Pair(name: "borda bronze / fundo", fg: T.border, bg: T.base, min: 3),
            Pair(name: "borda bronze / cartao", fg: T.border, bg: T.surface, min: 3),
            Pair(name: "ouro velho / fundo", fg: T.borderStrong, bg: T.base, min: 3),
            Pair(name: "ouro velho / cartao", fg: T.borderStrong, bg: T.surface, min: 3),
            Pair(name: "texto do botao / bisel", fg: T.onAccent, bg: T.borderStrong, min: 3),
            // Onda 2 (telas): molduras e blocos novos
            Pair(name: "texto / bloco de comando (selo)", fg: T.text, bg: T.seal, min: 4.5),
            Pair(name: "secundario / selo", fg: T.textSecondary, bg: T.seal, min: 4.5),
            Pair(name: "secundario / cartao perigo", fg: T.textSecondary, bg: T.tintDanger, min: 4.5),
            Pair(name: "texto / barra de decisao", fg: T.text, bg: T.mantle, min: 4.5),
            Pair(name: "borda ouro (balao dele) / selo", fg: T.accent, bg: T.seal, min: 3),
            Pair(name: "borda bronze (balao do agente) / cartao", fg: T.border, bg: T.surface, min: 3),
            Pair(name: "borda bronze / selo", fg: T.border, bg: T.seal, min: 3),
            Pair(name: "fio interno ouro velho / cartao alerta", fg: T.borderStrong, bg: T.tintAlert, min: 3),
            Pair(name: "fio interno ouro velho / cartao perigo", fg: T.borderStrong, bg: T.tintDanger, min: 3),
            Pair(name: "borda pessego / fundo", fg: T.peach, bg: T.base, min: 3),
            Pair(name: "borda vermelha / fundo", fg: T.red, bg: T.base, min: 3),
            Pair(name: "linha bronze / barra", fg: T.border, bg: T.mantle, min: 3),
            Pair(name: "texto / botao neutro", fg: T.text, bg: T.surfaceStrong, min: 4.5),
            Pair(name: "borda ouro velho / botao neutro", fg: T.borderStrong, bg: T.surfaceStrong, min: 3),
            Pair(name: "borda ouro velho / tecla do terminal", fg: T.borderStrong, bg: T.surfaceStrong, min: 3),
            Pair(name: "teclas: texto do modificador ativo / acento", fg: T.onAccent, bg: T.accent, min: 4.5),
            Pair(name: "teclas: texto do modificador travado / pessego", fg: T.onAccent, bg: T.peach, min: 4.5),
            Pair(name: "teclas: texto / tecla", fg: T.text, bg: T.surfaceStrong, min: 4.5),
        ]
    }

    func testTodosOsParesDeCor() {
        let fails = Self.failures(Self.pairs)
        XCTAssertTrue(fails.isEmpty, "Pares abaixo do minimo:\n" + fails.joined(separator: "\n"))
    }

    /// As 16 cores do terminal sobre o fundo escuro: >= 4,5 (a cor 0 fica fora por ser "preto").
    func testDezesseisCoresDoTerminal() {
        XCTAssertEqual(T.terminalAnsi.count, 16)
        var pairs: [Pair] = []
        for (i, cor) in T.terminalAnsi.enumerated() where i > 0 {
            pairs.append(Pair(name: "ansi \(i)", fg: cor, bg: T.crust, min: 4.5))
        }
        let fails = Self.failures(pairs)
        XCTAssertTrue(fails.isEmpty, "Cores do terminal abaixo de 4,5:\n" + fails.joined(separator: "\n"))
    }

    /// As 16 cores sobre a selecao do terminal (ouro escuro): texto comum e as 7 brilhantes legiveis (>= 3).
    func testCoresDoTerminalSobreASelecao() {
        var pairs: [Pair] = [Pair(name: "texto / selecao", fg: T.text, bg: T.terminalSelection, min: 4.5)]
        for (i, cor) in T.terminalAnsi.enumerated() where i >= 9 {
            pairs.append(Pair(name: "ansi \(i) / selecao", fg: cor, bg: T.terminalSelection, min: 3))
        }
        let fails = Self.failures(pairs)
        XCTAssertTrue(fails.isEmpty, "Cores sobre a selecao:
" + fails.joined(separator: "
"))
    }

    /// O cursor (ouro) e o texto dentro do cursor de bloco (crust) se leem sobre o fundo do terminal.
    func testCursorDoTerminal() {
        let pairs = [
            Pair(name: "cursor / fundo", fg: T.accent, bg: T.crust, min: 3),
            Pair(name: "texto no cursor de bloco / cursor", fg: T.crust, bg: T.accent, min: 4.5),
        ]
        let fails = Self.failures(pairs)
        XCTAssertTrue(fails.isEmpty, "Cursor:
" + fails.joined(separator: "
"))
    }

    /// Controle negativo: o verificador tem que acusar pares ruins (senao o teste acima nao prova nada).
    func testControleNegativoAcusaParRuim() {
        let ruins = [
            Pair(name: "texto sobre ele mesmo", fg: T.text, bg: T.text, min: 4.5),
            Pair(name: "ansi 0 sobre o fundo", fg: T.terminalAnsi[0], bg: T.crust, min: 4.5),
            Pair(name: "texto claro sobre vermelho", fg: T.text, bg: T.red, min: 4.5),
        ]
        XCTAssertEqual(Self.failures(ruins).count, 3)
    }

    /// `ThemeTokens.swift` gerado tem que bater com `design/tokens.json` (o `--check` do gerador tambem confere).
    func testTokensJsonBateComOSwiftGerado() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("design/tokens.json")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("design/tokens.json fora do alcance do simulador") }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["ativo"] as? String, "guild")
        let temas = try XCTUnwrap(json["temas"] as? [String: Any])
        let guild = try XCTUnwrap(temas["guild"] as? [String: Any])
        let cores = try XCTUnwrap(guild["cores"] as? [String: String])
        let esperado: [String: UInt32] = [
            "base": T.base, "mantle": T.mantle, "crust": T.crust, "surface": T.surface,
            "surfaceStrong": T.surfaceStrong, "text": T.text, "textSecondary": T.textSecondary,
            "accent": T.accent, "onAccent": T.onAccent, "border": T.border, "borderStrong": T.borderStrong,
            "peach": T.peach, "red": T.red, "blue": T.blue, "green": T.green, "lavender": T.lavender,
            "idle": T.idle, "gameMode": T.gameMode,
        ]
        for (nome, valor) in esperado {
            XCTAssertEqual(UInt32(cores[nome] ?? "", radix: 16), valor, "token \(nome) diverge do JSON")
        }
        let ansi = try XCTUnwrap(guild["ansi"] as? [String]).compactMap { UInt32($0, radix: 16) }
        XCTAssertEqual(ansi, Array(T.terminalAnsi.prefix(8)))
    }

    func testTemaAtivoEGuild() {
        XCTAssertEqual(T.accent, 0xE8B04A)
        XCTAssertEqual(T.base, 0x1B1612)
    }

    func testFontePixelRegistrada() {
        XCTAssertNotNil(UIFont(name: GuildType.pixelName, size: 12), "UIAppFonts nao registrou a Silkscreen")
    }
}
