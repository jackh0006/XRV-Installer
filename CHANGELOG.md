# Changelog

All notable changes to XRV Installer are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions use [Semantic Versioning](https://semver.org/).

## [1.1.0] — 2026-11-13

This release is a full audit and rewrite. v1.0.0 could not be installed
reliably: interactive prompts returned the literal text `__line`, the client
menu never downloaded a client, the deployment manager contained invalid
Python, and the systemd sandbox hid the paths the relay needed.

### Added

- **Standalone `xrv-client.sh`** for Ubuntu/Linux amd64, Linux arm64 and
  Android Termux arm64. It is self-contained and can be run directly or from
  the repo with `bash <(curl ...)`.
- Client prompts for relay domain/IP, port, one or more deployment IDs,
  tunnel key, local SOCKS port, optional LAN sharing, optional local SOCKS
  auth, optional download proxy, and optional automatic start.
- Pinned SHA-256 checks for the upstream v1.7.1 client and server archives.
- Safe archive extraction (rejects absolute paths, `..`, and links).
- Certificate manager: show, renew, force-renew, replace domain, revoke and
  delete, and renewal dry-run.
- Automatic certificate renewal via `certbot.timer`, a deploy hook that
  rebuilds the HAProxy PEM, and optional pre/post hooks for services that
  occupy port 80.
- Dedicated `xrv-haproxy` systemd service with a separate config file, so it
  never touches or conflicts with a distro HAProxy configuration.
- Plain-language explanations for every prompt and every critical failure.
- JSON output for the server doctor (`--check --json`).
- Deployment-ID manager that works on the real config (add/list/remove/rename).
- Client systemd user service (optional) and Termux wake-lock handling.
- Unit tests, offline install tests, HAProxy config tests, and CI updates.

### Changed

- Server installs to FHS-friendly paths: `/opt/xrv` (binary) and `/etc/xrv`
  (config/key/state). v1.0 used `/root`.
- The relay runs as an unprivileged `xrv` user. HAProxy runs as `haproxy`.
  Both use strict systemd sandboxes.
- Server config now contains only fields the upstream binary understands.
  The fake `worker_pool_size` / `http2_enabled` / `max_batch_size_bytes` keys
  were removed.
- Client config uses only upstream fields, `coalesce_step_ms=25` (the
  upstream-recommended range is 20-40), and computed `idle_slots_per_bucket`.
- HAProxy is TLS 1.3 only, with modern ciphers, no tickets, `http-reuse`,
  long-poll-friendly timeouts, and path allow-listing (`/tunnel`, `/healthz`).
- `--update` now replaces only the binary and keeps the config and key.
- The client accepts a bare Deployment ID *or* a full `/exec` URL.
- Firewall handling detects the real SSH port before enabling UFW.

### Fixed

- `ask_line` wrote the literal string `__line` instead of the user's input.
- The client installer used `local` and `fetch` inside `bash -c`, so it could
  never install the binary.
- Menu option 1 called only the client flow; menu option 3 ran two conflicting
  flows back to back.
- Duplicate "Part 2/3/4 loaded" blocks and duplicate helper definitions.
- `server_existing_menu` fell through to a fresh install when the user chose
  "keep".
- The deployment manager's Python had `def save(): with ...` (SyntaxError).
- HAProxy config used removed `option http-use-htx`, deprecated `nbproc`, and
  TLS 1.2 while the docs claimed TLS 1.3.
- HAProxy was never given a frontend/backend on a fresh config.
- `/root` was hidden by `ProtectHome=true` while the binary lived there.
- Certificate issuance could race the distro HAProxy binding port 80.
- `curl -k` and other TLS-verification bypasses were removed.
- Audit logs are now created with private permissions and redact secrets.

### Security

- The tunnel key and deployment IDs are redacted from all log lines.
- Config and key are mode 600, owned by the service user.
- The public listener exposes only `/tunnel` and `/healthz`.
- No `eval`, no unquoted remote content, no TLS verification bypass.
- Downloads are HTTPS-only, retried, checksum-verified, and executed only
  after verification.

### Upgrade notes

v1.1.0 can migrate an existing v1.0 server:

1. It reads the old `/root/xrv-tunnel-key.txt` only if you explicitly install
   over it; the new key lives at `/etc/xrv/tunnel_key`.
2. It removes the old `# BEGIN XRV managed GooseRelayVPN` block from
   `/etc/haproxy/haproxy.cfg` and moves TLS to `xrv-haproxy`.
3. Clients must be pointed at the new relay URL if the public port changed.
4. If you rotate the key, update every client; old clients will not connect.

## [1.0.0] — 2026-10-25

Initial public release.

- Server menu with HAProxy, Certbot and systemd.
- Client menu for Linux amd64 and Android arm64.
- Deployment-ID manager, doctor, status and tests.
- Pinned upstream v1.7.1 release.

[1.1.0]: https://github.com/jackh0006/XRV-Installer/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jackh0006/XRV-Installer/releases/tag/v1.0.0
