package main

import (
	"log"
	"regexp"
	"strings"
	"sync"
)

// engineLog keeps the last few hundred native log lines for the in-app log
// viewer. Nothing is written to logcat. Secrets are redacted before storage.
type engineLogBuffer struct {
	mu    sync.Mutex
	lines []string
	max   int
}

var engineLog = &engineLogBuffer{max: 500}

var (
	keyPattern      = regexp.MustCompile(`[0-9a-fA-F]{64}`)
	depPattern      = regexp.MustCompile(`AKfycb[A-Za-z0-9_.-]*`)
	proxyURLPattern = regexp.MustCompile(`socks5://[^\s]+`)
)

func redactLogLine(line string) string {
	line = keyPattern.ReplaceAllString(line, "[key]")
	line = depPattern.ReplaceAllString(line, "[deployment]")
	line = proxyURLPattern.ReplaceAllString(line, "socks5://[redacted]")
	return line
}

func (b *engineLogBuffer) Write(p []byte) (int, error) {
	text := string(p)
	for _, line := range strings.Split(strings.TrimRight(text, "\n"), "\n") {
		if line == "" {
			continue
		}
		if len(line) > 600 {
			line = line[:600] + "…"
		}
		line = redactLogLine(line)
		b.mu.Lock()
		b.lines = append(b.lines, line)
		if len(b.lines) > b.max {
			b.lines = b.lines[len(b.lines)-b.max:]
		}
		b.mu.Unlock()
	}
	return len(p), nil
}

func (b *engineLogBuffer) snapshot() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return strings.Join(b.lines, "\n")
}

func (b *engineLogBuffer) clear() {
	b.mu.Lock()
	b.lines = nil
	b.mu.Unlock()
}

func init() {
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)
	log.SetOutput(engineLog)
}
