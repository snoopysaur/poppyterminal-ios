#!/usr/bin/env bash
# Servidor REAL para os UITests E2E do PoppyTerminal (roda no runner macOS do CI).
#
#   scripts/e2e-server.sh start    compila e sobe daemon + tuios-web + proxy, semeia a sessao
#   scripts/e2e-server.sh verify   confere o que so o servidor sabe (aprovacao, pergunta, after_seq)
#   scripts/e2e-server.sh stop     derruba tudo
#
# O fork do TUIOS e clonado em commit FIXO (wip/ios-v020). Nada aqui toca o PC do Gobby: tudo
# vive em $E2E_DIR (padrao /tmp/pe2e, curto por causa do limite de caminho do socket unix).
#
# Variaveis: TUIOS_FORK_URL (padrao ssh do fork), TUIOS_FORK_KEY_FILE (chave de deploy,
# somente leitura, vinda de secret do CI), TUIOS_FORK_SRC (usa um checkout pronto, sem clonar).
#
# Acoes de pessoa (aprovar/responder): o tuios-web so as aceita com login Tailscale vindo de
# loopback. A regra de producao fica intacta; o `e2e-proxy.go` faz o papel do `tailscale serve`
# e injeta o cabecalho Tailscale-User-Login. A senha basica continua NAO podendo agir.
set -euo pipefail

# wip/v030-servidor: chat (GET/send/interrupt/stream) + visao de celular + features em /info.
FORK_SHA="dffb9bf391ffc5d14129ef44b35536067b0ae7fc"
FORK_URL="${TUIOS_FORK_URL:-git@github.com:snoopysaur/poppyterminal.git}"
HERE="$(cd "$(dirname "$0")" && pwd)"
W="${E2E_DIR:-/tmp/pe2e}"
BIN="$W/bin"
SESSION="e2e"
WEB_PORT=18080
PROXY_PORT=18081
LEGACY_PORT=18083
CHAT_WIN="conversa"
CHAT_SID="0b7e3c1a-5d2f-4a8e-9c61-2f4d8a1b9e07"
SEED_PORT=18082
LOGIN="e2e@example.com"
PROXY_URL="http://127.0.0.1:$PROXY_PORT"
LEGACY_URL="http://127.0.0.1:$LEGACY_PORT"

log() { printf '[e2e-server] %s\n' "$*" >&2; }
die() { log "ERRO: $*"; exit 1; }

# Roda um comando isolado (HOME, XDG e TMPDIR sob $W).
iso() {
  env HOME="$W/h" TMPDIR="$W/t" SHELL=/bin/sh TERM=xterm-256color \
    XDG_RUNTIME_DIR="$W/r" XDG_CONFIG_HOME="$W/h/.config" XDG_STATE_HOME="$W/h/.state" \
    XDG_CACHE_HOME="$W/h/.cache" XDG_DATA_HOME="$W/h/.local/share" \
    XDG_CONFIG_DIRS="$W/h/.config-dirs" XDG_DATA_DIRS="$W/h/.data-dirs" "$@"
}
tuios() { iso "$BIN/tuios" "$@"; }

api() { # api METODO CAMINHO [JSON]
  if [ -n "${3:-}" ]; then
    curl -sS -m 15 -X "$1" -H 'X-Poppy-Client: e2e' -H 'Content-Type: application/json' -d "$3" "$PROXY_URL$2"
  else
    curl -sS -m 15 -X "$1" -H 'X-Poppy-Client: e2e' "$PROXY_URL$2"
  fi
}

