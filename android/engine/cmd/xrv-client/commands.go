package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"strings"
	"time"
)

func probeClient(args []string) error {
	fs := flag.NewFlagSet("probe", flag.ExitOnError)
	configPathFlag := fs.String("config", configPath(), "configuration file")
	write := fs.Bool("write", false, "save the fastest edge")
	_ = fs.Parse(args)
	cfg, err := loadConfig(*configPathFlag)
	if err != nil {
		return err
	}
	report := probeEdges(cfg.GoogleCandidates, edgeProbeTimeout)
	for _, result := range report.Results {
		if result.OK {
			fmt.Printf("%-16s %d ms\n", result.IP, result.MS)
		} else {
			fmt.Printf("%-16s unavailable (%s)\n", result.IP, result.Error)
		}
	}
	if report.Best == "" {
		return fmt.Errorf("%s", report.Error)
	}
	fmt.Printf("Fastest: %s (%d ms)\n", report.Best, report.BestMS)
	if *write {
		cfg.GoogleIP = report.Best
		if err := saveConfig(*configPathFlag, cfg); err != nil {
			return err
		}
		fmt.Printf("Saved edge %s to %s\n", report.Best, *configPathFlag)
	}
	return nil
}

func testClient(args []string) error {
	fs := flag.NewFlagSet("test", flag.ExitOnError)
	configPathFlag := fs.String("config", configPath(), "configuration file")
	_ = fs.Parse(args)
	cfg, err := loadConfig(*configPathFlag)
	if err != nil {
		return err
	}
	if conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", cfg.SocksPort), 2*time.Second); err != nil {
		return fmt.Errorf("XRV is not listening on 127.0.0.1:%d; start it with: xrv-client run", cfg.SocksPort)
	} else {
		_ = conn.Close()
	}
	result := testTunnel(cfg.SocksPort, cfg.SocksUser, cfg.SocksPass, 20*time.Second)
	if !result.OK {
		return fmt.Errorf("tunnel test failed: %s", result.Error)
	}
	real := directIP(10 * time.Second)
	fmt.Printf("Tunnel exit IP: %s\n", result.ExitIP)
	fmt.Printf("Latency:        %d ms\n", result.MS)
	if real != "" {
		fmt.Printf("Direct IP:      %s\n", real)
		if real == result.ExitIP {
			fmt.Println("Warning: exit IP equals direct IP; traffic may not be using XRV.")
		} else {
			fmt.Println("Path: direct -> XRV exit (working).")
		}
	}
	return nil
}

func checkClient(args []string) error {
	fs := flag.NewFlagSet("check", flag.ExitOnError)
	configPathFlag := fs.String("config", configPath(), "configuration file")
	_ = fs.Parse(args)
	cfg, err := loadConfig(*configPathFlag)
	if err != nil {
		return err
	}
	pid := readPID()
	if pid == 0 || !pidAlive(pid) {
		return fmt.Errorf("XRV is not running; start it with: xrv-client run")
	}
	fmt.Printf("PASS  process (PID %d)\n", pid)
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", cfg.SocksPort), 2*time.Second)
	if err != nil {
		return fmt.Errorf("FAIL  local SOCKS listener 127.0.0.1:%d is closed", cfg.SocksPort)
	}
	_ = conn.Close()
	fmt.Printf("PASS  local SOCKS listener 127.0.0.1:%d\n", cfg.SocksPort)
	result := testTunnel(cfg.SocksPort, cfg.SocksUser, cfg.SocksPass, 20*time.Second)
	if !result.OK {
		return fmt.Errorf("FAIL  live tunnel test: %s", result.Error)
	}
	fmt.Printf("PASS  live tunnel test (exit %s, %d ms)\n", result.ExitIP, result.MS)
	real := directIP(10 * time.Second)
	if real != "" {
		fmt.Printf("INFO  direct IP %s\n", real)
		if real == result.ExitIP {
			fmt.Println("WARN  exit IP equals direct IP; verify the tunnel path")
		} else {
			fmt.Println("PASS  traffic path direct -> XRV exit")
		}
	}
	fmt.Println("\nVerdict: critical checks passed.")
	return nil
}

func logsClient(args []string) error {
	fs := flag.NewFlagSet("logs", flag.ExitOnError)
	_ = fs.Parse(args)
	text, err := readLog()
	if err != nil {
		return err
	}
	fmt.Print(text)
	return nil
}

func configClient(args []string) error {
	fs := flag.NewFlagSet("config", flag.ExitOnError)
	configPathFlag := fs.String("config", configPath(), "configuration file")
	_ = fs.Parse(args)
	cfg, err := loadConfig(*configPathFlag)
	if err != nil {
		return err
	}
	data, _ := json.MarshalIndent(redactedConfig(cfg), "", "  ")
	fmt.Println(string(data))
	return nil
}

func usage() {
	fmt.Printf(`XRV Client %s — encrypted relay client for Linux

Usage:
  xrv-client setup [options]     configure deployments, key, port and Google edge
  xrv-client run                 start the authenticated local SOCKS5 proxy
  xrv-client probe [--write]     test Google edge IPv4 candidates
  xrv-client test                verify the real exit IP through the tunnel
  xrv-client check               process, listener and live tunnel health check
  xrv-client status              show whether XRV is running
  xrv-client stop                stop the background client
  xrv-client logs                show the last log lines
  xrv-client config              show non-secret configuration (redacted)
  xrv-client version             print the version

Setup examples:
  xrv-client setup
  xrv-client setup --non-interactive --yes \
    --deployment AKfycb... --tunnel-key "$(sudo cat /etc/xrv/tunnel_key)" \
    --socks-port 1080

Proxy mode:
  Use socks5://username:password@127.0.0.1:port#XRV in v2rayNG, a browser,
  or any app that accepts a SOCKS5 upstream. The Copy output from setup/run
  includes the generated credentials and the XRV profile name.

Linux note:
  This package provides the same encrypted relay engine, authenticated local
  SOCKS5 proxy, edge probing, tunnel test and logs as the Android app's
  proxy-only mode. Android TUN/per-app routing is provided by Android's
  VpnService; on Linux, point applications at the local proxy or use your
  system's VPN tooling.
`, version)
}

func main() {
	if len(os.Args) < 2 {
		usage()
		return
	}
	command := strings.ToLower(os.Args[1])
	var err error
	switch command {
	case "setup":
		err = setupClient(os.Args[2:])
	case "run", "start":
		config := configPath()
		if len(os.Args) > 2 && !strings.HasPrefix(os.Args[2], "-") {
			config = os.Args[2]
		}
		err = runClient(config)
	case "probe":
		err = probeClient(os.Args[2:])
	case "test":
		err = testClient(os.Args[2:])
	case "check", "doctor":
		err = checkClient(os.Args[2:])
	case "status":
		statusClient(configPath())
	case "stop":
		err = stopClient()
	case "logs":
		err = logsClient(os.Args[2:])
	case "config":
		err = configClient(os.Args[2:])
	case "version", "--version", "-V":
		fmt.Printf("XRV Client %s\n", version)
	case "help", "--help", "-h":
		usage()
	default:
		usage()
		err = fmt.Errorf("unknown command: %s", command)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "xrv-client: %v\n", err)
		os.Exit(1)
	}
}
