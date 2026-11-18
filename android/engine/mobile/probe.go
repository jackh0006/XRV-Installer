package main

// Real network probes used by the Android settings screen. They mirror the
// Linux client's behavior:
//   * choose a Google edge by fetching https://www.google.com/generate_204
//     through each candidate IP and keeping the fastest 204 response;
//   * verify the tunnel by requesting https://api.ipify.org through the local
//     authenticated SOCKS5 listener and showing the exit IP.

import (
	"bufio"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/proxy"
)

const (
	defaultEdgeProbeTimeout = 6 * time.Second
	maxEdgeProbes           = 32
	edgeSNI                 = "www.google.com"
)

type edgeProbeRequest struct {
	IPs       []string `json:"ips"`
	TimeoutMs int      `json:"timeoutMs"`
}

type edgeProbeResult struct {
	IP     string `json:"ip"`
	OK     bool   `json:"ok"`
	MS     int64  `json:"ms"`
	Status int    `json:"status,omitempty"`
	Error  string `json:"error,omitempty"`
}

type edgeProbeResponse struct {
	Results []edgeProbeResult `json:"results"`
	Best    string            `json:"best,omitempty"`
	BestMS  int64             `json:"bestMs,omitempty"`
	Error   string            `json:"error,omitempty"`
}

type connectionTestRequest struct {
	Port int    `json:"port"`
	User string `json:"user"`
	Pass string `json:"pass"`
}

type connectionTestResponse struct {
	OK     bool   `json:"ok"`
	ExitIP string `json:"exitIp,omitempty"`
	MS     int64  `json:"ms,omitempty"`
	Error  string `json:"error,omitempty"`
}

func uniqueIPv4(values []string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(values))
	for _, raw := range values {
		value := strings.TrimSpace(raw)
		if value == "" {
			continue
		}
		ip := net.ParseIP(value)
		if ip == nil || ip.To4() == nil {
			continue
		}
		value = ip.To4().String()
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
		if len(out) >= maxEdgeProbes {
			break
		}
	}
	return out
}

func probeOneEdge(ip string, timeout time.Duration) edgeProbeResult {
	res := edgeProbeResult{IP: ip}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	start := time.Now()
	dialer := &net.Dialer{}
	conn, err := dialer.DialContext(ctx, "tcp4", net.JoinHostPort(ip, "443"))
	if err != nil {
		res.Error = "connect failed"
		return res
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(timeout))

	tlsConn := tls.Client(conn, &tls.Config{
		ServerName: edgeSNI,
		MinVersion: tls.VersionTLS12,
		NextProtos: []string{"http/1.1"},
	})
	if err := tlsConn.HandshakeContext(ctx); err != nil {
		res.Error = "tls failed"
		return res
	}

	request := "GET /generate_204 HTTP/1.1\r\n" +
		"Host: " + edgeSNI + "\r\n" +
		"User-Agent: XRV-Android\r\n" +
		"Connection: close\r\n\r\n"
	if _, err := io.WriteString(tlsConn, request); err != nil {
		res.Error = "request failed"
		return res
	}

	line, err := bufio.NewReader(tlsConn).ReadString('\n')
	if err != nil {
		res.Error = "no response"
		return res
	}
	fields := strings.Fields(line)
	if len(fields) < 2 {
		res.Error = "bad response"
		return res
	}
	var status int
	if _, err := fmt.Sscanf(fields[1], "%d", &status); err != nil {
		res.Error = "bad status"
		return res
	}
	res.Status = status
	res.MS = time.Since(start).Milliseconds()
	res.OK = status == http.StatusNoContent
	if !res.OK {
		res.Error = fmt.Sprintf("HTTP %d", status)
	}
	return res
}

func probeEdges(ips []string, timeout time.Duration) edgeProbeResponse {
	candidates := uniqueIPv4(ips)
	if len(candidates) == 0 {
		return edgeProbeResponse{Error: "no valid IPv4 addresses"}
	}
	results := make([]edgeProbeResult, len(candidates))
	var wg sync.WaitGroup
	for i, ip := range candidates {
		wg.Add(1)
		go func(i int, ip string) {
			defer wg.Done()
			results[i] = probeOneEdge(ip, timeout)
		}(i, ip)
	}
	wg.Wait()

	sort.SliceStable(results, func(i, j int) bool {
		if results[i].OK != results[j].OK {
			return results[i].OK
		}
		if results[i].MS != results[j].MS {
			return results[i].MS < results[j].MS
		}
		return results[i].IP < results[j].IP
	})
	resp := edgeProbeResponse{Results: results}
	for _, r := range results {
		if r.OK {
			resp.Best = r.IP
			resp.BestMS = r.MS
			break
		}
	}
	if resp.Best == "" {
		resp.Error = "none of the Google edges answered with HTTP 204"
	}
	return resp
}

func testTunnel(port int, user, pass string, timeout time.Duration) connectionTestResponse {
	if port < 1024 || port > 65535 {
		return connectionTestResponse{Error: "invalid local port"}
	}
	address := fmt.Sprintf("127.0.0.1:%d", port)
	var auth *proxy.Auth
	if user != "" {
		auth = &proxy.Auth{User: user, Password: pass}
	}
	dialer, err := proxy.SOCKS5("tcp", address, auth, proxy.Direct)
	if err != nil {
		return connectionTestResponse{Error: "SOCKS setup failed"}
	}
	transport := &http.Transport{
		DialContext: func(_ context.Context, network, addr string) (net.Conn, error) {
			return dialer.Dial(network, addr)
		},
		TLSHandshakeTimeout: timeout,
		ForceAttemptHTTP2:   false,
	}
	client := &http.Client{Transport: transport, Timeout: timeout}
	request, _ := http.NewRequest(http.MethodGet, "https://api.ipify.org", nil)
	request.Header.Set("User-Agent", "XRV-Android")
	start := time.Now()
	resp, err := client.Do(request)
	if err != nil {
		return connectionTestResponse{Error: "tunnel request failed"}
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 256))
	if err != nil {
		return connectionTestResponse{Error: "tunnel read failed"}
	}
	exitIP := strings.TrimSpace(string(body))
	if net.ParseIP(exitIP) == nil {
		return connectionTestResponse{Error: "exit did not return an IP address"}
	}
	return connectionTestResponse{
		OK:     true,
		ExitIP: exitIP,
		MS:     time.Since(start).Milliseconds(),
	}
}

func marshalProbeResponse(resp edgeProbeResponse) string {
	data, err := json.Marshal(resp)
	if err != nil {
		return `{"error":"encode failed"}`
	}
	return string(data)
}