build() {
  mkdir -p "$BIN"
  local src="${TUIOS_FORK_SRC:-$W/src}"
  if [ -z "${TUIOS_FORK_SRC:-}" ]; then
    rm -rf "$src"; mkdir -p "$src"
    export GIT_TERMINAL_PROMPT=0
    if [ -n "${TUIOS_FORK_KEY_FILE:-}" ]; then
      export GIT_SSH_COMMAND="ssh -i $TUIOS_FORK_KEY_FILE -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    fi
    log "clonando o fork no commit $FORK_SHA"
    git -C "$src" init -q
    git -C "$src" remote add origin "$FORK_URL"
    git -C "$src" fetch -q --depth 1 origin "$FORK_SHA"
    git -C "$src" checkout -q FETCH_HEAD
    [ "$(git -C "$src" rev-parse HEAD)" = "$FORK_SHA" ] || die "commit do fork diferente do fixo"
  fi
  log "go version: $(go version)"
  (cd "$src/engine" && GOTOOLCHAIN=auto go build -o "$BIN/tuios" ./cmd/tuios \
    && GOTOOLCHAIN=auto go build -o "$BIN/tuios-web" ./cmd/tuios-web)
  (cd "$HERE" && go build -o "$BIN/e2e-proxy" e2e-proxy.go)
  log "binarios: $(ls "$BIN" | tr '\n' ' ')"
}

wait_for() { # wait_for SEGUNDOS DESCRICAO comando...
  local n="$1" what="$2"; shift 2
  local i=0
  while ! "$@" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge "$((n * 4))" ]; then return 1; fi
    sleep 0.25
  done
}

# Algum campo "attach*"/"client*" do `ls --json` com valor verdadeiro = ha cliente anexado.
owner_attached() {
  tuios ls --json 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
def walk(x):
    if isinstance(x, dict):
        for k, v in x.items():
            if ("attach" in k.lower() or "client" in k.lower()) and v not in (0, False, None, "", []):
                return True
            if walk(v):
                return True
    elif isinstance(x, list):
        return any(walk(i) for i in x)
    return False
sys.exit(0 if walk(d) else 1)'
}

inbox_has2() {
  api GET /api/v1/inbox | python3 -c '
import json, sys
sys.exit(0 if len(json.load(sys.stdin).get("items", [])) >= 2 else 1)'
}

focused_index() {
  tuios list-windows --json -s "$SESSION" | python3 -c '
import json, sys
ws = json.load(sys.stdin)["windows"]
print(next(w["index"] for w in ws if w.get("focused")))'
}

# Uma linha de transcript no formato do Claude Code 2.1.295 (mesmo molde do e2e/tui do servidor).
tline() { # tline UUID TIPO CORPO
  printf '{"parentUuid":null,"isSidechain":false,"sessionId":"%s","version":"2.1.295","type":"%s","uuid":"%s","timestamp":"2026-10-09T13:00:02.000Z",%s}\n' "$CHAT_SID" "$2" "$1" "$3"
}
chat_transcript() { echo "$W/h/claude/projects/C--e2e-demo/$CHAT_SID.jsonl"; }

