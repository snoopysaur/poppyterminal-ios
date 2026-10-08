# Product

<!-- impeccable:product-schema 1 -->

> Gerado pela frente A4 sem entrevista interativa (sem canal de resposta): fatos vêm do plano `notes/frentes/poppyterminal-ios-v020-plano.md` e do repo. Itens marcados (inferido) esperam confirmação do Gobby.

## Platform

ios

## Users
Gobby (uso pessoal, único usuário), no iPhone, fora da mesa, ligado ao PC por Tailscale. Tarefa: acompanhar sessões do TUIOS (terminal multiplexador no PC), aprovar ou responder pedidos de agentes Claude Code e abrir um terminal numa janela específica sem mexer no foco do PC. Sessões curtas, muitas vezes com uma mão (inferido).

## Product Purpose
App nativo SwiftUI (v0.2.0) em volta do terminal `/ws` satélite do tuios-web: abas Sessões, Agentes (inbox de aprovações/perguntas/erros/término) e Ajustes; o terminal continua SwiftTerm. Sucesso: ver em segundos o que precisa dele, resolver pelo celular e voltar à vida.

## Positioning
Não é um cliente SSH genérico: conhece sessões, janelas e agentes do TUIOS e tem foco local separado do PC.

## Constraints
- iOS 17+, só iPhone, Swift 6, sem dependência de terceiros além do SwiftTerm; repo público sem segredos.
- Tema fixo escuro: Catppuccin Mocha; fonte do terminal JetBrains Mono Nerd (embutida).
- Mascote Poppy: só sprites reais da folha; sem easter eggs no app.
- Fora da v0.2.0: iPad, tema claro, push em segundo plano.

## Accessibility
Dynamic Type, VoiceOver com rótulos de estado, Reduce Motion, alvos de 44 pt, contraste AA; cor nunca é o único sinal de estado.

## Voice
Português do Brasil, direto e curto; a Poppy fala de leve ("Tudo em dia"), sem humor forçado em erros.
