# XRV v1.0 — GooseRelayVPN Optimized Installer

**Maximum speed, stability, security for Google Apps Script + VPS**  
Linux amd64 (VPS + client) + Android arm64 (Termux client only)

## Quick Start

```bash
# On VPS (root):
bash xrv-install.sh  # Choose option 2 → follow prompts

# On client (no root):
bash xrv-install.sh  # Choose option 3 → follow prompts
./start-xrv.sh       # Wait for "pre-flight OK" then "ready"
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org  # Should show VPS IP
```

## Features

| Category | Details |
|----------|---------|
| **Speed** | 4 deployment IDs across 2 Google accounts, HTTP/2 in HAProxy, `coalesce_step_ms=100ms` |
| **Stability** | TLS fingerprint mimicry (utls-ready), ECH support, blocking detection + auto-failover across deployments |
| **Security** | Entropy-checked keys, JSON schema validation, audit logging (JSONL), TLS 1.3-only HAProxy |
| **Platforms** | VPS: Ubuntu amd64 (root) · Client: Linux amd64 + Android arm64 (Termux, no root) |
| **Ops** | Doctor v2 (10-stage exact cause/fix), smart idempotence, deployment-ID manager (any count) |

## Menu Options

1. **Full installation** — VPS + Apps Script + both clients
2. **Server installation** — VPS only (Linux amd64)
3. **Client installation** — Linux amd64 + Android arm64 (Termux)
4. **Deployment-ID manager** — Add/remove/list/rename deployment IDs
5. **Test** — Server test / Client test
6. **Doctor v2** — 10-stage diagnosis (exact cause, exact fix)
7. **Status & health** — Service status, certs, backend health

## Requirements

- **VPS**: Ubuntu 22.04/24.04 amd64, root, domain (for TLS), ports 80/443/8443 open
- **Client**: Linux amd64 (any distro) or Android Termux (arm64)
- **Google**: 1-2 Google accounts, Apps Script projects with Web App deployments (AKfycb... IDs)

## Architecture

```
Browser → SOCKS5 127.0.0.1:1080 → Google HTTPS → Apps Script (4 deployments × 2 accounts)
                                                              ↓
                                                   VPS: HAProxy (TLS 1.3, HTTP/2) → xrv-relay (GooseRelayVPN)
```

## Security Model

- **Tunnel key**: 256-bit AES, generated with entropy check, 600 perms, never logged
- **Deployment IDs**: Masked in logs (`AKfycb...cdef12`)
- **Audit log**: JSONL at `/var/log/xrv/audit.log` (VPS) / `~/.xrv/logs/audit.log` (client)
- **TLS**: HAProxy terminates with TLS 1.3, modern ciphers, no tickets

## Documentation

- `bash xrv-install.sh --help` — Full usage
- `bash xrv-install.sh --dry-run` — Syntax verification only
- `GUIDE.txt` — Generated in each client folder
- `doctor_flow --json` — Machine-readable health verdict

## License

MIT — jackh0006 <jackh109867@gmail.com>  
Upstream: https://github.com/Kianmhz/GooseRelayVPN
