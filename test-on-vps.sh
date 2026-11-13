#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Convenience wrapper: run the full server doctor on this VPS.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "The server doctor needs root for the complete check."
  exec sudo bash "${ROOT}/xrv-install.sh" --check "$@"
fi

exec bash "${ROOT}/xrv-install.sh" --check "$@"
