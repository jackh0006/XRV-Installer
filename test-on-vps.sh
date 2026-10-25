#!/usr/bin/env bash
# XRV v1.0 — Live VPS Verification Script
# Run on the VPS AFTER: sudo bash xrv-install.sh (option 2)

set -Eeuo pipefail

GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; CYAN='\033[36m'; RESET='\033[0m'
CHECK="✅"; CROSS="❌"; WARN="⚠️"

ok()   { printf "%s %s[OK]%s %s\n" "$CHECK" "$GREEN" "$RESET" "$*"; }
fail() { printf "%s %s[FAIL]%s %s\n" "$CROSS" "$RED" "$RESET" "$*"; }
warn() { printf "%s %s[WARN]%s %s\n" "$WARN" "$YELLOW" "$RESET" "$*"; }
info() { printf "%s[INFO]%s %s\n" "$CYAN" "$RESET" "$*"; }

echo -e "\n${CYAN}=== XRV v1.0 VPS Post-Install Verification ===${RESET}\n"

# 1. Service status
info "Checking systemd services..."
systemctl is-active --quiet xrv-relay && ok "xrv-relay active" || fail "xrv-relay NOT active"
systemctl is-active --quiet haproxy && ok "haproxy active" || warn "haproxy not running (HTTP mode?)"

# 2. Binary & config
[[ -x /root/xrv-server ]] && ok "xrv-server binary present" || fail "xrv-server binary missing"
[[ -f /root/xrv-server-config.json ]] && ok "xrv-server config present" || fail "xrv-server config missing"
[[ -f /root/xrv-tunnel-key.txt ]] && ok "Tunnel key present" || fail "Tunnel key missing"
[[ "$(stat -c %a /root/xrv-tunnel-key.txt 2>/dev/null)" == "600" ]] && ok "Tunnel key perms 600" || warn "Tunnel key perms not 600"

# 3. Backend health
code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:9443/healthz 2>/dev/null || true)
[[ "$code" =~ ^[23][0-9][0-9]$ ]] && ok "Backend healthz: HTTP $code" || fail "Backend healthz failed (HTTP $code)"

# 4. Public endpoint (if TLS mode)
if [[ -f /etc/xrv/state.conf ]]; then
  source /etc/xrv/state.conf
  if [[ "${XRV_MODE:-http}" == "tls" && -n "${XRV_DOMAIN:-}" ]]; then
    code=$(curl -k -m 8 -s -o /dev/null -w '%{http_code}' "https://${XRV_DOMAIN}:${XRV_PUBLIC_PORT:-8443}/healthz" 2>/dev/null || true)
    [[ "$code" =~ ^[23][0-9][0-9]$ ]] && ok "Public endpoint: HTTP $code" || fail "Public endpoint failed (HTTP $code)"
    [[ -f "/etc/haproxy/certs/${XRV_DOMAIN}.pem" ]] && ok "HAProxy cert present" || fail "HAProxy cert missing"
  fi
fi

# 5. HAProxy config validation
haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 && ok "HAProxy config valid" || warn "HAProxy config has issues"

# 6. Ports listening
ss -tln | grep -q ':9443 ' && ok "Backend port 9443 listening" || warn "Backend port 9443 not listening"
ss -tln | grep -q ':8443 ' && ok "HAProxy port 8443 listening" || warn "HAProxy port 8443 not listening"

# 7. Journal (last 5 lines)
info "Recent xrv-relay logs:"
journalctl -u xrv-relay -n 5 --no-pager 2>/dev/null | sed 's/^/  /'

echo -e "\n${CYAN}=== VPS Verification Complete ===${RESET}\n"
