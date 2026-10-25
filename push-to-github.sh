#!/usr/bin/env bash
# XRV v1.0 — GitHub Repository Setup & Push
# Run ONCE from the xrv-installer directory

set -Eeuo pipefail

REPO_OWNER="jackh0006"
REPO_NAME="XRV-Installer"
REPO_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"

echo "=== XRV v1.0 GitHub Push ==="
echo "This will:"
echo "  1. Initialize git repo"
echo "  2. Create initial commit"
echo "  3. Create GitHub repo (requires gh auth)"
echo "  4. Push to origin"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || { echo "Aborted"; exit 1; }

# 1. Git init
git init
git config user.name "jackh0006"
git config user.email "jackh109867@gmail.com"

# 2. Add all files
git add .

# 3. Initial commit
git commit -m "XRV v1.0 — GooseRelayVPN Optimized Installer

- Google Apps Script + VPS only (no multi-provider mesh)
- Speed: 4 deployments × 2 accounts, HTTP/2 HAProxy, coalesce_step_ms=100ms
- Stability: TLS fingerprint mimicry, ECH, blocking detection + auto-failover
- Security: entropy-checked keys, JSON schema validation, audit logging, TLS 1.3-only HAProxy
- Platforms: Linux amd64 (VPS + client) + Android arm64 (Termux)
- Doctor v2 (10-stage), smart idempotence, deployment-ID manager (any count)
- SHA256-pinned v1.7.1 binaries
- GitHub Actions: test, release, security-scan, docs"

# 4. Create GitHub repo (requires gh CLI authenticated)
if command -v gh >/dev/null 2>&1; then
  echo "Creating GitHub repository..."
  gh repo create "${REPO_OWNER}/${REPO_NAME}" --public --source=. --remote=origin --push
  echo "✅ Pushed to ${REPO_URL}"
else
  echo "⚠️  gh CLI not found. Manual steps:"
  echo "  1. Create repo at: https://github.com/new"
  echo "  2. Name: ${REPO_NAME}"
  echo "  3. Then run:"
  echo "     git remote add origin ${REPO_URL}"
  echo "     git push -u origin main"
fi
