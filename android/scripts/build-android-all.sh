#!/usr/bin/env bash
# Builds the native engine for one or more ABIs (comma-separated).
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
list="${1:-arm64-v8a}"
IFS=',' read -r -a abis <<< "$list"
for abi in "${abis[@]}"; do
    abi="$(echo "$abi" | xargs)"
    [[ -n "$abi" ]] || continue
    echo "=== building native engine for $abi ==="
    bash "$root/scripts/build-android-engine.sh" "$abi"
done
