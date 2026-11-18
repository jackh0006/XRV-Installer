package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"

	"golang.org/x/term"
)

type stringList []string

func (s *stringList) String() string { return strings.Join(*s, ",") }
func (s *stringList) Set(value string) error {
	*s = append(*s, value)
	return nil
}

func ask(scanner *bufio.Scanner, label, fallback string) string {
	if fallback != "" {
		fmt.Printf("%s [%s]: ", label, fallback)
	} else {
		fmt.Printf("%s: ", label)
	}
	if !scanner.Scan() {
		return fallback
	}
	value := strings.TrimSpace(scanner.Text())
	if value == "" {
		return fallback
	}
	return value
}

func askSecret(label string) (string, error) {
	fmt.Printf("%s: ", label)
	if term.IsTerminal(int(os.Stdin.Fd())) {
		data, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Println()
		if err != nil {
			return "", err
		}
		return strings.TrimSpace(string(data)), nil
	}
	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		return "", fmt.Errorf("no value entered")
	}
	return strings.TrimSpace(scanner.Text()), nil
}

func setupClient(args []string) error {
	fs := flag.NewFlagSet("setup", flag.ExitOnError)
	configPathFlag := fs.String("config", configPath(), "configuration file")
	nonInteractive := fs.Bool("non-interactive", false, "never prompt")
	yes := fs.Bool("yes", false, "overwrite without asking")
	port := fs.Int("socks-port", defaultPort, "local SOCKS5 port")
	var deployments stringList
	fs.Var(&deployments, "deployment", "deployment ID (repeat for up to four)")
	deploymentCSV := fs.String("deployments", "", "comma-separated deployment IDs")
	key := fs.String("tunnel-key", "", "64-character tunnel key")
	edge := fs.String("edge", "", "force this Google edge IPv4")
	edgesCSV := fs.String("edges", "", "comma-separated Google edge candidates")
	noProbe := fs.Bool("no-probe", false, "skip the Google edge test")
	_ = fs.Parse(args)

	if _, err := os.Stat(*configPathFlag); err == nil && !*yes {
		if *nonInteractive {
			return fmt.Errorf("configuration exists; pass --yes to overwrite")
		}
		scanner := bufio.NewScanner(os.Stdin)
		answer := ask(scanner, "Configuration exists. Overwrite it? (y/N)", "n")
		if strings.ToLower(answer) != "y" && strings.ToLower(answer) != "yes" {
			return fmt.Errorf("canceled")
		}
	}

	var ids []string
	ids = append(ids, deployments...)
	for _, part := range strings.Split(*deploymentCSV, ",") {
		if value := strings.TrimSpace(part); value != "" {
			ids = append(ids, value)
		}
	}
	tunnelKey := *key

	scanner := bufio.NewScanner(os.Stdin)
	if !*nonInteractive {
		if len(ids) == 0 {
			fmt.Println("Paste the Apps Script deployment ID (starts with AKfycb).")
			ids = append(ids, ask(scanner, "Deployment ID 1", ""))
			for len(ids) < 4 {
				more := ask(scanner, "Add another deployment ID? (y/N)", "n")
				if strings.ToLower(more) != "y" && strings.ToLower(more) != "yes" {
					break
				}
				ids = append(ids, ask(scanner, fmt.Sprintf("Deployment ID %d", len(ids)+1), ""))
			}
		}
		if tunnelKey == "" {
			fmt.Println("Get the key on the server with: sudo cat /etc/xrv/tunnel_key")
			value, err := askSecret("Tunnel key (64 hex characters)")
			if err != nil {
				return err
			}
			tunnelKey = value
		}
		if !fsWasSet(fs, "socks-port") {
			value := ask(scanner, "Local SOCKS5 port", strconv.Itoa(defaultPort))
			parsed, err := strconv.Atoi(value)
			if err == nil {
				*port = parsed
			}
		}
	}
	if len(ids) == 0 {
		return fmt.Errorf("at least one deployment ID is required")
	}
	if tunnelKey == "" {
		return fmt.Errorf("the tunnel key is required")
	}

	candidates := append([]string(nil), defaultEdges...)
	if *edgesCSV != "" {
		candidates = nil
		for _, part := range strings.Split(*edgesCSV, ",") {
			if value := strings.TrimSpace(part); value != "" {
				candidates = append(candidates, value)
			}
		}
	}
	candidates = uniqueIPv4(candidates)
	if len(candidates) == 0 {
		candidates = append([]string(nil), defaultEdges...)
	}
	selected := strings.TrimSpace(*edge)
	if selected == "" && !*noProbe {
		fmt.Printf("Testing Google edges: %s\n", strings.Join(candidates, ", "))
		report := probeEdges(candidates, edgeProbeTimeout)
		for _, result := range report.Results {
			if result.OK {
				fmt.Printf("  %-16s %d ms\n", result.IP, result.MS)
			} else {
				fmt.Printf("  %-16s unavailable\n", result.IP)
			}
		}
		if report.Best != "" {
			selected = report.Best
			fmt.Printf("Fastest edge: %s (%d ms)\n", report.Best, report.BestMS)
		} else {
			selected = defaultEdge
			fmt.Printf("No edge answered; using %s\n", selected)
		}
	}
	if selected == "" {
		selected = defaultEdge
	}

	user, pass := newCredentials()
	cfg := &Config{
		Deployments:      ids,
		TunnelKey:        tunnelKey,
		SocksPort:        *port,
		SocksUser:        user,
		SocksPass:        pass,
		GoogleIP:         selected,
		GoogleCandidates: candidates,
		SNIHosts:         defaultSNIHosts(),
		CoalesceMs:       defaultCoalesce,
		IdleSlots:        defaultIdleFor(len(ids)),
	}
	if err := saveConfig(*configPathFlag, cfg); err != nil {
		return err
	}
	fmt.Printf("\nConfiguration saved: %s (mode 600)\n", *configPathFlag)
	fmt.Printf("Proxy: %s\n", proxyURL(cfg))
	fmt.Printf("Edge:  %s\n", cfg.GoogleIP)
	fmt.Println("\nNext steps:")
	fmt.Println("  xrv-client run          # run in this terminal")
	fmt.Println("  systemctl --user enable --now xrv-client   # run in the background")
	fmt.Println("  xrv-client test         # verify the real tunnel path")
	return nil
}

func fsWasSet(fs *flag.FlagSet, name string) bool {
	set := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == name {
			set = true
		}
	})
	return set
}
