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
	"net"
	"os"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/kianmhz/GooseRelayVPN/internal/carrier"
	"github.com/kianmhz/GooseRelayVPN/internal/session"
	"github.com/kianmhz/GooseRelayVPN/internal/socks"
)

func init() {
	// Go on Android also reads /data/misc/keychain/certs-added by default.
	// Restrict the engine to the immutable system trust store so a user- or
	// malware-installed CA cannot transparently intercept relay traffic.
	if runtime.GOOS == "android" {
		_ = os.Setenv(
			"SSL_CERT_DIR",
			"/system/etc/security/cacerts:/apex/com.android.conscrypt/cacerts",
		)
	}
}

type mobileConfig struct {
	Deployments []string `json:"deployments"`
	TunnelKey   string   `json:"tunnelKey"`
	SocksPort   int      `json:"socksPort"`
	SocksUser   string   `json:"socksUser"`
	SocksPass   string   `json:"socksPass"`
	GoogleIP    string   `json:"googleIp"`
	SNIHosts    []string `json:"sniHosts"`
	CoalesceMs  *int     `json:"coalesceMs"`
	IdleSlots   int      `json:"idleSlots"`
}

type statsResponse struct {
	Up       uint64 `json:"up"`
	Down     uint64 `json:"down"`
	Sessions uint64 `json:"sessions"`
}

func validCredential(value string, max int) bool {
	if value == "" || len(value) > max {
		return false
	}
	for _, r := range value {
		if (r < 'a' || r > 'z') && (r < 'A' || r > 'Z') && (r < '0' || r > '9') {
			return false
		}
	}
	return true
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
	if (cfg.SocksUser == "") != (cfg.SocksPass == "") {
		return response(fmt.Errorf("invalid configuration"))
	}
	if cfg.SocksUser != "" &&
		(!validCredential(cfg.SocksUser, 64) || !validCredential(cfg.SocksPass, 128)) {
		return response(fmt.Errorf("invalid configuration"))
	}

	googleIP := strings.TrimSpace(cfg.GoogleIP)
	if googleIP == "" {
		googleIP = "216.239.38.120"
	}
	if ip := net.ParseIP(googleIP); ip == nil || ip.To4() == nil {
		return response(fmt.Errorf("invalid Google edge IP"))
	}
	sniHosts := cfg.SNIHosts
	if len(sniHosts) == 0 {
		sniHosts = []string{"www.google.com", "mail.google.com", "accounts.google.com"}
	}
	for _, host := range sniHosts {
		host = strings.TrimSpace(host)
		if host == "" || strings.ContainsAny(host, "/\\") {
			return response(fmt.Errorf("invalid SNI host"))
		}
	}
	coalesceMs := 25
	if cfg.CoalesceMs != nil {
		coalesceMs = *cfg.CoalesceMs
	}
	if coalesceMs < 0 || coalesceMs > 1000 {
		return response(fmt.Errorf("invalid coalesce setting"))
	}
	idleSlots := cfg.IdleSlots
	if idleSlots == 0 {
		idleSlots = 2
	}
	if idleSlots < 1 || idleSlots > 3 {
		return response(fmt.Errorf("invalid idle-slot setting"))
	}

	urls := make([]string, 0, len(cfg.Deployments))
	for _, id := range cfg.Deployments {
		id = strings.TrimSpace(id)
		if !strings.HasPrefix(id, "AKfycb") || len(id) < 50 {
			return response(fmt.Errorf("invalid configuration"))
		}
		urls = append(urls, "https://script.google.com/macros/s/"+id+"/exec")
	}
	c, err := carrier.New(carrier.Config{
		ScriptURLs: urls,
		AESKeyHex:  cfg.TunnelKey,
		Fronting: carrier.FrontingConfig{
			GoogleIP: googleIP,
			SNIHosts: sniHosts,
		},
		CoalesceStep:       time.Duration(coalesceMs) * time.Millisecond,
		CoalesceMax:        time.Duration(coalesceMs*25) * time.Millisecond,
		IdleSlotsPerBucket: idleSlots,
	})
	if err != nil {
		return response(err)
	}
	listener, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", cfg.SocksPort))
	if err != nil {
		return response(fmt.Errorf("local SOCKS port is unavailable"))
	}
	socks.ResetStats()
	ctx, cancel := context.WithCancel(context.Background())
	state.cancel, state.carrier = cancel, c
	go func() { _ = c.Run(ctx) }()
	go func() {
		_ = socks.ServeListener(ctx, listener, cfg.SocksUser, cfg.SocksPass, false, socks.SessionFactory(func(target string) *session.Session { return c.NewSession(target) }))
	}()
	return response(nil)
}

//export xrv_stats_json
func xrv_stats_json() *C.char {
	up, down, sessions := socks.Stats()
	data, err := json.Marshal(statsResponse{Up: up, Down: down, Sessions: sessions})
	if err != nil {
		return C.CString(`{"up":0,"down":0,"sessions":0}`)
	}
	return C.CString(string(data))
}

//export xrv_probe_edges_json
func xrv_probe_edges_json(raw *C.char) *C.char {
	var req edgeProbeRequest
	if err := json.Unmarshal([]byte(C.GoString(raw)), &req); err != nil {
		return C.CString(`{"error":"invalid probe request"}`)
	}
	timeout := defaultEdgeProbeTimeout
	if req.TimeoutMs > 0 {
		timeout = time.Duration(req.TimeoutMs) * time.Millisecond
		if timeout > 15*time.Second {
			timeout = 15 * time.Second
		}
	}
	return C.CString(marshalProbeResponse(probeEdges(req.IPs, timeout)))
}

//export xrv_test_connection_json
func xrv_test_connection_json(raw *C.char) *C.char {
	var req connectionTestRequest
	if err := json.Unmarshal([]byte(C.GoString(raw)), &req); err != nil {
		return C.CString(`{"ok":false,"error":"invalid test request"}`)
	}
	data, err := json.Marshal(testTunnel(req.Port, req.User, req.Pass, 20*time.Second))
	if err != nil {
		return C.CString(`{"ok":false,"error":"encode failed"}`)
	}
	return C.CString(string(data))
}

//export xrv_logs_text
func xrv_logs_text() *C.char {
	return C.CString(engineLog.snapshot())
}

//export xrv_logs_clear
func xrv_logs_clear() {
	engineLog.clear()
}

//export xrv_stop
func xrv_stop() {
	state.Lock()
	defer state.Unlock()
	if state.cancel != nil {
		shutdown, done := context.WithTimeout(context.Background(), 3*time.Second)
		if state.carrier != nil {
			state.carrier.Shutdown(shutdown)
		}
		done()
		state.cancel()
		state.cancel = nil
		state.carrier = nil
	}
}
func main() {}