cmd_start() {
  rm -rf "$W"; mkdir -p "$W/h" "$W/t" "$W/r" "$W/cwd" "$W/logs"
  build
  umask 077
  printf 'e2e-only-password\n' > "$W/pw"
  mkdir -p "$W/h/.config/tuios"
  # Aprovacoes seguradas para o agent-hook "qwen" (o mesmo molde dos testes do fork).
  printf '[agents.approvals]\nenabled = ["qwen"]\nhold_seconds = 900\n' > "$W/h/.config/tuios/config.toml"

  log "daemon + sessao $SESSION"
  tuios new "$SESSION" --detach
  nohup env HOME="$W/h" TMPDIR="$W/t" SHELL=/bin/sh TERM=xterm-256color XDG_RUNTIME_DIR="$W/r" \
    XDG_CONFIG_HOME="$W/h/.config" XDG_STATE_HOME="$W/h/.state" XDG_CACHE_HOME="$W/h/.cache" \
    XDG_DATA_HOME="$W/h/.local/share" XDG_CONFIG_DIRS="$W/h/.config-dirs" XDG_DATA_DIRS="$W/h/.data-dirs" \
    python3 "$HERE/e2e-owner.py" "$W/logs/owner.log" "$BIN/tuios" attach "$SESSION" \
    >"$W/logs/owner.out" 2>&1 &
  echo $! > "$W/owner.pid"

  if wait_for 20 "dono anexado" owner_attached; then
    log "dono anexado (ls --json)"
  else
    log "AVISO: ls --json nao mostrou cliente anexado; seguindo com espera fixa"
  fi
  tuios ls --json > "$W/logs/ls.json" || true
  cat "$W/logs/ls.json" >&2 || true
  sleep 3

  # Duas janelas: A (a primeira, com o foco do dono) e B (beta). B nasce sem tirar o foco.
  tuios new-window -s "$SESSION" beta --no-focus
  tuios focus-window -s "$SESSION" 0
  sleep 1
  tuios list-windows --json -s "$SESSION" > "$W/logs/windows.json"
  cat "$W/logs/windows.json" >&2
  local focused
  focused="$(focused_index)"
  [ "$focused" = "0" ] || die "o foco do dono nao esta na janela A (index $focused)"

  # Janela com chat: um "Claude Code" (harness + agent_session_id) com transcript falso em CLAUDE_CONFIG_DIR.
  tuios new-window -s "$SESSION" "$CHAT_WIN" --no-focus
  tuios focus-window -s "$SESSION" 0
  mkdir -p "$W/h/claude/projects/C--e2e-demo"
  {
    tline aaaaaaaa-0000-4000-8000-000000000001 user '"message":{"role":"user","content":"ola, Claude"}'
    tline aaaaaaaa-0000-4000-8000-000000000002 assistant '"message":{"role":"assistant","content":[{"type":"text","text":"ola! como posso ajudar no E2E?"}]}'
  } > "$(chat_transcript)"
  tuios set-agent-state -s "$SESSION" -w "$CHAT_WIN" working --harness claude-code --agent-session-id "$CHAT_SID" -m "conversando" \
    || die "set-agent-state da janela de chat falhou"
  [ "$(focused_index)" = "0" ] || die "o foco do dono saiu da janela A ao criar a janela de chat"

  log "tuios-web em $WEB_PORT + proxy $PROXY_PORT"
  (cd "$W/cwd" && nohup env HOME="$W/h" TMPDIR="$W/t" SHELL=/bin/sh XDG_RUNTIME_DIR="$W/r" \
    XDG_CONFIG_HOME="$W/h/.config" XDG_STATE_HOME="$W/h/.state" XDG_CACHE_HOME="$W/h/.cache" \
    XDG_DATA_HOME="$W/h/.local/share" XDG_CONFIG_DIRS="$W/h/.config-dirs" XDG_DATA_DIRS="$W/h/.data-dirs" \
    CLAUDE_CONFIG_DIR="$W/h/claude" \
    "$BIN/tuios-web" --host 127.0.0.1 --port "$WEB_PORT" --insecure \
    --password-file "$W/pw" --tailscale-login "$LOGIN" --default-session "$SESSION" \
    >"$W/logs/tuios-web.log" 2>&1 &
   echo $! > "$W/web.pid")
  wait_for 30 "tuios-web" curl -fsS "http://127.0.0.1:$WEB_PORT/health" || { tail -n 30 "$W/logs/tuios-web.log" >&2; die "tuios-web nao subiu"; }
  nohup "$BIN/e2e-proxy" -listen "127.0.0.1:$PROXY_PORT" -upstream "http://127.0.0.1:$WEB_PORT" \
    -login "$LOGIN" -log "$W/logs/proxy.log" >"$W/logs/proxy.out" 2>&1 &
  echo $! > "$W/proxy.pid"
  wait_for 15 "proxy" curl -fsS "$PROXY_URL/health" || die "proxy nao subiu"
  # Servidor "antigo" para o UITest: o mesmo tuios-web, mas /info sem `features`.
  nohup "$BIN/e2e-proxy" -listen "127.0.0.1:$LEGACY_PORT" -upstream "http://127.0.0.1:$WEB_PORT" \
    -login "$LOGIN" -log "$W/logs/proxy-legacy.log" -legacy >"$W/logs/proxy-legacy.out" 2>&1 &
  echo $! > "$W/proxy-legacy.pid"
  wait_for 15 "proxy legacy" curl -fsS "$LEGACY_URL/health" || die "proxy legacy nao subiu"
  curl -fsS -m 10 -H 'X-Poppy-Client: e2e' "$LEGACY_URL/api/v1/info" | python3 -c '
import json, sys
d = json.load(sys.stdin)
sys.exit(1 if "features" in d else 0)' || die "o proxy legacy deixou passar features"

  local info
  info="$(api GET /api/v1/info)"
  echo "$info" > "$W/logs/info.json"; log "info: $info"
  echo "$info" | python3 -c '
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if d.get("human_actions") is True and d.get("daemon_ok") and "chat" in d.get("features", []) else 1)' \
    || die "info sem human_actions/daemon_ok (login Tailscale simulado nao aceito?)"
  # A senha basica NAO pode agir como pessoa (regra de producao intacta).
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 10 -X POST -u "tuios:e2e-only-password" \
    -H 'X-Poppy-Client: e2e' "http://127.0.0.1:$WEB_PORT/api/v1/inbox/x/dismiss")"
  [ "$code" = "403" ] || die "senha basica deveria dar 403 em acao de pessoa, deu $code"

  log "semeando agentes"
  tuios set-agent-state -s "$SESSION" -w beta working --harness claude-code -m "rodando testes" \
    || log "AVISO: set-agent-state falhou (agente 'trabalhando' nao semeado)"
  nohup python3 "$HERE/e2e-seeder.py" "$SEED_PORT" "$HERE/e2e-server.sh" >"$W/logs/seeder.log" 2>&1 &
  echo $! > "$W/seeder.pid"
  wait_for 15 "seeder" curl -fsS "http://127.0.0.1:$SEED_PORT/health" || die "seeder nao subiu"

  printf 'E2E_URL=%s
