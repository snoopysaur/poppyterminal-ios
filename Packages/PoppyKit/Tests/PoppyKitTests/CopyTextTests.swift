import Testing
@testable import PoppyKit

@Suite struct CopyTextTests {
    @Test func meioBlocoSomeELinhaVazia() {
        #expect(CopyText.clean("ola\n▀▀▀▀▀▀▀▀\n▄▄ ██ ░▒▓\nmundo") == "ola\n\nmundo")
    }

    @Test func molduraDeJanelaSome() {
        let r = CopyText.clean("│ texto aqui │\n┌──────┐\n└──────┘\n╭─╮ ╰─╯")
        #expect(r == " texto aqui")
    }

    @Test func powerlineENerdFontSomem() {
        #expect(CopyText.clean("\u{E0B0}\u{E0B6} main \u{E0B4}\u{F015} ~/src\u{E0A0}") == " main  ~/src")
        #expect(CopyText.clean("\u{E0B0}\u{E0B6}x\u{E0B4}") == "x")
        #expect(CopyText.clean("a\u{F0001}b") == "ab")
    }

    @Test func linhaSoDeSimbolosViraVazia() {
        #expect(CopyText.clean("a\n▀▀▀\n│\u{E0B0}│\n▀▀\nb") == "a\n\nb")
    }

    @Test func espacosNoFimDaLinha() {
        #expect(CopyText.clean("abc    \ndef \t \n") == "abc\ndef")
    }

    @Test func noMaximoUmaLinhaEmBranco() {
        #expect(CopyText.clean("a\n\n\n\n\nb") == "a\n\nb")
        #expect(CopyText.clean("\n\n a\n") == " a")
    }

    @Test func textoNormalIntactoComAcentos() {
        let t = "Ação: não há coração, é ótimo — ÀÉÎÕÜ ç\n  indentado\n$ ls -la | grep 'x'"
        #expect(CopyText.clean(t) == t)
    }
}
