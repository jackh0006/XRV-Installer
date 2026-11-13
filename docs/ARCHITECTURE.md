# Architecture

## Components

```
+-------------------+        +----------------------+        +------------------+
| Client device     |        | Google               |        | Your VPS         |
|                   |        |                      |        |                  |
| app -> SOCKS5     |  TLS   | Apps Script doPost() |  TLS   | xrv-haproxy      |
| 127.0.0.1:1080    | -----> | (dumb forwarder)     | -----> | :8443 TLS 1.3    |
| xrv-client        |        |                      |        |        |         |
| AES-256-GCM       |        |                      |        |        v         |
+-------------------+        +----------------------+        | xrv-relay        |
                                                             | 127.0.0.1:9443   |
                                                             |        |         |
                                                             |        v         |
                                                             | the internet     |
                                                             +------------------+
```

### Client (`goose-client`)

- Listens on `socks_host:socks_port` (default `127.0.0.1:1080`).
- Groups TCP frames, compresses batches with Zstandard and encrypts each batch
  with AES-256-GCM.
- Sends each batch to an Apps Script deployment over TLS to a Google edge IP
  with `SNI=www.google.com`.
- Keeps idle long-polls open per Google-account bucket to receive downstream
  bytes.
- Rotates deployments, blacklists failing ones, and groups them by the
  `account` label so per-account quotas are respected.

### Google Apps Script (`Code.gs`)

- About 30 lines. Forwards request bytes verbatim to `RELAY_URLS`.
- Does not decrypt, does not hold the key.
- Retries the next relay URL on failure.
- Returns a JSON invocation counter on `GET /exec` for diagnostics.

### TLS front (`xrv-haproxy`)

- Dedicated HAProxy instance and config. It does not touch the distro
  `/etc/haproxy/haproxy.cfg`.
- Binds the public port (default 8443) with TLS 1.3 only.
- Accepts `GET /healthz` and `POST /tunnel`, denies everything else with 404.
- Health-checks the relay on `127.0.0.1:9443/healthz`.
- Uses long timeouts for long-polling and `http-reuse always`.
- Reads a combined PEM (full chain + private key) from
  `/etc/haproxy/certs/<domain>.pem`.

### Relay (`xrv-relay`)

- Go binary `goose-server` from the pinned upstream release.
- Binds `127.0.0.1:9443` in TLS mode (only HAProxy can reach it).
- Decrypts with the shared tunnel key, opens real TCP connections, and pumps
  bytes back.
- Optional `upstream_proxy` sends outbound connections through a local SOCKS5
  proxy (for example Cloudflare WARP).
- Runs as `xrv`, with no capabilities and a read-only filesystem.

### Certificates

```
Let's Encrypt HTTP-01
  -> certbot --standalone
  -> /etc/letsencrypt/live/<domain>/fullchain.pem + privkey.pem
  -> deploy hook rebuilds /etc/haproxy/certs/<domain>.pem
  -> systemctl reload xrv-haproxy
```

`certbot.timer` checks twice a day. The deploy hook runs only when a
certificate is actually renewed.

## Network and ports

| Port | Who listens | Why |
|------|-------------|-----|
| SSH (detected) | sshd | Administration |
| 80/tcp | certbot, only during issuance/renewal | Let's Encrypt HTTP-01 |
| 8443/tcp (default) | `xrv-haproxy` | Public TLS tunnel |
| 9443/tcp | `xrv-relay`, localhost only | Backend, never exposed |
| 1080/tcp | `goose-client`, localhost by default | Local SOCKS5 |

## File layout

### VPS

```
/opt/xrv/bin/xrv-server              relay binary
/etc/xrv/server_config.json          relay config (mode 600)
/etc/xrv/tunnel_key                  shared AES key (mode 600)
/etc/xrv/state.conf                  installer state (mode 600)
/etc/xrv/Code.gs                     Apps Script file with the relay URL
/etc/haproxy/xrv.cfg                 TLS front config
/etc/haproxy/certs/<domain>.pem      certificate + key bundle (mode 640)
/etc/systemd/system/xrv-relay.service
/etc/systemd/system/xrv-haproxy.service
/var/log/xrv/install.log             installer log (secrets redacted)
```

### Client

```
~/xrv/goose-client                   client binary
~/xrv/client_config.json             config + tunnel key (mode 600)
~/xrv/Code.gs                        Apps Script file
~/xrv/start-xrv.sh / stop-xrv.sh / status-xrv.sh
~/xrv/GUIDE.txt
~/xrv/xrv-client.log
~/xrv/.xrv-state                     relay URL / platform / date
~/.xrv/logs/install.log              installer log (secrets redacted)
```

## Trust boundaries

1. The tunnel key is generated on the VPS and copied to clients by the user.
   It is never sent to Google.
2. The Apps Script sees only ciphertext. It forwards to the relay URL.
3. The relay is the only place that decrypts and dials real destinations.
4. HAProxy is the only public listener and allows only the tunnel and health
   paths.
5. The distro HAProxy configuration and other sites are left alone.

## Failure handling

- Any failed download stops before execution.
- Any checksum mismatch stops before extraction.
- Any archive with unsafe paths or links is rejected.
- HAProxy config is validated with `haproxy -c` before restart/reload.
- systemd services are checked with `is-active`; failures print the journal.
- Certificate failures print the common causes and the exact retry command.
- Every installer writes a redacted log so a failure can be diagnosed later
  without exposing the tunnel key.
