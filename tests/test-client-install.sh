#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# End-to-end offline client install in a temporary home.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "${ROOT}/tests/lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_DIR="${TMP}/home"
LOG="${TMP}/install.log"
ID1="AKfycb$(printf 'H%.0s' {1..60})"
ID2="AKfycb$(printf 'I%.0s' {1..60})"
KEY="$(printf 'd%.0s' {1..64})"

printf '== offline client install\n'
XRV_LOG_FILE="$LOG" bash "${ROOT}/xrv-client.sh" \
  --non-interactive --yes \
  --home "$HOME_DIR" \
  --relay vpn.example.com --relay-port 8443 --relay-scheme https \
  --deployment "${ID1}:acct-a" \
  --deployment "${ID2}:acct-a" \
  --tunnel-key "$KEY" \
  --socks-port 19080 \
  --offline-binary "/usr/bin/true" \
  --skip-arch-check \
  --no-probe --no-health --no-start >"${TMP}/stdout" 2>&1
assert_eq "0" "$?" "client install exited 0"

assert_file "client binary installed" "${HOME_DIR}/goose-client"
assert_file "config installed" "${HOME_DIR}/client_config.json"
assert_file "Code.gs installed" "${HOME_DIR}/Code.gs"
assert_file "guide installed" "${HOME_DIR}/GUIDE.txt"
assert_file "start script installed" "${HOME_DIR}/start-xrv.sh"
assert_file "stop script installed" "${HOME_DIR}/stop-xrv.sh"
assert_file "status script installed" "${HOME_DIR}/status-xrv.sh"
assert_file "state file installed" "${HOME_DIR}/.xrv-state"
assert_mode "config is mode 600" "${HOME_DIR}/client_config.json" "600"
assert_mode "state is mode 600" "${HOME_DIR}/.xrv-state" "600"
assert_mode "start script is executable" "${HOME_DIR}/start-xrv.sh" "755"

printf '\n== config content\n'
if command -v python3 >/dev/null 2>&1; then
  python3 - "${HOME_DIR}/client_config.json" "$ID1" "$ID2" "$KEY" <<'PY'
import json, sys
path, id1, id2, key = sys.argv[1:5]
with open(path) as f:
    c = json.load(f)
assert c["tunnel_key"] == key
assert c["socks_port"] == 19080
assert c["socks_host"] == "127.0.0.1"
assert c["coalesce_step_ms"] == 25
assert c["idle_slots_per_bucket"] == 2
assert c["socks_user"] == "" and c["socks_pass"] == ""
assert [x["id"] for x in c["script_keys"]] == [id1, id2]
assert all(x["account"] == "acct-a" for x in c["script_keys"])
assert c["google_host"].count(".") == 3
assert c["sni"] == ["www.google.com", "mail.google.com", "accounts.google.com"]
PY
  assert_eq "0" "$?" "config matches the expected schema and values"
fi

printf '\n== secret hygiene\n'
if grep -q "$KEY" "$LOG" 2>/dev/null; then
  t_not_ok "tunnel key leaked into the installer log"
else
  t_ok "tunnel key is not present in the installer log"
fi
if grep -q "$ID1" "$LOG" 2>/dev/null; then
  t_not_ok "deployment ID leaked into the installer log"
else
  t_ok "deployment ID is not present in the installer log"
fi

printf '\n== local SOCKS auth config\n'
HOME2="${TMP}/home2"
XRV_LOG_FILE="${TMP}/install2.log" bash "${ROOT}/xrv-client.sh" \
  --non-interactive --yes \
  --home "$HOME2" \
  --relay 203.0.113.10 --relay-port 8443 --relay-scheme http \
  --deployment "${ID1}:acct-a" \
  --tunnel-key "$KEY" \
  --socks-port 19081 \
  --socks-user tester --socks-pass 'p@ss"word' \
  --offline-binary "/usr/bin/true" \
  --skip-arch-check \
  --no-probe --no-health --no-start >"${TMP}/stdout2" 2>&1
assert_eq "0" "$?" "client install with SOCKS auth exited 0"
if command -v python3 >/dev/null 2>&1; then
  python3 - "${HOME2}/client_config.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    c = json.load(f)
assert c["socks_user"] == "tester"
assert c["socks_pass"] == 'p@ss"word'
PY
  assert_eq "0" "$?" "SOCKS credentials are stored correctly (quotes escaped)"
fi

printf '\n== uninstall\n'
XRV_LOG_FILE="${TMP}/uninstall.log" bash "${ROOT}/xrv-client.sh" \
  --uninstall --yes --home "$HOME_DIR" >"${TMP}/uninstall.out" 2>&1
assert_eq "0" "$?" "uninstall exited 0"
if [[ -e "$HOME_DIR" ]]; then
  t_not_ok "install folder still exists after uninstall"
else
  t_ok "install folder removed"
fi

finish
