# Design

Modo: Operate. Dials: variância 2/10, movimento 3/10, densidade média. Mockup de referência: `notes/estudos/poppyterminal-v020-mockup.html` (fora do repo, no workspace do Gobby). Código: `App/Theme.swift`, `App/Design/`.

## Cor (Catppuccin Mocha, só escuro)
| Papel | Token SwiftUI | Valor | Contraste |
|---|---|---|---|
| Fundo | `Theme.Palette.base` | #1E1E2E | |
| Cartão/lista | `.surface` (surface0) | #313244 | |
| Divisor/botão neutro | `.surfaceStrong` (surface1) | #45475A | |
| Terminal/comando | `.sunken` (crust) | #11111B | |
| Texto | `.text` | #CDD6F4 | 11,3 base / 8,7 surface |
| Texto secundário | `.textSecondary` (subtext0) | #A6ADC8 | 7,4 base / 5,7 surface; nunca sobre surface1 (4,1) |
| Acento único | `.accent` (Mauve) | #CBA6F7 | 8,1 base; texto sobre ele = crust (9,2) |

Estados (`AgentTone`): precisa de você = Peach #FAB387; erro = Red #F38BA8; trabalhando = Blue #89B4FA; terminou = Green #A6E3A1; ocioso = Overlay1 #7F849C (4,4 na base: só ícone/contorno, nunca texto). Texto de pill é sempre `.text`; a cor fica no símbolo (>= 3:1). Cada estado tem símbolo + rótulo próprios.
Regra: Mauve é o único acento; estados não viram decoração.

## Tipografia
SF Pro com estilos de texto do sistema (Dynamic Type) em toda a UI. JetBrains Mono Nerd (`Theme.fontRegular`) só para terminal, comandos e caminhos (`.custom(..., relativeTo:)`).

## Componentes (`App/Design/`)
- `AgentTone`: enum de estados (cor, símbolo, rótulo, prioridade, haptic).
- `StatusPill(tone, text?, count?)`: cápsula informativa; ocioso só com contorno.
- `AgentStateBadge(tone, count?, haptics:)`: selo redondo, 32 pt escalável, contador opcional.
- `PoppyView(mood, size:, label:)`: pixel art sem interpolação, 2 quadros a 2 Hz, parada com Reduce Motion; `size` múltiplo de 64.
- `EmptyStateView(kind, primary:, secondary:)`: sobre `ContentUnavailableView`; kinds: allCaughtUp, noSessions, connecting, tailscaleOff, accessDenied, serverUnreachable.
- `PoppyActionStyle` (`.poppyProminent`, `.poppyNeutral`): botão 44 pt.
- `DesignCatalogView` (só Debug): tudo acima; abrir com argumento `-design-catalog` (`DesignCatalog.isRequested`).

## Movimento e tato
Transições do sistema. `symbolEffect(.pulse)` só no estado trabalhando e desligado com Reduce Motion. `.sensoryFeedback`: warning (novo pedido), error, success (terminou/aprovado), selection (trocar janela), leve na barra de teclas.

## Poppy
Quadros reais recortados de `mascote/godot/assets/poppy.png` (índices em `scripts/poppy_frames.json`); humores: idle, working, attention, done, failed, lost, sleeping, waving. Sem easter eggs.
