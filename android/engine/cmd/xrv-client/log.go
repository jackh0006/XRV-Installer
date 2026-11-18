package main

import (
	"io"
	"log"
	"os"
	"regexp"
	"strings"
	"sync"
	"syscall"
)

var (
	logKeyPattern  = regexp.MustCompile(`[0-9a-fA-F]{64}`)
	logDepPattern  = regexp.MustCompile(`AKfycb[A-Za-z0-9_.-]*`)
	logSockPattern = regexp.MustCompile(`socks5://[^\s]+`)
)

func redactLog(value string) string {
	value = logKeyPattern.ReplaceAllString(value, "[key]")
	value = logDepPattern.ReplaceAllString(value, "[deployment]")
	value = logSockPattern.ReplaceAllString(value, "socks5://[redacted]")
	return value
}

type redactWriter struct {
	mu sync.Mutex
	w  io.Writer
}

func (r *redactWriter) Write(p []byte) (int, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	_, err := r.w.Write([]byte(redactLog(string(p))))
	if err != nil {
		return 0, err
	}
	return len(p), nil
}

func setupLog() (*os.File, error) {
	if err := os.MkdirAll(stateDir(), 0o700); err != nil {
		return nil, err
	}
	file, err := os.OpenFile(logPath(), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return nil, err
	}
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)
	log.SetOutput(io.MultiWriter(os.Stderr, &redactWriter{w: file}))
	return file, nil
}

func readLog() (string, error) {
	data, err := os.ReadFile(logPath())
	if err != nil {
		if os.IsNotExist(err) {
			return "No log entries yet.\n", nil
		}
		return "", err
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) > 500 {
		lines = lines[len(lines)-500:]
	}
	return strings.Join(lines, "\n") + "\n", nil
}

func pidAlive(pid int) bool {
	if pid <= 0 {
		return false
	}
	process, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	return process.Signal(syscall.Signal(0)) == nil
}
