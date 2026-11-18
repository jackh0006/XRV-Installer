package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const (
	version         = "2.0.0"
	defaultEdge     = "216.239.38.120"
	defaultPort     = 1080
	defaultCoalesce = 25
)

var defaultEdges = []string{
	"216.239.32.120",
	"216.239.34.120",
	"216.239.36.120",
	"216.239.38.120",
}

var deploymentPattern = regexp.MustCompile(`^AKfycb[A-Za-z0-9_-]{44,}$`)

// Config is deliberately the same shape as the Android client's profile plus
// its non-secret settings. The JSON names match the Android bridge.
type Config struct {
	Deployments      []string `json:"deployments"`
	TunnelKey        string   `json:"tunnelKey"`
	SocksPort        int      `json:"socksPort"`
	SocksUser        string   `json:"socksUser"`
	SocksPass        string   `json:"socksPass"`
	GoogleIP         string   `json:"googleIp"`
	GoogleCandidates []string `json:"googleCandidates"`
	SNIHosts         []string `json:"sniHosts"`
	CoalesceMs       int      `json:"coalesceMs"`
	IdleSlots        int      `json:"idleSlots"`
}

func defaultSNIHosts() []string {
	return []string{"www.google.com", "mail.google.com", "accounts.google.com"}
}

func configPath() string {
	if value := os.Getenv("XRV_CONFIG"); value != "" {
		return value
	}
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, ".config")
	}
	return filepath.Join(base, "xrv", "client.json")
}

func stateDir() string {
	if value := os.Getenv("XRV_STATE_DIR"); value != "" {
		return value
	}
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, ".local", "state")
	}
	return filepath.Join(base, "xrv")
}

func pidPath() string { return filepath.Join(stateDir(), "client.pid") }
func logPath() string { return filepath.Join(stateDir(), "client.log") }

func frontingAddress(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	if _, _, err := net.SplitHostPort(value); err == nil {
		return value
	}
	return net.JoinHostPort(value, "443")
}

func newCredentials() (string, string) {
	user := make([]byte, 6)
	pass := make([]byte, 16)
	_, _ = rand.Read(user)
	_, _ = rand.Read(pass)
	return "xrv" + hex.EncodeToString(user), hex.EncodeToString(pass)
}

func normalizeConfig(c *Config) {
	c.TunnelKey = strings.ToLower(strings.TrimSpace(c.TunnelKey))
	for i, id := range c.Deployments {
		c.Deployments[i] = strings.TrimSpace(id)
	}
	if c.SocksPort == 0 {
		c.SocksPort = defaultPort
	}
	if c.SocksUser == "" || c.SocksPass == "" {
		c.SocksUser, c.SocksPass = newCredentials()
	}
	if c.GoogleIP == "" {
		c.GoogleIP = defaultEdge
	}
	if len(c.GoogleCandidates) == 0 {
		c.GoogleCandidates = append([]string(nil), defaultEdges...)
	}
	if len(c.SNIHosts) == 0 {
		c.SNIHosts = defaultSNIHosts()
	}
	if c.CoalesceMs < 0 {
		c.CoalesceMs = 0
	}
	if c.IdleSlots == 0 {
		c.IdleSlots = defaultIdleFor(len(c.Deployments))
	}
	if c.IdleSlots < 1 || c.IdleSlots > 3 {
		c.IdleSlots = defaultIdleFor(len(c.Deployments))
	}
}

func defaultIdleFor(deployments int) int {
	switch {
	case deployments >= 3:
		return 3
	case deployments == 2:
		return 2
	default:
		return 1
	}
}

func validateConfig(c *Config) error {
	// Remove blank deployment entries.
	ids := c.Deployments[:0]
	for _, id := range c.Deployments {
		if strings.TrimSpace(id) != "" {
			ids = append(ids, strings.TrimSpace(id))
		}
	}
	c.Deployments = ids
	if len(c.Deployments) < 1 || len(c.Deployments) > 4 {
		return fmt.Errorf("use between one and four deployment IDs")
	}
	for _, id := range c.Deployments {
		if !deploymentPattern.MatchString(id) {
			return fmt.Errorf("invalid deployment ID: %s", id)
		}
	}
	if len(c.TunnelKey) != 64 {
		return fmt.Errorf("the tunnel key must be exactly 64 hex characters")
	}
	if _, err := hex.DecodeString(c.TunnelKey); err != nil {
		return fmt.Errorf("the tunnel key contains non-hex characters")
	}
	if c.SocksPort < 1024 || c.SocksPort > 65535 {
		return fmt.Errorf("the SOCKS port must be between 1024 and 65535")
	}
	if c.SocksUser == "" || c.SocksPass == "" {
		return fmt.Errorf("SOCKS credentials are missing")
	}
	host := c.GoogleIP
	if h, _, err := net.SplitHostPort(c.GoogleIP); err == nil {
		host = h
	}
	if ip := net.ParseIP(host); ip == nil || ip.To4() == nil {
		return fmt.Errorf("the Google edge must be an IPv4 address")
	}
	if c.CoalesceMs < 0 || c.CoalesceMs > 1000 {
		return fmt.Errorf("coalescing must be between 0 and 1000 ms")
	}
	if c.IdleSlots < 1 || c.IdleSlots > 3 {
		return fmt.Errorf("idle polls must be between 1 and 3")
	}
	return nil
}

func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var c Config
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("invalid configuration: %w", err)
	}
	normalizeConfig(&c)
	if err := validateConfig(&c); err != nil {
		return nil, err
	}
	return &c, nil
}

func saveConfig(path string, c *Config) error {
	normalizeConfig(c)
	if err := validateConfig(c); err != nil {
		return err
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func proxyURL(c *Config) string {
	return fmt.Sprintf("socks5://%s:%s@127.0.0.1:%d#XRV", c.SocksUser, c.SocksPass, c.SocksPort)
}

func redactedConfig(c *Config) Config {
	out := *c
	out.TunnelKey = "[redacted]"
	out.SocksUser = "[redacted]"
	out.SocksPass = "[redacted]"
	return out
}
