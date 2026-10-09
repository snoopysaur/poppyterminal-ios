# Fixtures do chatlog (PoppyTerminal v0.3.0, Onda 0)

Tudo aqui é **sintético**: texto, caminhos (`C:\Users\fulano\...`), ids e segredos foram inventados.
O formato segue o **Claude Code 2.1.295**: a estrutura (chaves e tipos) foi conferida em transcripts reais, mas nenhum conteúdo foi copiado.
Contrato: `notes/frentes/poppyterminal-ios-v030-contrato.md` (§3 a §5).

São arquivos congelados da Onda 0. As frentes só leem. Mudança aqui é pedido à integração, e o par no app (`Packages/PoppyKit/Tests/PoppyKitTests/Fixtures/chat/`) muda junto.

## Layout

```
projects/                       raiz falsa de ~/.claude/projects (Locator.Root nos testes)
  C--Users-fulano-Projetos-demo/
    <sid>.jsonl                 um transcript por sessão
    0b7e3c1a-.../subagents/agent-a7f3c9e1b2d4e6f8.jsonl   subagente (2.1.295 grava a sidechain aqui): NUNCA ler
    sub/0b7e3c1a-....jsonl      armadilha: mesmo nome num nível abaixo. Busca recursiva acha e vaza
  C--Users-fulano-Projetos-outro/
    c0ffee00-....jsonl          sessionId de dentro não bate com o nome
    d15ea5e0-....jsonl          formato que ninguém conhece
esperado/<fixture>.json         projeção esperada (histórico inteiro, depois do último /clear)
vazamento.txt                   segredos falsos: nenhum pode aparecer em saída nenhuma
canarios.txt                    marcadores que só existem em campos proibidos: nenhum pode aparecer
```

## Fixtures

| fixture | sessão (`<sid>.jsonl`) | cobre | itens |
|---|---|---|---|
| basico | 0b7e3c1a-5d2f-4a8e-9c61-2f4d8a1b9e07 | texto; Bash, Read, Write, Edit, Agent, ToolSearch e mcp__*; tool_result ok, erro e em lista; thinking; redacted_thinking; imagem; sidechain inline; isMeta; local_command; interrompido; tipos sem chat (snapshot, hook, queue, títulos, custo) | 24 |
| segredos | 5f1c2a9d-8e3b-4c7a-a1d2-6b9e0f3c4d18 | todas as regras do redator: texto, comando Bash, URL com senha, chave privada, base64, hex, key=valor, resumo maior que 160; v0.3 pós-revisão: PGP, PuTTY, curl -u, Basic, DB_PASS=, senha:, hf_/glpat-/GOCSPX-, webhooks | 15 |
| grande | 9a2d4f6b-1c3e-4b5a-8d7f-0e2c4a6b8d19 | 70 trocas (3 páginas de 50); tool_result de ~300 KB numa linha só, maior que o bloco de 256 KB; texto acima de 8 KB com multibyte (corte em 8192 bytes) | 143 |
| clear_antes | 3d8b1f2e-7a4c-4e9d-b5a6-1c0f2e3d4a5b | conversa velha (o agent_session_id antigo) | 2 |
| clear_depois | 7e4a2c1b-9d3f-4b8e-a6c5-2d1e0f9a8b7c | arquivo novo depois do /clear, que começa pela linha `/clear` | 2 |
| clear_inline | f6d4a1f9-2b4d-4c6e-8a0b-1d3f5e7a9c2b | caso defensivo: `/clear` no meio do mesmo arquivo; o que vem antes some | 2 |
| tolerancia | e5c3a1f9-2b4d-4c6e-8a0b-1d3f5e7a9c2b | tipo desconhecido, JSON quebrado, linha vazia, assistant sem message, bloco desconhecido, dois blocos numa linha, compact_boundary/isCompactSummary, comando e bash do usuário, **última linha sem `\n`** | 6 |
| sessao_trocada | c0ffee00-1111-4222-8333-444455556666 | `supported:false`, `reason:"session_mismatch"` | 0 |
| formato_novo | d15ea5e0-2222-4333-8444-555566667777 | `supported:false`, `reason:"unknown_format"` | 0 |

## Como o teste usa

- **Home**: os caminhos usam `C:\Users\fulano`. O parser recebe `Home` por opção (o campo `home` de cada `esperado/*.json`) e nunca lê `os.UserHomeDir()` no teste.
- **Comparação**: compare `id, role, kind, text, truncated, tool, result, ts` e `cursor`. O cursor é `<conversation_id>.<offset do fim da linha em bytes>`. `conversation_id` são os 16 primeiros hex do sha256 do sessionId. Os bytes dos arquivos são exatos (`.gitattributes` com `-text`). Não deixe o git converter fim de linha.
- **Vazamento** (obrigatório, falha o build): para cada fixture, rode a leitura inteira e também a paginada (limit 1, 7 e 50); serialize toda resposta HTTP e todo evento SSE; nenhuma linha de `vazamento.txt` e nenhuma de `canarios.txt` pode aparecer. Inclua o log do servidor (texto do log capturado) no mesmo teste.
- **Linha parcial**: `tolerancia` termina em `{"parentUuid":null,...,"text":"PARCIAL-AINDA-NAO meio da escr`, sem `\n`. Ela não pode sair na leitura nem no stream. O teste de tail acrescenta o resto da linha e o `\n` e espera exatamente 1 mensagem nova. `PARCIAL-AINDA-NAO` não está em `canarios.txt` de propósito.
- **Subagente/armadilha**: com `Root=projects`, procurar `0b7e3c1a-...` acha só `projects/C--Users-fulano-Projetos-demo/0b7e3c1a-....jsonl`. `CANARIO-SUBAGENTE` e `CANARIO-ARMADILHA-RECURSIVA` provam que nada mais foi lido.
- **Traversal/symlink**: crie em tempo de teste (`t.TempDir()`), não por fixture: id `../x`, id com `\`, symlink de `projects/X/<sid>.jsonl` para fora da raiz (pule com `t.Skip` se o Windows não deixar criar symlink).
