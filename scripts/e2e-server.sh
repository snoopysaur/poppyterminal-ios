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

FORK_SHA="2261eaffab91591bb0bfb89b39ed382c0993eabe"
FORK_URL="${TUIOS_FORK_URL:-git@github.com:snoopysaur/poppyterminal.git}"
HERE="$(cd "$(dirname "$0")" && pwd)"
W="${E2E_DIR:-/tmp/pe2e}"
BIN="$W/bin"
SESSION="e2e"
WEB_PORT=18080
PROXY_PORT=18081
LOGIN="e2e@example.com"
PROXY_URL="http://127.0.0.1:$PROXY_PORT"

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

  log "tuios-web em $WEB_PORT + proxy $PROXY_PORT"
  (cd "$W/cwd" && nohup env HOME="$W/h" TMPDIR="$W/t" SHELL=/bin/sh XDG_RUNTIME_DIR="$W/r" \
    XDG_CONFIG_HOME="$W/h/.config" XDG_STATE_HOME="$W/h/.state" XDG_CACHE_HOME="$W/h/.cache" \
    XDG_DATA_HOME="$W/h/.local/share" XDG_CONFIG_DIRS="$W/h/.config-dirs" XDG_DATA_DIRS="$W/h/.data-dirs" \
    "$BIN/tuios-web" --host 127.0.0.1 --port "$WEB_PORT" --insecure \
    --password-file "$W/pw" --tailscale-login "$LOGIN" --default-session "$SESSION" \
    >"$W/logs/tuios-web.log" 2>&1 &
   echo $! > "$W/web.pid")
  wait_for 30 "tuios-web" curl -fsS "http://127.0.0.1:$WEB_PORT/health" || { tail -n 30 "$W/logs/tuios-web.log" >&2; die "tuios-web nao subiu"; }
  nohup "$BIN/e2e-proxy" -listen "127.0.0.1:$PROXY_PORT" -upstream "http://127.0.0.1:$WEB_PORT" \
    -login "$LOGIN" -log "$W/logs/proxy.log" >"$W/logs/proxy.out" 2>&1 &
  echo $! > "$W/proxy.pid"
  wait_for 15 "proxy" curl -fsS "$PROXY_URL/health" || die "proxy nao subiu"

  local info
  info="$(api GET /api/v1/info)"
  echo "$info" > "$W/logs/info.json"; log "info: $info"
  echo "$info" | python3 -c '
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if d.get("human_actions") is True and d.get("daemon_ok") else 1)' \
    || die "info sem human_actions/daemon_ok (login Tailscale simulado nao aceito?)"
  # A senha basica NAO pode agir como pessoa (regra de producao intacta).
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 10 -X POST -u "tuios:e2e-only-password" \
    -H 'X-Poppy-Client: e2e' "http://127.0.0.1:$WEB_PORT/api/v1/inbox/x/dismiss")"
  [ "$code" = "403" ] || die "senha basica deveria dar 403 em acao de pessoa, deu $code"

  log "semeando agentes"
  tuios set-agent-state -s "$SESSION" -w beta working --harness claude-code -m "rodando testes" \
    || log "AVISO: set-agent-state falhou (agente 'trabalhando' nao semeado)"
  printf '%s' '{"hook_event_name":"PermissionRequest","session_id":"e2e-approval","permission_mode":"default","tool_name":"run_shell_command","tool_input":{"command":"go test ./...","is_background":false}}' > "$W/hook.in"
  nohup env HOME="$W/h" TMPDIR="$W/t" SHELL=/bin/sh XDG_RUNTIME_DIR="$W/r" \
    XDG_CONFIG_HOME="$W/h/.config" XDG_STATE_HOME="$W/h/.state" XDG_CACHE_HOME="$W/h/.cache" \
    XDG_DATA_HOME="$W/h/.local/share" XDG_CONFIG_DIRS="$W/h/.config-dirs" XDG_DATA_DIRS="$W/h/.data-dirs" \
    "$BIN/tuios" agent-hook qwen --session "$SESSION" --window 0 \
    < "$W/hook.in" > "$W/logs/hook.out" 2> "$W/logs/hook.err" &
  echo $! > "$W/hook.pid"
  nohup env HOME="$W/h" TMPDIR="$W/t" SHELL=/bin/sh XDG_RUNTIME_DIR="$W/r" \
    XDG_CONFIG_HOME="$W/h/.config" XDG_STATE_HOME="$W/h/.state" XDG_CACHE_HOME="$W/h/.cache" \
    XDG_DATA_HOME="$W/h/.local/share" XDG_CONFIG_DIRS="$W/h/.config-dirs" XDG_DATA_DIRS="$W/h/.data-dirs" \
    "$BIN/tuios" ask-human -s "$SESSION" --timeout 900000 "Fazer deploy?" -o Sim -o Nao \
    > "$W/logs/ask.out" 2> "$W/logs/ask.err" &
  echo $! > "$W/ask.pid"
  if ! wait_for 60 "2 itens na inbox" inbox_has2; then
    api GET /api/v1/inbox >&2 || true
    tail -n 20 "$W/logs/hook.err" "$W/logs/ask.err" >&2 || true
    die "a inbox nao recebeu a aprovacao e a pergunta"
  fi
  api GET /api/v1/inbox > "$W/logs/inbox-seed.json"
  cat "$W/logs/inbox-seed.json" >&2; echo >&2

  printf 'E2E_URL=%s\nE2E_SESSION=%s\n' "$PROXY_URL" "$SESSION" > "$W/e2e.env"
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

  if grep -q allow "$W/logs/hook.out"; then log "OK   aprovacao 'uma vez' chegou ao hook (allow)"
  else log "FALHOU o hook nao recebeu allow"; fail=1; fi

  if grep -q 'Sim' "$W/logs/ask.out"; then log "OK   a resposta 'Sim' chegou ao ask-human"
  else log "FALHOU o ask-human nao recebeu 'Sim'"; fail=1; fi

  if grep -q 'api/v1/events?.*after_seq=' "$W/logs/proxy.log"; then log "OK   o app retomou o SSE com after_seq"
  else log "FALHOU nenhum GET /events com after_seq no log do proxy"; fail=1; fi

  if grep -q 'POST /api/v1/sessions/[^ ]*/focus' "$W/logs/proxy.log"; then log "FALHOU o app chamou rota de foco"; fail=1
  else log "OK   o app nunca chamou rota de foco"; fi

  if [ "$fail" = 0 ]; then log "verify: tudo OK"; else log "verify: houve falha"; fi
  return "$fail"
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
  for p in ask hook proxy web owner; do
    if [ -f "$W/$p.pid" ]; then kill "$(cat "$W/$p.pid")" 2>/dev/null || true; fi
  done
  if [ -x "$BIN/tuios" ]; then tuios kill-server >/dev/null 2>&1 || true; fi
  log "parado"
}

case "${1:-}" in
  start) cmd_start ;;
  verify) cmd_verify ;;
  probe) cmd_probe ;;
  stop) cmd_stop ;;
  *) echo "uso: $0 start|verify|stop" >&2; exit 2 ;;
esac
