# Regras do projeto

- Alvo: iOS 17+, iPhone (device family 1), Swift 6 (cair para Swift 5 so se uma dependencia exigir, e anotar aqui).
- Repo PUBLICO: NENHUM segredo, token, e-mail ou URL/nome da tailnet no repositorio. Enderecos de servidor entram em runtime (Keychain/ajustes), nunca no codigo.
- Cores somente por tokens do tema ativo: `design/tokens.json` -> `scripts/gen_theme.py` -> `App/Design/ThemeTokens.swift` (gerado, nao editar a mao) -> `App/Theme.swift` (nomes de papel). Tema ativo: Guild (acento = ouro); Mocha fica como reserva no JSON. Proibido `Color(red:)`/`UIColor(red:)` em tela. Conferir com `python -I scripts/gen_theme.py --check`.
- Fonte de pixel (Pixelify Sans Bold, OFL; a Silkscreen saiu em 18/10/2026 por N/M parecerem H) so em titulo de tela, cabecalho de secao, rotulo de aba e rotulo de botao (botao em pixel foi decisao do Gobby em 17/10/2026); volta para SF em tamanhos de acessibilidade e na paisagem compacta (`App/Design/GuildType.swift`). Comando, risco e texto longo ficam em SF ou JetBrains Mono, nunca em pixel.
- Nada de codigo GPL; so dependencias MIT/BSD/Apache/OFL.
- Sem NSAllowsArbitraryLoads.
- `project.yml` e a fonte de verdade; `.xcodeproj` e `Info.plist` sao gerados e ignorados pelo git.
- Sem Mac local: validar via GitHub Actions (`gh run watch`).
- SwiftTerm fixado em versao exata (ver project.yml).
