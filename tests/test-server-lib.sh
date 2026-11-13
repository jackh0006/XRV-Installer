#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for pure functions and generated configuration in xrv-install.sh.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "${ROOT}/tests/lib.sh"

export XRV_LIB_ONLY=1
export XRV_LOG_FILE="/tmp/xrv-test-server-lib.log"
# shellcheck disable=SC1091
source "${ROOT}/xrv-install.sh"
set +e

printf '== server validators\n'
assert_true "accepts a normal domain" valid_domain vpn.example.com
assert_false "rejects an invalid domain" valid_domain not_a_domain
assert_true "accepts IPv4" valid_ipv4 203.0.113.10
assert_false "rejects IPv4 > 255" valid_ipv4 300.1.1.1
assert_true "accepts a valid email" valid_email admin@example.com
assert_false "rejects a bad email" valid_email admin@
assert_true "accepts a port" valid_port 8443
assert_false "rejects a bad port" valid_port 70000
assert_true "accepts a key" valid_tunnel_key "$(printf 'b%.0s' {1..64})"
assert_false "rejects a short key" valid_tunnel_key b
assert_true "accepts an https relay URL" valid_relay_url https://vpn.example.com:8443/tunnel
assert_true "accepts an http IP relay URL" valid_relay_url http://203.0.113.10:8443/tunnel
assert_false "rejects a relay URL without /tunnel" valid_relay_url https://vpn.example.com:8443/
assert_true "accepts a SOCKS5 proxy" valid_socks_proxy socks5://127.0.0.1:40000
assert_false "rejects an HTTP upstream proxy" valid_socks_proxy http://127.0.0.1:40000

printf '\n== server config generation\n'
KEY="$(printf 'c%.0s' {1..64})"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
render_server_config 127.0.0.1 9443 "$KEY" "" false >"${TMP}/server.json"
assert_file "server config written" "${TMP}/server.json"
if command_exists python3; then
  python3 -m json.tool "${TMP}/server.json" >/dev/null 2>&1
  assert_eq "0" "$?" "server config is valid JSON"
  python3 - "${TMP}/server.json" "$KEY" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    c = json.load(f)
assert c["server_host"] == "127.0.0.1"
assert c["server_port"] == 9443
assert c["tunnel_key"] == sys.argv[2]
assert c["upstream_proxy"] == ""
assert c["debug_timing"] is False
assert set(c) == {"server_host", "server_port", "tunnel_key", "upstream_proxy", "debug_timing"}
PY
  assert_eq "0" "$?" "server config contains only upstream-supported fields"
fi

render_server_config 127.0.0.1 9443 "$KEY" "socks5://127.0.0.1:40000" true >"${TMP}/proxy.json"
assert_true "server config accepts an upstream proxy" grep -q '"upstream_proxy": "socks5://127.0.0.1:40000"' "${TMP}/proxy.json"
assert_true "server config accepts debug_timing" grep -q '"debug_timing": true' "${TMP}/proxy.json"

printf '\n== Apps Script file\n'
write_code_gs "https://vpn.example.com:8443/tunnel" "${TMP}/Code.gs" >/dev/null 2>&1
assert_file "Code.gs written" "${TMP}/Code.gs"
assert_true "relay URL was injected" grep -q "https://vpn.example.com:8443/tunnel" "${TMP}/Code.gs"
assert_true "no placeholder remains" bash -c "! grep -q RELAY_URL_PLACEHOLDER '${TMP}/Code.gs'"

