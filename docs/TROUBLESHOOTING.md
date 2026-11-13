# Troubleshooting

Every message in the installer names what failed and the next command. This
page collects the longer explanations.

## First commands to run

On the VPS:

```bash
sudo bash xrv-install.sh --check
sudo systemctl status xrv-relay xrv-haproxy --no-pager
sudo journalctl -u xrv-relay -n 50 --no-pager
sudo journalctl -u xrv-haproxy -n 50 --no-pager
sudo tail -n 50 /var/log/xrv/install.log
```

On the client:

```bash
bash xrv-client.sh --check
~/xrv/status-xrv.sh
tail -n 50 ~/xrv/xrv-client.log
```

---

## Server installation

### `Could not download ...`

The server could not reach GitHub.

1. Check the network:

   ```bash
   curl -I https://github.com
   ```

2. If your network needs a proxy:

   ```bash
   sudo bash xrv-install.sh --server --download-proxy http://127.0.0.1:8080 ...
   ```

3. If DNS is broken, fix `/etc/resolv.conf` or the provider's DNS first.

### `Security check failed ... Checksum mismatch`

Nothing was installed. The bytes on the wire are not the release we trust.
This can be a corrupted download, a captive portal, or tampering. Try again on
another network. If it repeats, open a security advisory; do not bypass it.

### `Port 80 is currently used by ...`

Let's Encrypt's HTTP-01 check needs port 80 for about 20 seconds.

- The installer offers to stop nginx/apache2/haproxy for the check.
- It records `pre_hook`/`post_hook` in the Certbot renewal config so future
  renewals do the same.
- If the process is unknown, stop it manually and re-run:

  ```bash
  sudo ss -ltnp 'sport = :80'
  sudo bash xrv-install.sh --cert
  ```

### `DNS for ... does not point to ...`

Create an A record:

```
vpn.example.com.   300   IN   A   203.0.113.10
```

If Cloudflare is in front, set the record to **DNS only** (grey cloud) while
issuing the certificate. The HTTP-01 challenge must reach your VPS directly.

### `HAProxy rejected the generated configuration`

This should not happen with a correct install. The exact line is printed. The
config is validated with `haproxy -c` before anything is reloaded. Capture the
output and open an issue; your running service is left untouched.

### `The TLS front did not stay running`

```bash
sudo journalctl -u xrv-haproxy -n 80 --no-pager
sudo /usr/sbin/haproxy -c -f /etc/haproxy/xrv.cfg
```

Common causes:

- the certificate bundle is missing or unreadable by `haproxy`;
- another process owns the public port;
- the HAProxy version is older than 2.2 (Ubuntu 20.04 is not supported).

Fix the first error in the journal, then:

```bash
sudo systemctl restart xrv-haproxy
```

### `The relay service did not stay running`

```bash
sudo journalctl -u xrv-relay -n 80 --no-pager
sudo cat /etc/xrv/server_config.json
```

The relay refuses to start if:

- the JSON is malformed;
- `tunnel_key` is not 64 lowercase hex characters;
- the port is busy;
- the binary is for the wrong CPU architecture.

### `The relay is not healthy`

```bash
curl -v http://127.0.0.1:9443/healthz
sudo ss -ltnp 'sport = :9443'
```

If nothing listens, the service exited. Read its journal. If it listens but
returns an error, the upstream binary is rejecting the config.

### I lost the tunnel key

```bash
sudo cat /etc/xrv/tunnel_key
```

If the file is gone, rotate:

```bash
sudo bash xrv-install.sh --rotate-key
```

Then update every client.

### I need a new certificate or a new domain

```bash
sudo bash xrv-install.sh --cert
```

- **Renew now** keeps the name and forces a fresh certificate.
- **Replace domain** deletes the old certificate files, issues for the new name,
  rebuilds HAProxy, and updates the state.
- **Revoke and delete** is for a compromised key. After revoking, issue a new
  certificate.

Automatic renewal:

```bash
systemctl status certbot.timer
sudo certbot renew --dry-run
```

---

## Client installation

### `Could not download the official client`

- Check `curl -I https://github.com`.
- If you need a proxy for downloads only:

  ```bash
  bash xrv-client.sh --proxy http://127.0.0.1:8080
  ```

- On Termux, make sure `curl` and `tar` are installed:

  ```bash
  pkg install -y curl tar coreutils
  ```

### `The downloaded file is not the exact file we trust`

Nothing was installed. Retry on another network. If it repeats, treat it as a
supply-chain warning and do not bypass the check.

### `The downloaded program cannot run on this device`

You are installing a binary for another CPU or OS. Let the script detect the
platform (do not pass `--platform` unless you are preparing an offline bundle),
or use the correct Termux package:

```bash
uname -m          # aarch64 on arm64 Termux
```

### `Relay answered HTTP 404` or `pre-flight FAILED ... 404`

The Apps Script deployment ID is wrong, deleted, or not published.

1. Open the Apps Script project.
2. **Deploy -> Manage deployments**.
3. Make sure the Web App is deployed with:
   - Execute as: **Me**
   - Who has access: **Anyone**
4. Copy the ID between `/s/` and `/exec` (starts with `AKfycb`).
5. Add it:

   ```bash
   bash xrv-client.sh --deployment AKfycb...
   ```

Editing the code without creating a **new deployment** does not update the
published app.

### `Local port 1080 is already busy`

```bash
~/xrv/stop-xrv.sh
```

or choose another port:

```bash
bash xrv-client.sh --socks-port 1081
```

### The client starts but `api.ipify.org` shows my real IP

The tunnel is not carrying traffic.

1. Check the log:

   ```bash
   tail -n 100 ~/xrv/xrv-client.log
   ```

2. Check the relay:

   ```bash
   curl -v https://vpn.example.com:8443/healthz
   ```

3. Make sure your browser/app actually uses `127.0.0.1:1080` for **SOCKS5**.
4. Make sure another VPN's TUN mode is not capturing all traffic first.

### Termux stops when the screen turns off

The start script takes a Termux wake-lock. Also:

- disable battery optimization for Termux in Android settings;
- keep Termux in the foreground while starting;
- in NekoBox/v2rayNG, **exclude Termux** from the proxy.

### Android says "permission denied" when running the binary

```bash
chmod 755 ~/xrv/goose-client ~/xrv/start-xrv.sh
```

Do not store the client on a filesystem mounted `noexec`.

---

## Certificate details

Check what is installed:

```bash
sudo openssl x509 -in /etc/letsencrypt/live/vpn.example.com/fullchain.pem \
  -noout -subject -issuer -dates
```

Check the live TLS handshake:

```bash
openssl s_client -connect vpn.example.com:8443 \
  -servername vpn.example.com -verify_return_error </dev/null
```

You want:

```
Verify return code: 0 (ok)
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
```

Check renewal:

```bash
sudo certbot renew --dry-run
systemctl list-timers | grep certbot
```

If the dry run fails because port 80 is busy, use the certificate manager's
replace/renew path so the service stop/start hooks are recorded.

---

## Reading the logs safely

The logs redact:

- the tunnel key (any 64-hex string in a key assignment);
- deployment IDs (`AKfycb...`).

They may still contain domains, IP addresses and timestamps. Review before
sharing. Never paste `client_config.json` or `server_config.json` into an
issue.

---

## Still stuck

Open an issue with:

```bash
sudo bash xrv-install.sh --check --json > /tmp/xrv-server-check.json
tail -n 100 /var/log/xrv/install.log > /tmp/xrv-install.log
```

Attach those two files. Do not attach configs or keys.