E2E_SESSION=%s
E2E_SEED_URL=http://127.0.0.1:%s
E2E_LEGACY_URL=%s
' "$PROXY_URL" "$SESSION" "$SEED_PORT" "$LEGACY_URL" > "$W/e2e.env"
  log "pronto: $PROXY_URL (sessao $SESSION); variaveis em $W/e2e.env"
}

cmd_verify() {
  local fail=0
  api GET "/api/v1/sessions/$SESSION" > "$W/logs/final-session.json" || true

  if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
ws = [w for s in d["workspaces"] for w in s["windows"]]
foc = [w for w in ws if w.get("focused")]
sys.exit(0 if len(foc) == 1 and foc[0]["id"] == ws[0]["id"] else 1)' "$W/logs/final-session.json"; then
    log "OK   o foco do PC continua na janela A"
  else log "FALHOU o foco do PC saiu da janela A"; fail=1; fi

  if grep -q allow "$W/logs/hook-e2e05.out"; then log "OK   aprovacao 'uma vez' chegou ao hook (allow)"
  else log "FALHOU o hook nao recebeu allow"; fail=1; fi

  if grep -q 'Sim' "$W/logs/ask-e2e06.out"; then log "OK   a resposta 'Sim' chegou ao ask-human"
  else log "FALHOU o ask-human nao recebeu 'Sim'"; fail=1; fi

  if tuios capture-pane -s "$SESSION" -w "$CHAT_WIN" 2>/dev/null | grep -q E2ESEND; then log "OK   o texto enviado pelo chat chegou ao PTY da janela $CHAT_WIN"
  else log "FALHOU o texto do chat nao apareceu no PTY da janela $CHAT_WIN"; fail=1; fi

  if grep -q 'api/v1/events?.*after_seq=' "$W/logs/proxy.log"; then log "OK   o app retomou o SSE com after_seq"
  else log "FALHOU nenhum GET /events com after_seq no log do proxy"; fail=1; fi

  if grep -q 'POST /api/v1/sessions/[^ ]*/focus' "$W/logs/proxy.log"; then log "FALHOU o app chamou rota de foco"; fail=1
  else log "OK   o app nunca chamou rota de foco"; fi

  if [ "$fail" = 0 ]; then log "verify: tudo OK"; else log "verify: houve falha"; fi
  return "$fail"
}

