package main

import (
	"os"
	"strings"
	"testing"
	"time"
)

func TestRedactLogLine(t *testing.T) {
	key := strings.Repeat("ab", 32)
	deployment := "AKfy" + "cbExample123"
	line := "carrier key=" + key + " deployment=" + deployment + " socks5://user:pass@127.0.0.1:1080"
	got := redactLogLine(line)
	if strings.Contains(got, key) {
		t.Fatalf("key was not redacted: %s", got)
	}
	if strings.Contains(got, deployment) {
		t.Fatalf("deployment was not redacted: %s", got)
	}
	if strings.Contains(got, "user:pass") {
		t.Fatalf("proxy credentials were not redacted: %s", got)
	}
}

func TestProbeLive(t *testing.T) {
	if os.Getenv("XRV_LIVE_TEST") != "1" {
		t.Skip("set XRV_LIVE_TEST=1 to probe Google edges")
	}
	report := probeEdges([]string{
		"216.239.32.120",
		"216.239.34.120",
		"216.239.36.120",
		"216.239.38.120",
	}, 6*time.Second)
	for _, result := range report.Results {
		t.Logf("%s ok=%v status=%d ms=%d error=%s", result.IP, result.OK, result.Status, result.MS, result.Error)
	}
	t.Logf("best=%s bestMs=%d error=%s", report.Best, report.BestMS, report.Error)
	if report.Error != "" && report.Best == "" {
		t.Logf("no edge answered on this network; this is allowed")
	}
}
