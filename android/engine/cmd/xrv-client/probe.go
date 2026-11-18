package main

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
	edgeSNI          = "www.google.com"
	edgeProbeTimeout = 6 * time.Second
	maxEdgeProbes    = 32
)

type EdgeResult struct {
	IP     string `json:"ip"`
	OK     bool   `json:"ok"`
	MS     int64  `json:"ms"`
	Status int    `json:"status,omitempty"`
	Error  string `json:"error,omitempty"`
}

type EdgeReport struct {
	Results []EdgeResult `json:"results"`
	Best    string       `json:"best,omitempty"`
	BestMS  int64        `json:"bestMs,omitempty"`
	Error   string       `json:"error,omitempty"`
}

func validIPv4(value string) bool {
	value = strings.TrimSpace(value)
	ip := net.ParseIP(value)
	return ip != nil && ip.To4() != nil
}

func uniqueIPv4(values []string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(values))
	for _, raw := range values {
		value := strings.TrimSpace(raw)
		if !validIPv4(value) {
			continue
		}
		value = net.ParseIP(value).To4().String()
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

func probeOneEdge(ip string, timeout time.Duration) EdgeResult {
	res := EdgeResult{IP: ip}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	start := time.Now()
	conn, err := (&net.Dialer{}).DialContext(ctx, "tcp4", net.JoinHostPort(ip, "443"))
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
		res.Error = "TLS failed"
		return res
	}
	request := "GET /generate_204 HTTP/1.1\r\nHost: " + edgeSNI +
		"\r\nUser-Agent: XRV-Linux\r\nConnection: close\r\n\r\n"
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

func probeEdges(values []string, timeout time.Duration) EdgeReport {
	ips := uniqueIPv4(values)
	if len(ips) == 0 {
		return EdgeReport{Error: "no valid IPv4 addresses"}
	}
	results := make([]EdgeResult, len(ips))
	var wg sync.WaitGroup
	for i, ip := range ips {
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
	report := EdgeReport{Results: results}
	for _, result := range results {
		if result.OK {
			report.Best = result.IP
			report.BestMS = result.MS
			break
		}
	}
	if report.Best == "" {
		report.Error = "none of the Google edges answered with HTTP 204"
	}
	return report
}

type TunnelTest struct {
	OK     bool   `json:"ok"`
	ExitIP string `json:"exitIp,omitempty"`
	MS     int64  `json:"ms,omitempty"`
	Error  string `json:"error,omitempty"`
}

func testTunnel(port int, user, pass string, timeout time.Duration) TunnelTest {
	address := fmt.Sprintf("127.0.0.1:%d", port)
	var auth *proxy.Auth
	if user != "" {
		auth = &proxy.Auth{User: user, Password: pass}
	}
	dialer, err := proxy.SOCKS5("tcp", address, auth, proxy.Direct)
	if err != nil {
		return TunnelTest{Error: "SOCKS setup failed"}
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
	request.Header.Set("User-Agent", "XRV-Linux")
	start := time.Now()
	resp, err := client.Do(request)
	if err != nil {
		return TunnelTest{Error: "tunnel request failed"}
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 256))
	if err != nil {
		return TunnelTest{Error: "tunnel read failed"}
	}
	exitIP := strings.TrimSpace(string(body))
	if net.ParseIP(exitIP) == nil {
		return TunnelTest{Error: "exit did not return an IP address"}
	}
	return TunnelTest{OK: true, ExitIP: exitIP, MS: time.Since(start).Milliseconds()}
}

func directIP(timeout time.Duration) string {
	transport := &http.Transport{
		Proxy:               nil,
		TLSHandshakeTimeout: timeout,
		ForceAttemptHTTP2:   false,
	}
	client := &http.Client{Transport: transport, Timeout: timeout}
	request, _ := http.NewRequest(http.MethodGet, "https://api.ipify.org", nil)
	request.Header.Set("User-Agent", "XRV-Linux")
	resp, err := client.Do(request)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64))
	if err != nil {
		return ""
	}
	value := strings.TrimSpace(string(body))
	if net.ParseIP(value) == nil {
		return ""
	}
	return value
}

func encodeReport(report EdgeReport) string {
	data, _ := json.Marshal(report)
	return string(data)
}
