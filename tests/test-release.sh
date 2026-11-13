#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Verify that the pinned release digests still match the upstream release.
# Skips cleanly when the network is unavailable.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib.sh
source "${ROOT}/tests/lib.sh"

API="https://api.github.com/repos/Kianmhz/GooseRelayVPN/releases/tags/v1.7.1"

printf '== pinned upstream release\n'
json="$(curl -fsS --noproxy '*' --max-time 25 "$API" 2>/dev/null || true)"
if [[ -z "$json" ]]; then
  printf '  skip upstream API is not reachable from this environment\n'
  finish
  exit $?
fi

export XRV_LIB_ONLY=1
export XRV_LOG_FILE=/tmp/xrv-test-release.log
# shellcheck disable=SC1091
source "${ROOT}/xrv-client.sh" >/dev/null 2>&1 || true
# shellcheck disable=SC1091
source "${ROOT}/xrv-install.sh" >/dev/null 2>&1 || true
set +e

check_asset() {
  local name="$1" expected="$2" got
  got="$(
    python3 - "$json" "$name" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
for a in data["assets"]:
    if a["name"] == sys.argv[2]:
        print((a.get("digest") or "").removeprefix("sha256:"))
        break
PY
  )"
  assert_eq "$expected" "$got" "$name digest matches the pin"
}

check_asset "GooseRelayVPN-client-v1.7.1-linux-amd64.tar.gz" "$CLIENT_SHA_LINUX_AMD64"
check_asset "GooseRelayVPN-client-v1.7.1-android-arm64.tar.gz" "$CLIENT_SHA_ANDROID_ARM64"
check_asset "GooseRelayVPN-client-v1.7.1-linux-arm64.tar.gz" "$CLIENT_SHA_LINUX_ARM64"
check_asset "GooseRelayVPN-server-v1.7.1-linux-amd64.tar.gz" "$SERVER_SHA256_AMD64"

finish
