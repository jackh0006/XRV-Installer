package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/kianmhz/GooseRelayVPN/internal/carrier"
	"github.com/kianmhz/GooseRelayVPN/internal/session"
	"github.com/kianmhz/GooseRelayVPN/internal/socks"
)

func writePID() error {
	if err := os.MkdirAll(stateDir(), 0o700); err != nil {
		return err
	}
	return os.WriteFile(pidPath(), []byte(strconv.Itoa(os.Getpid())), 0o600)
}

func readPID() int {
	data, err := os.ReadFile(pidPath())
	if err != nil {
		return 0
	}
	pid, _ := strconv.Atoi(string(data))
	return pid
}

func removePID() { _ = os.Remove(pidPath()) }

func runClient(configPath string) error {
	cfg, err := loadConfig(configPath)
	if err != nil {
		return err
	}
	if pid := readPID(); pidAlive(pid) {
		return fmt.Errorf("XRV is already running (PID %d)", pid)
	}
	removePID()

	file, err := setupLog()
	if err != nil {
		return err
	}
	defer file.Close()

	urls := make([]string, 0, len(cfg.Deployments))
	for _, id := range cfg.Deployments {
		urls = append(urls, "https://script.google.com/macros/s/"+id+"/exec")
	}
	client, err := carrier.New(carrier.Config{
		ScriptURLs: urls,
		AESKeyHex:  cfg.TunnelKey,
		Fronting: carrier.FrontingConfig{
			GoogleIP: frontingAddress(cfg.GoogleIP),
			SNIHosts: cfg.SNIHosts,
		},
		CoalesceStep:       time.Duration(cfg.CoalesceMs) * time.Millisecond,
		CoalesceMax:        time.Duration(cfg.CoalesceMs*25) * time.Millisecond,
		IdleSlotsPerBucket: cfg.IdleSlots,
	})
	if err != nil {
		return err
	}
	listener, err := net.Listen("tcp4", fmt.Sprintf("127.0.0.1:%d", cfg.SocksPort))
	if err != nil {
		return fmt.Errorf("local SOCKS port %d is unavailable", cfg.SocksPort)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() { _ = client.Run(ctx) }()
	go func() {
		_ = socks.ServeListener(ctx, listener, cfg.SocksUser, cfg.SocksPass, false,
			socks.SessionFactory(func(target string) *session.Session {
				return client.NewSession(target)
			}))
	}()
	if err := writePID(); err != nil {
		_ = listener.Close()
		return err
	}
	defer removePID()

	fmt.Printf("XRV proxy ready.\n")
	fmt.Printf("  Proxy: %s\n", proxyURL(cfg))
	fmt.Printf("  Mode:  proxy only (loopback)\n")
	fmt.Printf("  Edge:  %s\n", cfg.GoogleIP)
	fmt.Printf("  Log:   %s\n", logPath())
	fmt.Printf("Press Ctrl+C to stop.\n")

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)
	<-signals
	signal.Stop(signals)

	shutdown, done := context.WithTimeout(context.Background(), 3*time.Second)
	client.Shutdown(shutdown)
	done()
	cancel()
	fmt.Println("XRV stopped.")
	return nil
}

func stopClient() error {
	pid := readPID()
	if pid == 0 {
		return fmt.Errorf("XRV is not running (no pid file)")
	}
	if !pidAlive(pid) {
		removePID()
		return fmt.Errorf("XRV is not running (stale pid file removed)")
	}
	process, err := os.FindProcess(pid)
	if err != nil {
		return err
	}
	if err := process.Signal(syscall.SIGTERM); err != nil {
		return err
	}
	for i := 0; i < 50; i++ {
		if !pidAlive(pid) {
			removePID()
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return fmt.Errorf("XRV did not stop within 5 seconds (PID %d)", pid)
}

func statusClient(configPath string) {
	cfg, err := loadConfig(configPath)
	if err != nil {
		fmt.Printf("Configuration: unavailable (%v)\n", err)
		cfg = nil
	}
	pid := readPID()
	if pid != 0 && pidAlive(pid) {
		fmt.Printf("XRV is running (PID %d).\n", pid)
	} else {
		fmt.Println("XRV is not running.")
	}
	if cfg != nil {
		fmt.Printf("Local SOCKS: socks5://127.0.0.1:%d (username/password required)\n", cfg.SocksPort)
		fmt.Printf("Selected edge: %s\n", cfg.GoogleIP)
		if conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", cfg.SocksPort), time.Second); err == nil {
			_ = conn.Close()
			fmt.Println("Listener: open")
		} else {
			fmt.Println("Listener: closed")
		}
	}
}
