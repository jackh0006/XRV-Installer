# XRV — hardened GooseRelayVPN installer

**A private SOCKS5 tunnel that travels inside ordinary Google HTTPS.**
One small VPS is the exit. Your devices run a client. Google only sees encrypted
traffic to a Google address, and the tunnel key never leaves your machines.

This repository is the **installer** for the upstream
[GooseRelayVPN](https://github.com/Kianmhz/GooseRelayVPN) v1.7.1 release.
It installs, verifies, explains, and manages the pieces for you.

```
Browser / app
  -> SOCKS5 127.0.0.1:1080
  -> encrypted frames
  -> HTTPS to a Google edge (SNI www.google.com)
  -> Google Apps Script (dumb forwarder)
  -> your VPS :8443/tunnel (TLS 1.3, HAProxy)
  -> the real internet
```

- **End-to-end encryption:** AES-256-GCM. Google never holds the key.
- **Server:** Ubuntu/Debian Linux amd64 or arm64, root.
- **Client:** Ubuntu/Linux amd64 (also arm64) and Android Termux arm64.
- **License:** MIT. No tracking, no telemetry, no closed pieces.

---

## What changed in v1.1.0

v1.0 was unsafe to run unattended: prompts read the literal text `__line`,
the client installer never installed a client, the deployment manager had a
Python syntax error, the systemd sandbox hid `/root`, and HAProxy was started
with options that recent versions reject. v1.1.0 is a full audit fix.

Highlights:

| Area | v1.1.0 |
|------|--------|
| Prompts | Every prompt now returns what you typed. Validation loops explain typos. |
| Client | New standalone `xrv-client.sh` for Linux amd64, Linux arm64 and Termux arm64. |
| Checksums | Release archives are pinned by SHA-256 and checked before anything runs. |
| Certificates | Issue, renew, force-renew, replace, revoke/delete, renewal hooks, dry-run. |
| HAProxy | Dedicated `xrv-haproxy` service, TLS 1.3 only, valid modern options, no port 80 conflict. |
| Systemd | Unprivileged `xrv` user, strict sandbox, config/key readable only by that user. |
| Firewall | Detects your SSH port first; opens only SSH, 80 (ACME) and the tunnel port. |
| Errors | Plain-language cause + exact next command. No secret is logged. |
| Tests | Syntax, ShellCheck, unit tests, offline install test, HAProxy config test. |

See [CHANGELOG.md](CHANGELOG.md) for the full list.

---

## Requirements

### VPS
- Ubuntu 22.04/24.04 or Debian 12, **amd64** or **arm64**, root access.
- A domain whose **A record** points to the VPS IPv4 (recommended).
- TCP ports **80** (certificate renewal) and **8443** (tunnel) open in UFW
  **and** in your cloud provider's firewall.
- About 200 MB of free disk space.

### Client
- Linux: `x86_64` or `aarch64`, `curl`, `tar`, `sha256sum` (or `openssl`).
- Android: Termux from F-Droid, arm64. The installer can add `curl`/`tar` for you.
- No root is needed on the client.

### Google
- One or two Google accounts.
- Apps Script Web App deployments. Each deployment ID starts with `AKfycb`.

---

## Server install (VPS)

```bash
sudo bash xrv-install.sh
# choose: 1) Install or update the server
```

The installer will:

1. Install packages (HAProxy, Certbot, curl, tar, openssl, UFW and friends).
2. Detect your SSH port and open only what is needed.
3. Ask for your domain and email.
4. Request a trusted **ECDSA** Let's Encrypt certificate.
5. Write a dedicated HAProxy TLS 1.3 configuration.
6. Create the unprivileged `xrv` user and its systemd service.
7. Verify the local relay and the public TLS endpoint.
8. Write `/etc/xrv/Code.gs` with your relay URL.

Non-interactive form:

```bash
sudo bash xrv-install.sh --server --non-interactive --yes \
  --domain vpn.example.com --email you@example.com
```

Useful flags:

```
--public-port 8443      change the public TLS port
--upstream-proxy socks5://127.0.0.1:40000
                        route VPS outbound traffic through a local SOCKS5
                        (for example Cloudflare WARP)
--http                  HTTP-only mode (not recommended; no certificate)
--tls                   force TLS mode if a saved state says HTTP
--staging               Let's Encrypt staging service (testing only)
```

After installation, read the key on the VPS:

```bash
sudo cat /etc/xrv/tunnel_key
```

Copy the **relay URL** and the **tunnel key** into the client installer.

### What gets installed where

| Thing | Path |
|-------|------|
| Relay binary | `/opt/xrv/bin/xrv-server` |
| Server config (contains key, mode 600) | `/etc/xrv/server_config.json` |
| Tunnel key (mode 600, owner `xrv`) | `/etc/xrv/tunnel_key` |
| HAProxy config | `/etc/haproxy/xrv.cfg` |
| Certificate bundle | `/etc/haproxy/certs/<domain>.pem` |
| Apps Script file | `/etc/xrv/Code.gs` |
| Installer log (no secrets) | `/var/log/xrv/install.log` |
| Relay service | `xrv-relay.service` |
| TLS front service | `xrv-haproxy.service` |

---

## Client install

### Ubuntu / Linux amd64 (or arm64)

```bash
bash xrv-client.sh
```

It asks for:

1. **Relay domain or IP** — example `vpn.example.com`.
2. **Relay port** — default `8443`.
3. **Deployment IDs** — paste one or more `AKfycb...` values (or full `/exec` links).
4. **Tunnel key** — hidden input, 64 hex characters.
5. **Local SOCKS port** — default `1080`.
6. Optional: LAN sharing, local SOCKS password, download proxy, automatic start.

It then downloads the official client, verifies its SHA-256, writes a mode-600
config, and gives you:

```bash
~/xrv/start-xrv.sh
~/xrv/stop-xrv.sh
~/xrv/status-xrv.sh
```

### Android / Termux arm64

Install Termux from **F-Droid** (not the Play Store), then:

```bash
pkg update && pkg install -y curl tar
bash xrv-client.sh
```

The script detects Termux and downloads the `android-arm64` binary. It also
creates a wake-lock while the client is running.

In NekoBox or v2rayNG:

- Add a SOCKS5 server: `127.0.0.1:1080`.
- **Exclude Termux** from the proxy, otherwise Termux loses the connection it
  needs to keep the tunnel alive.

### Verify

```bash
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

The answer must be your **VPS IP**, not your real IP. If it is your real IP,
the tunnel is not carrying traffic; run:

```bash
bash xrv-client.sh --check
```

### Non-interactive client install

```bash
bash xrv-client.sh --non-interactive --yes \
  --relay vpn.example.com --relay-port 8443 --relay-scheme https \
  --deployment AKfycb...:acct-a \
  --tunnel-key "$(sudo cat /etc/xrv/tunnel_key)" \
  --socks-port 1080
```

Add `--no-start` in automation, then start with `~/xrv/start-xrv.sh`.

---

## Apps Script (the Google side)

The client writes `~/xrv/Code.gs` (the server writes `/etc/xrv/Code.gs`).
The relay URL is already inside it.

1. Open <https://script.google.com> -> **New project**.
2. Delete the sample code and paste the whole `Code.gs`.
3. **Deploy -> New deployment -> Web app**.
   - Execute as: **Me**
   - Who has access: **Anyone**
4. Copy the **Deployment ID** (`AKfycb...`).
5. Add it to the client:

   ```bash
   bash xrv-client.sh --deployment AKfycb...
   ```

Every time you edit `Code.gs`, create a **new deployment** and add the new ID.
Saving alone does not publish changes.

More deployments (especially under different Google accounts) give more daily
quota and more failover. Label each one with the account it belongs to.

---

## Certificates

```bash
sudo bash xrv-install.sh --cert
```

| Choice | What it does |
|--------|--------------|
| Show | Displays subject, issuer, dates and days remaining. |
| Renew | `certbot renew` for this certificate. |
| Force new | Requests a fresh certificate now. |
| Replace domain | Deletes the old certificate files, issues for the new name, rebuilds HAProxy. |
| Revoke & delete | Revokes (emergency/key compromise) then deletes. |
| Dry run | `certbot renew --dry-run` to test automatic renewal. |

The installer also:

- Installs a deploy hook that rebuilds the HAProxy PEM and reloads the TLS front.
- Enables `certbot.timer` (or an XRV timer if the package has none).
- If port 80 belongs to nginx/apache/haproxy, asks before stopping it for the
  ~20 second HTTP-01 check and records pre/post hooks for future renewals.

Certificates are ECDSA P-256, valid for 90 days, renewed automatically around
30 days before expiry.

---

## Security model

- **Tunnel key:** 256-bit, generated with `openssl rand -hex 32`, validated,
  stored mode 600, owned by `xrv`. It is never printed by the installer and
  never written to logs.
- **Transport:** TLS 1.3 only on the public VPS port, modern TLS 1.3 ciphers,
  no session tickets. The payload is *also* AES-256-GCM end to end.
- **Privileges:** the relay runs as `xrv`, not root. HAProxy runs as `haproxy`.
  Neither service can write to the system.
- **Supply chain:** the upstream release is pinned to v1.7.1 and checked against
  the SHA-256 published in the GitHub release digest.
- **Firewall:** only SSH, 80 and the tunnel port are opened. The SSH port is
  detected from `sshd`/`SSH_CONNECTION` before UFW is enabled.
- **Logs:** JSONL/plain logs redact `AKfycb...` deployment IDs and any 64-hex
  key that ever appears in a message.
- **No telemetry:** nothing is sent anywhere except the downloads you ask for.

**Not protected:** Google can see that your client talks to Google and how much
data it carries. Your VPS provider can see the exit traffic. A compromised VPS
or a stolen tunnel key defeats the tunnel. This is a censorship-resistance and
privacy tool, not an anonymity network.

Read [SECURITY.md](SECURITY.md) before exposing anything to the public internet.

---

## Operations

```bash
sudo bash xrv-install.sh --check       # full server doctor
sudo bash xrv-install.sh --version
sudo bash xrv-install.sh --update      # binary only, keeps config/key
sudo bash xrv-install.sh --rotate-key  # new key; update every client
sudo bash xrv-install.sh --uninstall
```

Client:

```bash
bash xrv-client.sh --check
bash xrv-client.sh --update
bash xrv-client.sh --uninstall
```

Logs:

```bash
journalctl -u xrv-relay -n 50 --no-pager
journalctl -u xrv-haproxy -n 50 --no-pager
tail -n 50 /var/log/xrv/install.log
tail -n 50 ~/xrv/xrv-client.log
```

---

## Troubleshooting

Every error in the scripts tells you the cause and the next command. The most
common ones:

| Symptom | Cause and fix |
|---------|----------------|
| `Could not download ...` | No route to GitHub, or a proxy is required. Pass `--download-proxy URL`. |
| `Checksum mismatch` | Broken/captive download or tampering. Nothing was installed. Retry on another network. |
| `Port 80 is currently used by nginx` | Certbot needs 80 for ~20 s. The installer offers to stop it and records renewal hooks. |
| `DNS ... does not point to ...` | Fix the A record, turn off Cloudflare's orange proxy while issuing, wait for TTL. |
| `HAProxy rejected ...` | The generated config is tested before reload; the exact line is printed. |
| `xrv-relay is not active` | `journalctl -u xrv-relay -n 40`; usual cause is a bad config or a busy port. |
| Client: `pre-flight FAILED ... HTTP 404` | The Apps Script deployment ID is wrong, deleted, or the Web App is not published as "Anyone". |
| Client: `port is already in use` | `~/xrv/stop-xrv.sh`, or choose another `--socks-port`. |
| Exit IP equals real IP | The tunnel is not carrying traffic. Check `~/xrv/xrv-client.log` and server health. |
| Termux disconnects when the screen locks | Enable the Termux wake-lock (the start script does it) and disable battery optimization for Termux. |

More detail: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

---

## Development and tests

```bash
bash -n xrv-install.sh xrv-client.sh
shellcheck -S warning xrv-install.sh xrv-client.sh
bash tests/run-all.sh
```

The test suite covers:

- shell syntax and ShellCheck;
- every input validator and deployment-ID normaliser;
- config generation and JSON schema;
- a complete offline client install in a temporary HOME;
- HAProxy configuration validation (when HAProxy is installed);
- SHA-256 values for the pinned upstream release.

---

## License

MIT. See [LICENSE](LICENSE).

Upstream GooseRelayVPN is a separate MIT project:
<https://github.com/Kianmhz/GooseRelayVPN>.
