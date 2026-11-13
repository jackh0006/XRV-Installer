#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Manual helper: stage, commit and optionally push the current XRV release.
# This script never pushes without asking.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

REPO_OWNER="jackh0006"
REPO_NAME="XRV-Installer"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
VERSION="${XRV_VERSION:-1.1.0}"

echo "=== XRV v${VERSION} release helper ==="
echo "Repository: ${REPO_URL}"
echo

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "This folder is not a Git repository."
  exit 1
fi

git status --short
echo
read -r -p "Stage all changes and commit? [y/N] " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

git add -A
git commit -m "XRV v${VERSION} — security, certificate and client overhaul

- standalone xrv-client.sh for Linux amd64/arm64 and Termux arm64
- pinned SHA-256 verification for client and server archives
- certificate issue/renew/replace/revoke with deploy hooks
- dedicated sandboxed xrv-haproxy service, TLS 1.3 only
- unprivileged xrv relay user and strict systemd hardening
- plain-language errors, redacted logs, firewall SSH-port detection
- tests: syntax, ShellCheck, unit, offline install, HAProxy config"

if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "$REPO_URL"
fi

echo
read -r -p "Push this commit and tag v${VERSION}? [y/N] " push
if [[ "$push" =~ ^[Yy]$ ]]; then
  git push origin HEAD
  git tag -a "v${VERSION}" -m "XRV v${VERSION}"
  git push origin "v${VERSION}"
  echo "Pushed. The release workflow will build the GitHub release."
else
  echo "Committed locally. Push when ready:"
  echo "  git push origin HEAD"
  echo "  git tag -a v${VERSION} -m 'XRV v${VERSION}' && git push origin v${VERSION}"
fi
