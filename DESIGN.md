# Design

Modo: Operate. Dials: variância 2/10, movimento 3/10, densidade média. Mockup de referência: `notes/estudos/poppyterminal-v020-mockup.html` (fora do repo, no workspace do Gobby). Código: `App/Theme.swift`, `App/Design/`.

## Cor (identidade Guild, so escuro)
Fonte unica: `design/tokens.json` (Guild ativo; Catppuccin Mocha como reserva). O gerador `scripts/gen_theme.py` escreve `App/Design/ThemeTokens.swift`; `Theme.Palette` so da nomes de papel. Nada de cor crua em tela.
| Papel | Token SwiftUI | Valor | Contraste |
|---|---|---|---|
| Fundo | `Palette.base` | #1B1612 | |
| Barras | `.mantle` | #15110D | |
| Cartao/lista | `.surface` | #2A2119 | |
| Divisor/botao neutro | `.surfaceStrong` | #3A2D20 | |
| Terminal/comando/selo | `.sunken` (crust) | #0E0B08 | |
| Texto | `.text` | #F3E6CC | 14,5 base / 12,8 cartao |
| Texto secundario | `.textSecondary` | #C7B596 | 9,0 base / 7,9 cartao |
| Acento unico (ouro) | `.accent` | #E8B04A | 9,2 base; texto sobre ele = `.onAccent` #1B1612 (9,2) |
| Moldura interna (bronze) / externa (ouro velho) | `.border` / `.borderStrong` | #9A6B2F / #C8923F | 3,9 / 6,5 sobre a base |

Estados (`AgentTone`, tabela unica do app e da mesa): precisa de voce = pessego #F29A4B; erro/risco = vermelho #E5575B (so icone e borda); trabalhando = azul #7FB2E5; terminou = verde #93C96B; ocioso = #8C7B66 (4,4: so icone/contorno, nunca texto). Texto de selo e sempre `.text`; a cor vai no simbolo e no fio da moldura. Cada estado tem simbolo + rotulo. Contador vermelho leva texto escuro (claro daria 2,9).
Regra: o acento e o ouro; estado nao vira enfeite (pessego = "precisa de voce", nunca decoracao). Contraste conferido por `Tests/ThemeContrastTests` (pares e as 16 cores do terminal).

## Tipografia
SF Pro com estilos do sistema (Dynamic Type) em corpo, avisos e risco. JetBrains Mono Nerd (`Theme.fontRegular`) so para terminal, comandos e caminhos. Silkscreen Bold (fonte de pixel, OFL) so em titulo de tela, cabecalho de secao, rotulo de aba e rotulo de botao (botao em pixel: decisao do Gobby, 17/10/2026, contra a recomendacao); `GuildType`/`.guildText(_:)` trocam para SF em AX1 ou maior e na paisagem compacta. Texto em caixa normal no codigo (a fonte ja desenha maiusculas; o VoiceOver le como palavra). Pixel nunca em comando, risco ou texto longo.

## Moldura
`GuildFrame` (SwiftUI): canto reto, 1 pt escuro + 2 pt (ouro velho ou cor do estado) + 1 pt bronze interno; sem sombra, desfoque nem material; decorativa (escondida do VoiceOver). Tipos: painel, alerta, perigo, selo, botao (ouro com bisel), botao neutro. Alvo de toque >= 44 pt.

## Componentes (`App/Design/`)
- `AgentTone`: enum de estados (cor, símbolo, rótulo, prioridade, haptic).
- `StatusPill(tone, text?, count?)`: selo escuro quadrado informativo; ocioso com ícone cinza e rótulo secundário.
- `AgentStateBadge(tone, count?, haptics:)`: selo quadrado, 32 pt escalável, contador opcional.
- `PoppyView(mood, size:, label:)`: pixel art sem interpolação, 2 quadros a 2 Hz, parada com Reduce Motion; `size` múltiplo de 64.
- `EmptyStateView(kind, primary:, secondary:)`: sobre `ContentUnavailableView`; kinds: allCaughtUp, noSessions, connecting, tailscaleOff, accessDenied, serverUnreachable.
- `PoppyActionStyle` (`.poppyProminent`, `.poppyNeutral`): botão 44 pt, moldura Guild, rótulo em pixel (SF em AX).
- `GuildFrame`, `GuildType`, `GuildAppearance` (abas, barra de navegação e seletor): ver acima.
- `DesignCatalogView` (só Debug): tudo acima; abrir com argumento `-design-catalog` (`DesignCatalog.isRequested`).

## Movimento e tato
Transições do sistema. `symbolEffect(.pulse)` só no estado trabalhando e desligado com Reduce Motion. `.sensoryFeedback`: warning (novo pedido), error, success (terminou/aprovado), selection (trocar janela), leve na barra de teclas.

## Poppy
Quadros reais recortados de `mascote/godot/assets/poppy.png` (índices em `scripts/poppy_frames.json`); humores: idle, working, attention, done, failed, lost, sleeping, waving. Sem easter eggs.
