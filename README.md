# PoppyTerminal (iOS)

App nativo de terminal para iPhone (SwiftUI + SwiftTerm), no visual Catppuccin Mocha com JetBrains Mono Nerd Font.

Estado: **F0 (pipeline)** - esqueleto que prova build, testes e IPA no GitHub Actions; terminal local de demonstracao. Conexao remota fica para a F1.

- iOS 17+, iPhone, Swift 6
- `Packages/PoppyKit`: codec do protocolo de quadros (puro Swift, `swift test`)
- Projeto gerado por XcodeGen: `xcodegen generate`
- CI: `.github/workflows/ios.yml` (IPA sem assinatura como artefato; Release em tags `v*`)

Licenca MIT. Terceiros em `THIRD_PARTY_LICENSES.md`.