printf '\n== HAProxy config\n'
HAPROXY_BIN="${HAPROXY_BIN:-$(command -v haproxy || true)}"
if [[ -n "$HAPROXY_BIN" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=vpn.example.com' \
    -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" >/dev/null 2>&1
  cat "${TMP}/cert.pem" "${TMP}/key.pem" >"${TMP}/bundle.pem"
  chmod 600 "${TMP}/bundle.pem"
  haproxy_config vpn.example.com 8443 9443 "${TMP}/bundle.pem" >"${TMP}/haproxy.cfg"
  "$HAPROXY_BIN" -c -q -f "${TMP}/haproxy.cfg"
  assert_eq "0" "$?" "generated HAProxy config is valid"
  assert_true "TLS 1.3 is enforced" grep -q 'ssl-min-ver TLSv1.3' "${TMP}/haproxy.cfg"
  assert_true "only /tunnel and /healthz are allowed" grep -q 'deny_status 404 unless xrv_tunnel or xrv_health' "${TMP}/haproxy.cfg"
  assert_false "removed http-use-htx is absent" grep -q 'http-use-htx' "${TMP}/haproxy.cfg"
  assert_false "deprecated nbproc is absent" grep -q 'nbproc' "${TMP}/haproxy.cfg"
else
  printf '  skip HAProxy checks (haproxy not installed)\n'
fi

printf '\n== archive extraction safety\n'
mkdir -p "${TMP}/src" "${TMP}/out"
printf 'hello\n' >"${TMP}/src/ok.txt"
tar -czf "${TMP}/safe.tar.gz" -C "${TMP}/src" ok.txt
safe_extract_tar "${TMP}/safe.tar.gz" "${TMP}/out" >/dev/null 2>&1
assert_file "safe archive extracted" "${TMP}/out/ok.txt"

mkdir -p "${TMP}/bad"
ln -sf /etc/passwd "${TMP}/bad/link"
tar -czf "${TMP}/bad.tar.gz" -C "${TMP}/bad" link
(safe_extract_tar "${TMP}/bad.tar.gz" "${TMP}/bad-out" >/dev/null 2>&1)
assert_eq "1" "$?" "archive with a symlink is refused"


printf '\n== Tolerating an existing HAProxy config\n'
cat >"${TMP}/user-haproxy.cfg" <<'CFG'
global
    maxconn 4096

defaults
    mode http
    timeout connect 5s
    timeout client 30s
    timeout server 30s

frontend user_site
    bind *:18080
    default_backend user_back

backend user_back
    server local 127.0.0.1:18081

# BEGIN XRV managed GooseRelayVPN

frontend xrv_tls_in
    bind *:18443 ssl crt /etc/haproxy/certs/old.example.com.pem
    default_backend xrv_back

backend xrv_back
    server xrv1 127.0.0.1:19443

# END XRV managed GooseRelayVPN
CFG
chmod 644 "${TMP}/user-haproxy.cfg"
strip_old_xrv_block "${TMP}/user-haproxy.cfg" >"${TMP}/stripped.cfg"
assert_false "old XRV block is removed" grep -q "XRV managed GooseRelayVPN" "${TMP}/stripped.cfg"
assert_true "user frontend is preserved" grep -q "frontend user_site" "${TMP}/stripped.cfg"
assert_true "user backend is preserved" grep -q "backend user_back" "${TMP}/stripped.cfg"
assert_true "unrelated bind is preserved" grep -q "bind \*:18080" "${TMP}/stripped.cfg"
assert_true "global section is preserved" grep -q "^global" "${TMP}/stripped.cfg"

cp "${TMP}/user-haproxy.cfg" "${TMP}/migrate.cfg"
remove_old_xrv_haproxy_block "${TMP}/migrate.cfg" >/dev/null 2>&1
assert_false "migration removes only the marked block" grep -q "XRV managed GooseRelayVPN" "${TMP}/migrate.cfg"
assert_true "migration keeps the user's frontend" grep -q "frontend user_site" "${TMP}/migrate.cfg"
assert_true "migration keeps the user's backend" grep -q "backend user_back" "${TMP}/migrate.cfg"
assert_mode "migration keeps the file mode" "${TMP}/migrate.cfg" "644"

printf '\n== Pinned release metadata\n'

assert_eq "amd64" "$(detect_arch)" "detect_arch returns amd64 here"
assert_true "server URL is the pinned release" grep -q 'v1.7.1' <<<"$(server_url_for_arch)"
assert_eq "64" "${#SERVER_SHA256_AMD64}" "amd64 server SHA-256 is pinned"
assert_eq "$(sha256_of "${ROOT}/xrv-client.sh")" "$CLIENT_SCRIPT_SHA256" \
  "server pins the exact client script shipped in this repo"

finish
