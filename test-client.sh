#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Convenience wrapper: run the full client doctor on this device.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT}/xrv-client.sh" --check "$@"
