# Changelog

All notable changes to XRV Installer are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions use [Semantic Versioning](https://semver.org/).

## [2.0.0-fronting-fix] — 2026-11-18

### Fixed

- The Android bridge passed a bare Google edge to the carrier fronting config;
  the carrier needs `host:port`. Every request failed with `missing port in
  address`, so there was no traffic despite a listening SOCKS port. Normalize
  the edge to `host:443` and auto-select a reachable edge on first connect.

## [2.0.0-settings] — 2026-11-18

### Added

- Per-app proxy for TUN mode (only selected / all except selected) with an
  installed-app picker and Android allow/deny lists.
- Google edge testing matching `xrv-client.sh`: real HTTPS `generate_204`
  probes of the four standard edges, latency display, fastest-edge selection,
  custom IPv4 candidates and automatic reset.
- Real SOCKS payload traffic counters in both modes, replacing the hev raw
  packet counters, plus session count from the engine.
- Live tunnel test via `api.ipify.org` through the authenticated SOCKS proxy,
  with exit-IP versus direct-IP comparison.
- In-app log viewer with persisted app events, native carrier logs, crash
  capture and secret redaction.
- Performance settings for uplink coalescing (default 25 ms) and 1–3 idle
  polls, scaling with deployment count.
- Copied proxy links are named `#XRV` so v2rayNG imports them as XRV, not
  `none`.

## [2.0.0] — 2026-11-17

### Added

- A complete Android TUN mode (`VpnService`) backed by a source-built,
  submodule-pinned hev-socks5-tunnel, with mapped DNS, IPv4/IPv6 routes,
  self-exclusion from the tunnel, and a watchdog.
- A Material 3 interface with a live status card, traffic/time counters,
  mode selector, inline validation, copyable proxy address and an About screen.
- A designed XRV shield logo: adaptive, monochrome, round, legacy PNG and
  notification variants.
- Detection and clear guidance when another VPN is already active.
- Automatic free-port selection and a real disconnect path that closes the
  listener.
- `scripts/verify-apk.sh`, which rejects absolute `DT_NEEDED` paths, checks
  16 KB page alignment, ABIs and the APK signature.

### Fixed

- The Connect crash caused by the JNI shim's absolute build-path dependency.
- The app icon that was missing from the manifest.
- Foreground-service lifecycle, Android 14/15/16 service types, notification
  permission handling, stale state after process death, and mode-switch races.
- Security hardening: no cleartext, no user CAs, no backups of credentials,
  no Go log output on Android, minified release with JNI keep rules.

### Changed

- Android version is now 2.0.0 (`versionCode` 20000), target SDK 36.
- CI builds and verifies a release APK instead of a debug APK.
- The previous 1.2.x APK cannot be updated in place because it was signed with
  an unrecoverable CI debug key; uninstall it first.

## [1.2.4] — 2026-11-15

- Port-80 collision handling maps listener processes to their running systemd
  units, so `hedioum-tunnel` is safely recognized as `hedioum.service`.
- Certificate issuance asks before pausing that exact service, restores it
  after the ACME attempt, and records renewal hooks only after a successful
  certificate request.

## [1.2.3] — 2026-11-15

- VPS completion screen includes the full Google setup and verification guide,
  saved as GOOGLE-SETUP.txt and available again through --google-guide.
- Generated forwarders explicitly verify TLS, omit upstream error bodies,
  remove the undocumented deadline option, and avoid storage calls when
  invocation counting is disabled.
- Added executable tests for both Google templates and documented Google's
  quotas, metadata visibility, deployment requirements and verification limits.

## [1.2.2] — 2026-11-15

### Fixed

- The client no longer silently assumes TCP 8443 when only a relay hostname is
  supplied. It checks XRV's familiar public HTTPS ports, reports a healthy
  endpoint when found, and always asks the user to confirm or replace the port.
- A failed relay health check now offers to correct and re-check the port before
  any client configuration is written.

## [1.2.1] — 2026-11-15

### Added

- `--acme-stop-service UNIT.service` for an explicit, verified service that
  may be paused only while Let's Encrypt needs TCP port 80. The installer
  records matching renewal hooks and restores only services that were running.

### Fixed

- Existing certificates valid for at least 30 days are now reused without
  asking Certbot's standalone listener to bind port 80. This prevents an
  unnecessary interruption to unrelated tunnels, web services, or HAProxy.
- Public-port conflicts are detected before package, firewall, configuration,
  or service changes are made.

## [1.2.0] — 2026-11-15

### Added

- Smart server port selection: it inspects TCP and UDP listeners, names a
  conflicting TCP process, and suggests free familiar HTTPS-style ports.
- `--backend-port PORT` and an interactive private-backend prompt. The backend
  remains bound only to `127.0.0.1` and is never opened by firewall automation.

### Fixed

- The companion client script URL now defaults to the repository's `main`
  branch, matching the documented default branch.
- Port collisions are detected before a service restart, avoiding opaque
  systemd failures.

## [1.1.1] — 2026-11-13

GitHub repository standards, donation information, and documentation deploy.

### Added

- `DONATE.md` with every public crypto address copied from the author's
  BNB-Terminal-Wallet and X-Wallet repositories.
- `.github/FUNDING.yml` pointing at `DONATE.md`.
- `.github/CODEOWNERS`, issue forms, and support guidance.
- `CITATION.cff` metadata for GitHub's **Cite this repository** button.
- README badges for CI, release, license, platforms, security policy, and PRs.
- Standard `SUPPORT.md` with the exact information needed for a useful report.
- `RELEASE_NOTES_v1.1.1.md`.

### Changed

- Merged the v1.1.0 work onto the repository's `main` branch and kept the
  standard community files from `main`.
- Pinned every GitHub Action to a commit SHA.
- CI now runs syntax, ShellCheck, the full test suite, and both help screens.
- Release workflow attaches both installers, checksums, docs, and release notes.
- GitHub Pages is enabled for this repository; the docs workflow deploys with
  the official Pages actions instead of the failing legacy path.
- Version bumped to 1.1.1 in both scripts and the doctor JSON.

### Fixed

- `Build Documentation` failed with `Creating Pages deployment failed / 404`
  because GitHub Pages was not enabled. Pages is now enabled with the workflow
  build type, and the workflow uses pinned Pages actions.
- The remote repository had two branches (`main` and `master`) with different
  content. `main` is now the single default branch.

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

[1.1.1]: https://github.com/jackh0006/XRV-Installer/compare/v1.1.0...v1.1.1
[1.2.4]: https://github.com/jackh0006/XRV-Installer/compare/v1.2.3...v1.2.4
[1.2.2]: https://github.com/jackh0006/XRV-Installer/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/jackh0006/XRV-Installer/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/jackh0006/XRV-Installer/compare/v1.1.1...v1.2.0
[1.1.0]: https://github.com/jackh0006/XRV-Installer/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jackh0006/XRV-Installer/releases/tag/v1.0.0