# O hold de aprovacao do fork dura no maximo 300 s: cada teste semeia o seu, na hora
# (via e2e-seeder.py), com uma etiqueta unica no comando para nao casar com itens velhos.
cmd_seed_approval() { # TAG
  local tag="${1:?tag}"
  # Itens de atencao sao por janela: uma aprovacao velha na janela 0 impede outra nova ali.
  local win=0; [ "$tag" = e2e05 ] && win=beta
  case "$tag" in e2echat*) win="$CHAT_WIN" ;; esac
  printf '{"hook_event_name":"PermissionRequest","session_id":"e2e-%s","permission_mode":"default","tool_name":"run_shell_command","tool_input":{"command":"go test ./... %s","is_background":false}}' "$tag" "$tag" > "$W/hook-$tag.in"
  nohup env HOME="$W/h" TMPDIR="$W/t" SHELL=/bin/sh XDG_RUNTIME_DIR="$W/r" \
    XDG_CONFIG_HOME="$W/h/.config" XDG_STATE_HOME="$W/h/.state" XDG_CACHE_HOME="$W/h/.cache" \
    XDG_DATA_HOME="$W/h/.local/share" XDG_CONFIG_DIRS="$W/h/.config-dirs" XDG_DATA_DIRS="$W/h/.data-dirs" \
    "$BIN/tuios" agent-hook qwen --session "$SESSION" --window "$win" \
    < "$W/hook-$tag.in" > "$W/logs/hook-$tag.out" 2> "$W/logs/hook-$tag.err" &
  wait_for 30 "item $tag" bash -c "curl -fsS -H 'X-Poppy-Client: e2e' '$PROXY_URL/api/v1/inbox' | grep -q '$tag'" \
    || { tail -n 20 "$W/logs/hook-$tag.err" >&2; die "aprovacao $tag nao apareceu"; }
}

cmd_seed_ask() { # TAG
  local tag="${1:?tag}"
  nohup env HOME="$W/h" TMPDIR="$W/t" SHELL=/bin/sh XDG_RUNTIME_DIR="$W/r" \
    XDG_CONFIG_HOME="$W/h/.config" XDG_STATE_HOME="$W/h/.state" XDG_CACHE_HOME="$W/h/.cache" \
    XDG_DATA_HOME="$W/h/.local/share" XDG_CONFIG_DIRS="$W/h/.config-dirs" XDG_DATA_DIRS="$W/h/.data-dirs" \
    "$BIN/tuios" ask-human -s "$SESSION" --timeout 1200000 "Fazer deploy?" -o Sim -o Nao \
    > "$W/logs/ask-$tag.out" 2> "$W/logs/ask-$tag.err" &
  wait_for 30 "pergunta" bash -c "curl -fsS -H 'X-Poppy-Client: e2e' '$PROXY_URL/api/v1/inbox' | grep -q 'Fazer deploy'" \
    || die "pergunta nao apareceu"
}

# Acrescenta uma resposta ao transcript da janela de chat (o Claude "falando" ao vivo).
cmd_seed_chatline() { # TAG
  local tag="${1:?tag}" n
  n="$(date +%s%N | tail -c 9)"
  tline "bbbbbbbb-0000-4000-8000-0000${n:0:8}" assistant "\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"resposta ao vivo $tag\"}]}" >> "$(chat_transcript)"
}

cmd_probe() {
  local id
  id="$(api GET /api/v1/inbox | python3 -c "import json,sys; print(next((i['id'] for i in json.load(sys.stdin)['items'] if i['kind']=='approval'), ''))")"
  log "probe: aprovacao id=$id"
  [ -n "$id" ] || return 0
  api GET "/api/v1/inbox/$id/prompt" >&2; echo >&2
  api POST "/api/v1/inbox/$id/reply" '{"decision":"once"}' >&2; echo >&2
}

cmd_stop() {
  for p in seeder ask hook proxy proxy-legacy web owner; do
    if [ -f "$W/$p.pid" ]; then kill "$(cat "$W/$p.pid")" 2>/dev/null || true; fi
  done
  if [ -x "$BIN/tuios" ]; then tuios kill-server >/dev/null 2>&1 || true; fi
  log "parado"
}

case "${1:-}" in
  start) cmd_start ;;
  verify) cmd_verify ;;
  probe) cmd_probe ;;
  seed-approval) cmd_seed_approval "$2" ;;
  seed-ask) cmd_seed_ask "$2" ;;
  seed-chatline) cmd_seed_chatline "$2" ;;
  stop) cmd_stop ;;
  *) echo "uso: $0 start|verify|probe|stop" >&2; exit 2 ;;
esac
