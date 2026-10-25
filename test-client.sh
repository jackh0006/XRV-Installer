#!/usr/bin/env bash
# XRV v1.0 — Live Client Verification Script
# Run on client machine AFTER: bash xrv-install.sh (option 3) then ./start-xrv.sh

set -Eeuo pipefail

GREEN='\033[32m'; RED='\033[31m'; YELLOW='\033[33m'; CYAN='\033[36m'; RESET='\033[0m'
CHECK="✅"; CROSS="❌"

ok()   { printf "%s %s[OK]%s %s\n" "$CHECK" "$GREEN" "$RESET" "$*"; }
fail() { printf "%s %s[FAIL]%s %s\n" "$CROSS" "$RED" "$RESET" "$*"; }
info() { printf "%s[INFO]%s %s\n" "$CYAN" "$RESET" "$*"; }

CLIENT_HOME="${XRV_CLIENT_HOME:-$HOME/xrv}"

echo -e "\n${CYAN}=== XRV v1.0 Client Post-Install Verification ===${RESET}\n"

# 1. Config & binary
[[ -f "$CLIENT_HOME/client_config.json" ]] && ok "client_config.json present" || fail "client_config.json missing"
[[ -x "$CLIENT_HOME/goose-client" ]] && ok "goose-client binary executable" || fail "goose-client binary missing"

# 2. Port listening
port=$(python3 -c 'import json; print(json.load(open("'"$CLIENT_HOME/client_config.json"'"))["socks_port"])' 2>/dev/null || echo 1080)
ss -tln 2>/dev/null | grep -q ":${port} " && ok "SOCKS5 port $port listening" || fail "SOCKS5 port $port NOT listening (run ./start-xrv.sh first)"

# 3. Live SOCKS5 test
if command -v curl >/dev/null 2>&1; then
  info "Testing SOCKS5 tunnel..."
  liveip=$(curl -s --noproxy '*' --max-time 15 --socks5-hostname "127.0.0.1:${port}" https://api.ipify.org 2>/dev/null || true)
  if [[ -n "$liveip" ]]; then
    ok "SOCKS5 LIVE — exit IP: $liveip"
    # Verify it's not our real IP
    realip=$(curl -s --max-time 6 https://api.ipify.org 2>/dev/null || true)
    [[ "$liveip" != "$realip" ]] && ok "Traffic routed through VPS (IP differs from local: $realip)" || warn "Exit IP matches local IP — check tunnel"
  else
    fail "SOCKS5 tunnel did not respond (client stuck?)"
  fi
fi

# 4. Config validation
if command -v python3 >/dev/null 2>&1; then
  python3 - "$CLIENT_HOME/client_config.json" <<'PYEOF' 2>/dev/null && ok "Client config schema valid" || warn "Client config schema issues"
import json, sys, re
with open(sys.argv[1]) as f: c = json.load(f)
assert c.get("socks_port") == 1080
assert isinstance(c.get("script_keys"), list) and len(c["script_keys"]) >= 1
assert len(c.get("tunnel_key", "")) == 64
assert c.get("coalesce_step_ms", 25) >= 25
assert c.get("deployment_pool_enabled", True) == True
assert "health_check_interval_ms" in c
print("VALID")
PYEOF
fi

# 5. Deployments count
if [[ -f "$CLIENT_HOME/client_config.json" ]]; then
  dep_count=$(python3 -c 'import json; print(len(json.load(open("'"$CLIENT_HOME/client_config.json"'"))["script_keys"]))' 2>/dev/null || echo 0)
  ok "Deployment IDs configured: $dep_count"
fi

# 6. Logs check
[[ -f "$CLIENT_HOME/xrv-client.log" ]] && info "Client log: $CLIENT_HOME/xrv-client.log" || warn "No client log yet"

echo -e "\n${CYAN}=== Client Verification Complete ===${RESET}\n"
echo "If all OK: Firefox → Settings → Network → Manual proxy → SOCKS5 127.0.0.1:$port"
echo "Then visit https://api.ipify.org — must show VPS IP"
