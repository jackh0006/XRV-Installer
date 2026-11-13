# XRV v1.1.0 — release notes

**Audit, harden, and finish the client.**

v1.0.0 shipped an installer that looked complete but could not work in several
core paths. v1.1.0 fixes the whole chain and adds the standalone client
installer.

## Downloads

| File | Platform |
|------|----------|
| `xrv-install.sh` | Server manager: Ubuntu/Debian amd64 or arm64 VPS |
| `xrv-client.sh` | Client: Linux amd64/arm64 and Android Termux arm64 |
| `SHA256SUMS.txt` | Checksums for every attached file |

Always verify before running:

```bash
sha256sum -c SHA256SUMS.txt
```

## Highlights

- **Client installer is real.** `xrv-client.sh` downloads, verifies, installs,
  configures, starts, checks, updates and uninstalls the client.
- **Certificate lifecycle.** Issue, renew, force-renew, replace a domain,
  revoke and delete, dry-run, deploy hook, renewal timer, port-80 conflict
  handling.
- **TLS front isolation.** A dedicated `xrv-haproxy` service with its own
  config. TLS 1.3 only. The distro HAProxy config is never overwritten.
- **Relay isolation.** Runs as `xrv`, not root, with a strict systemd sandbox.
  Config and key are mode 600.
- **Supply chain.** Pinned upstream v1.7.1 archives, SHA-256 verified, safe
  extraction that rejects traversal and links.
- **Plain-language errors.** Every critical failure names the cause and the
  next command. The tunnel key and deployment IDs are redacted from logs.
- **Firewall safety.** Detects the real SSH port before enabling UFW, and opens
  only SSH, 80 for ACME (TLS mode), and the tunnel port.
- **Tests and CI.** Syntax, ShellCheck, unit tests, offline client install,
  HAProxy config validation, release checksum verification.

## Fixed in v1.0.0

- Prompts returned the literal text `__line`.
- The client flow never downloaded a client binary.
- The deployment manager had a Python syntax error.
- HAProxy used removed `option http-use-htx`, deprecated `nbproc`, and TLS 1.2
  while claiming TLS 1.3.
- A fresh HAProxy config had no frontend/backend.
- `ProtectHome=true` hid `/root`, where the binary and config lived.
- Choosing "keep" in the existing-install menu fell through to a fresh install.
- Certbot could race the distro HAProxy for port 80.
- Deployment IDs were not masked consistently.

## Upgrade from v1.0.0

1. Keep a copy of `/root/xrv-tunnel-key.txt`.
2. Run `sudo bash xrv-install.sh` and choose the server install.
3. Enter the same domain. The installer reuses the existing certificate when
   it is still valid and migrates the old key if the new key file is missing.
4. Update every client to the new relay URL and key if they changed.
5. Verify with `sudo bash xrv-install.sh --check`.

If you want a clean start, choose **Full reinstall** and generate a new key.
Every client must then be updated.

## Known limits

- Google sees connection metadata and applies Apps Script quotas per account.
- The VPS provider sees exit traffic.
- A stolen tunnel key or a compromised VPS defeats the tunnel.
- TLS 1.3 is required on the public port. Very old clients that cannot speak
  TLS 1.3 are not supported.
- This is not an anonymity network.

## Verification performed

- `bash -n` on every script.
- ShellCheck warning-level clean.
- Unit tests for validators, deployment normalisation, JSON escaping and the
  deployment pool.
- Offline client install with a temporary HOME, checking file modes, config
  schema, secret redaction and uninstall.
- Generated server config checked with Python JSON validation.
- Generated HAProxy config checked with HAProxy 2.4 and 2.8 (`haproxy -c`).
- Full server install exercised in an isolated Linux sandbox, both HTTP-only
  and TLS-front modes: user creation, pinned download, key/config, service
  start, local health, HAProxy TLS 1.3 handshake, `/healthz` 200 and 404 for
  other paths.
- Server update and key rotation exercised against that installation; the key
  is preserved on update and replaced on rotation.
- Pinned client/server digests checked against the upstream GitHub API.
- Live client binary started against a generated config (pre-flight path).

## Thanks

Upstream project: <https://github.com/Kianmhz/GooseRelayVPN> (MIT).
