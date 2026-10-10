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
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

func main() {
	listen := flag.String("listen", "127.0.0.1:18081", "endereco do proxy")
	upstream := flag.String("upstream", "http://127.0.0.1:18080", "tuios-web")
	login := flag.String("login", "e2e@example.com", "login Tailscale simulado")
	logPath := flag.String("log", "proxy.log", "arquivo de log")
	legacy := flag.Bool("legacy", false, "finge servidor antigo: GET /api/v1/info sem o campo features")
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
		if *legacy {
			r.Header.Del("Accept-Encoding")
		}
	}
	if *legacy {
		rp.ModifyResponse = func(resp *http.Response) error {
			if resp.Request.URL.Path != "/api/v1/info" || resp.StatusCode != http.StatusOK {
				return nil
			}
			body, err := io.ReadAll(resp.Body)
			resp.Body.Close()
			if err != nil {
				return err
			}
			var m map[string]any
			if json.Unmarshal(body, &m) == nil {
				delete(m, "features")
				if nb, err := json.Marshal(m); err == nil {
					body = nb
				}
			}
			resp.Body = io.NopCloser(bytes.NewReader(body))
			resp.ContentLength = int64(len(body))
			resp.Header.Set("Content-Length", strconv.Itoa(len(body)))
			return nil
		}
	}
	// Deep link do push (v0.4 S4): o fork do E2E e a v0.3.2 e NAO tem a rota GET /api/v1/push/{id}
	// (ela vem do servidor v0.4, testada no repo do engine). Aqui o proxy faz o papel dela so para
	// ids que o teste registrou antes; qualquer outro id segue para o servidor de verdade (404).
	//   POST /__test/push/<32hex>/<inbox_id>   registra o mapeamento
	//   GET  /__test/push-hits                 quantas vezes a rota /push foi chamada
	var pushMu sync.Mutex
	pushMap := map[string]string{}
	pushHits := 0
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		fmt.Fprintf(lf, "%s REQ %s %s?%s last-event-id=%q\n", time.Now().UTC().Format(time.RFC3339), r.Method, r.URL.Path, r.URL.RawQuery, r.Header.Get("Last-Event-ID"))
		mu.Unlock()
		if r.Method == http.MethodPost && strings.HasPrefix(r.URL.Path, "/__test/push/") {
			parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/__test/push/"), "/")
			if len(parts) != 2 || len(parts[0]) != 32 || parts[1] == "" {
				http.Error(w, "uso: /__test/push/<32hex>/<inbox_id>", http.StatusBadRequest)
				return
			}
			pushMu.Lock()
			pushMap[parts[0]] = parts[1]
			pushMu.Unlock()
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if r.Method == http.MethodGet && r.URL.Path == "/__test/push-hits" {
			pushMu.Lock()
			n := pushHits
			pushMu.Unlock()
			fmt.Fprintf(w, "%d", n)
			return
		}
		if r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, "/api/v1/push/") {
			pushMu.Lock()
			pushHits++
			inbox, ok := pushMap[strings.TrimPrefix(r.URL.Path, "/api/v1/push/")]
			pushMu.Unlock()
			if ok {
				w.Header().Set("Content-Type", "application/json")
				_ = json.NewEncoder(w).Encode(map[string]string{"inbox_id": inbox})
				return
			}
		}
		rp.ServeHTTP(w, r)
	})
	log.Fatal(http.ListenAndServe(*listen, h))
}
