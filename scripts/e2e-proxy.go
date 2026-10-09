//go:build ignore

// Proxy de teste E2E: faz o papel do `tailscale serve`, que injeta o cabecalho
// Tailscale-User-Login nas requisicoes que chegam pela tailnet. So existe no runner
// de CI; o tuios-web de producao continua exigindo o login Tailscale de verdade
// (e so confia no cabecalho vindo de loopback). Registra cada requisicao
// (metodo, caminho, query, Last-Event-ID) para o `verify` do e2e-server.sh.
//
// uso: go run e2e-proxy.go -listen 127.0.0.1:18081 -upstream http://127.0.0.1:18080 \
//
//	-login e2e@example.com -log proxy.log
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"sync"
	"time"
)

func main() {
	listen := flag.String("listen", "127.0.0.1:18081", "endereco do proxy")
	upstream := flag.String("upstream", "http://127.0.0.1:18080", "tuios-web")
	login := flag.String("login", "e2e@example.com", "login Tailscale simulado")
	logPath := flag.String("log", "proxy.log", "arquivo de log")
	flag.Parse()

	u, err := url.Parse(*upstream)
	if err != nil {
		log.Fatal(err)
	}
	lf, err := os.OpenFile(*logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		log.Fatal(err)
	}
	var mu sync.Mutex
	rp := httputil.NewSingleHostReverseProxy(u)
	rp.FlushInterval = -1 // SSE sem buffer
	orig := rp.Director
	rp.Director = func(r *http.Request) {
		orig(r)
		r.Header.Set("Tailscale-User-Login", *login)
	}
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		fmt.Fprintf(lf, "%s REQ %s %s?%s last-event-id=%q\n", time.Now().UTC().Format(time.RFC3339), r.Method, r.URL.Path, r.URL.RawQuery, r.Header.Get("Last-Event-ID"))
		mu.Unlock()
		rp.ServeHTTP(w, r)
	})
	log.Fatal(http.ListenAndServe(*listen, h))
}
