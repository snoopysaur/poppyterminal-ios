# Regras do projeto

- Alvo: iOS 17+, iPhone (device family 1), Swift 6 (cair para Swift 5 so se uma dependencia exigir, e anotar aqui).
- Repo PUBLICO: NENHUM segredo, token, e-mail ou URL/nome da tailnet no repositorio. Enderecos de servidor entram em runtime (Keychain/ajustes), nunca no codigo.
- Cores e fonte somente via `App/Theme.swift` (constantes Catppuccin Mocha).
- Nada de codigo GPL; so dependencias MIT/BSD/Apache/OFL.
- Sem NSAllowsArbitraryLoads.
- `project.yml` e a fonte de verdade; `.xcodeproj` e `Info.plist` sao gerados e ignorados pelo git.
- Sem Mac local: validar via GitHub Actions (`gh run watch`).
- SwiftTerm fixado em versao exata (ver project.yml).
