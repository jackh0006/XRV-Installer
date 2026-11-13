#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Unit tests for pure functions in xrv-client.sh.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "${ROOT}/tests/lib.sh"

export XRV_LIB_ONLY=1
export XRV_LOG_FILE="/tmp/xrv-test-client-lib.log"
# shellcheck disable=SC1091
source "${ROOT}/xrv-client.sh"
set +e

printf '== client validators\n'
assert_true "accepts a normal domain" valid_domain vpn.example.com
assert_false "rejects an underscore domain" valid_domain bad_domain
assert_false "rejects a single label" valid_domain localhost
assert_true "accepts IPv4" valid_ipv4 203.0.113.10
assert_false "rejects IPv4 > 255" valid_ipv4 300.1.1.1
assert_false "rejects a short IPv4" valid_ipv4 1.2.3
assert_true "accepts a 64-hex key" valid_tunnel_key "$(printf 'a%.0s' {1..64})"
assert_false "rejects a short key" valid_tunnel_key abc
assert_true "accepts a real-looking deployment" valid_deployment_id "AKfycb$(printf 'A%.0s' {1..60})"
assert_false "rejects an editor script id" valid_deployment_id "1AbCdEfGhIjKlMnOp"
assert_true "accepts a port" valid_port 8443
assert_false "rejects port 0" valid_port 0
assert_false "rejects port 70000" valid_port 70000

printf '\n== deployment ID normalisation\n'
assert_eq "AKfycbTEST_123" \
  "$(normalize_deployment_id 'https://script.google.com/macros/s/AKfycbTEST_123/exec')" \
  "extracts ID from a full /exec URL"
assert_eq "AKfycbABC_def-123" \
  "$(normalize_deployment_id 'AKfycbABC_def-123')" \
  "keeps a bare ID unchanged"
assert_eq "AKfycbX" \
  "$(normalize_deployment_id ' AKfycbX/ ')" \
  "trims spaces and trailing slash"

printf '\n== JSON escaping\n'
assert_eq 'a b\"c\\d\n' \
  "$(json_escape 'a b"c\d
')" \
  "escapes quotes, backslashes and newlines"

printf '\n== deployment pool\n'
DEPLOYMENTS=()
add_deployment "AKfycb$(printf 'A%.0s' {1..60})" >/dev/null 2>&1
add_deployment "AKfycb$(printf 'B%.0s' {1..60})" >/dev/null 2>&1
compute_idle_slots
assert_eq "2" "$IDLE_SLOTS" "two deployments on one account -> 2 idle slots"
assert_eq "2" "${#DEPLOYMENTS[@]}" "two deployments recorded"

DEPLOYMENTS=()
add_deployment "AKfycb$(printf 'C%.0s' {1..60})" acct-a >/dev/null 2>&1
add_deployment "AKfycb$(printf 'D%.0s' {1..60})" acct-b >/dev/null 2>&1
add_deployment "AKfycb$(printf 'E%.0s' {1..60})" acct-b >/dev/null 2>&1
add_deployment "AKfycb$(printf 'F%.0s' {1..60})" acct-b >/dev/null 2>&1
compute_idle_slots
assert_eq "3" "$IDLE_SLOTS" "an account with three deployments -> 3 idle slots"

# Duplicate IDs must be rejected.
DEPLOYMENTS=()
add_deployment "AKfycb$(printf 'G%.0s' {1..60})" acct-a >/dev/null 2>&1
add_deployment "AKfycb$(printf 'G%.0s' {1..60})" acct-a >/dev/null 2>&1
assert_eq "1" "${#DEPLOYMENTS[@]}" "duplicate deployment is ignored"

finish
