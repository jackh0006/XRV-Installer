// XRV's Android bridge. The relay protocol itself is vendored unchanged from
// GooseRelayVPN (MIT); this file only adapts it to an in-process Android app.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/kianmhz/GooseRelayVPN/internal/carrier"
	"github.com/kianmhz/GooseRelayVPN/internal/session"
	"github.com/kianmhz/GooseRelayVPN/internal/socks"
)

type mobileConfig struct {
	Deployments []string `json:"deployments"`
	TunnelKey   string   `json:"tunnelKey"`
	SocksPort   int      `json:"socksPort"`
}

var state struct {
	sync.Mutex
	cancel  context.CancelFunc
	carrier *carrier.Client
}

func response(err error) *C.char {
	if err != nil {
		return C.CString(err.Error())
	}
	return C.CString("")
}

//export xrv_start_json
func xrv_start_json(raw *C.char) *C.char {
	state.Lock()
	defer state.Unlock()
	if state.cancel != nil {
		return response(fmt.Errorf("XRV is already running"))
	}
	var cfg mobileConfig
	if err := json.Unmarshal([]byte(C.GoString(raw)), &cfg); err != nil {
		return response(fmt.Errorf("invalid configuration"))
	}
	if len(cfg.Deployments) < 1 || len(cfg.Deployments) > 4 || len(cfg.TunnelKey) != 64 || cfg.SocksPort < 1024 || cfg.SocksPort > 65535 {
		return response(fmt.Errorf("invalid configuration"))
	}
	if _, err := hex.DecodeString(cfg.TunnelKey); err != nil {
		return response(fmt.Errorf("invalid configuration"))
	}
	urls := make([]string, 0, len(cfg.Deployments))
	for _, id := range cfg.Deployments {
		id = strings.TrimSpace(id)
		if !strings.HasPrefix(id, "AKfycb") || len(id) < 50 {
			return response(fmt.Errorf("invalid configuration"))
		}
		urls = append(urls, "https://script.google.com/macros/s/"+id+"/exec")
	}
	c, err := carrier.New(carrier.Config{ScriptURLs: urls, AESKeyHex: cfg.TunnelKey, Fronting: carrier.FrontingConfig{GoogleIP: "216.239.38.120", SNIHosts: []string{"www.google.com"}}, IdleSlotsPerBucket: 1})
	if err != nil {
		return response(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	state.cancel, state.carrier = cancel, c
	go func() { _ = c.Run(ctx) }()
	go func() {
		_ = socks.Serve(ctx, fmt.Sprintf("127.0.0.1:%d", cfg.SocksPort), "", "", false, socks.SessionFactory(func(target string) *session.Session { return c.NewSession(target) }))
	}()
	return response(nil)
}

//export xrv_stop
func xrv_stop() {
	state.Lock()
	defer state.Unlock()
	if state.cancel != nil {
		shutdown, done := context.WithTimeout(context.Background(), 3*time.Second)
		state.carrier.Shutdown(shutdown)
		done()
		state.cancel()
		state.cancel = nil
		state.carrier = nil
	}
}
func main() {}
