# XRV v1.1.1 — live test checklist

Use this on a fresh VPS and a fresh client. Every step says what success looks
like and where to look when it does not.

## 0. Before you start

### VPS
- [ ] Ubuntu 22.04/24.04 or Debian 12, amd64 or arm64, root.
- [ ] A domain with an **A record** pointing to the VPS IPv4.
- [ ] Cloud firewall allows TCP **22**, **80**, **8443** (or your chosen port).
- [ ] At least 200 MB free disk.
- [ ] One or two Google accounts ready.

### Client
- [ ] Linux amd64/arm64 with `curl`, `tar`, `sha256sum`.
- [ ] Or Termux from F-Droid on arm64 Android.

---

## 1. Server install

```bash
git clone https://github.com/jackh0006/XRV-Installer.git
cd XRV-Installer
sudo bash xrv-install.sh
# 1) Install or update the server
```

Expected:

- [ ] Domain and email accepted.
- [ ] DNS check passes (or you deliberately continue).
- [ ] Firewall shows SSH + 80 + 8443, and UFW is active.
- [ ] Let's Encrypt issues an ECDSA certificate.
- [ ] `xrv-relay` and `xrv-haproxy` are active.
- [ ] The public TLS check passes.
- [ ] The summary prints the relay URL and the key path.

If anything fails, the last lines name the cause. Run:

```bash
sudo bash xrv-install.sh --check
```

---

## 2. Server verification

```bash
sudo bash test-on-vps.sh
```

Expected all pass or explained warnings:

- [ ] `xrv-relay` active.
- [ ] `xrv-haproxy` active.
- [ ] Relay binary, config and key present.
- [ ] Key permissions 600.
- [ ] Local health `http://127.0.0.1:9443/healthz`.
- [ ] Certificate valid for more than 14 days.
- [ ] Public TLS is trusted and TLS 1.3.
- [ ] Public `https://<domain>:8443/healthz` returns 200.
- [ ] Renewal timer is active.

Manual checks:

```bash
sudo systemctl status xrv-relay xrv-haproxy --no-pager
sudo ss -ltnp 'sport = :8443'
sudo ss -ltnp 'sport = :9443'
sudo openssl s_client -connect vpn.example.com:8443 \
  -servername vpn.example.com -verify_return_error </dev/null | \
  grep -E 'Verify return code|Protocol|Cipher'
```

You want `Verify return code: 0 (ok)` and `TLSv1.3`.

---

## 3. Apps Script

- [ ] Open `sudo cat /etc/xrv/Code.gs`.
- [ ] Paste it into a new project at <https://script.google.com>.
- [ ] Deploy -> New deployment -> Web app.
- [ ] Execute as **Me**, access **Anyone**.
- [ ] Copy the `AKfycb...` Deployment ID.
- [ ] Repeat for a second account if you want more quota.

> Editing the code later requires a **new deployment**, not just Save.

---

## 4. Client install

### Linux

```bash
bash xrv-client.sh
```

### Termux

```bash
pkg update && pkg install -y curl tar
bash xrv-client.sh
```

Answer:

- [ ] Relay: `vpn.example.com` (or the full `https://.../tunnel` URL).
- [ ] Port: `8443`.
- [ ] Deployment ID(s): paste one or more, with the same account label for the
      same Google account.
- [ ] Tunnel key: `sudo cat /etc/xrv/tunnel_key` on the VPS.
- [ ] Local SOCKS port: `1080`.
- [ ] Optional LAN sharing: **no** unless you understand the quota risk.
- [ ] Optional SOCKS password: only if you need it.

Expected:

- [ ] SHA-256 verified.
- [ ] Binary architecture verified.
- [ ] `client_config.json` mode 600.
- [ ] `start-xrv.sh`, `stop-xrv.sh`, `status-xrv.sh` executable.
- [ ] Proxy listening on 1080.

---

## 5. Client verification

```bash
bash test-client.sh
```

Expected:

- [ ] Config present and mode 600.
- [ ] Key is 64 lowercase hex characters.
- [ ] At least one deployment.
- [ ] Client binary runs (`-version`).
- [ ] SOCKS port listening.
- [ ] Relay health 200.
- [ ] Certificate trusted.
- [ ] Live SOCKS test returns the VPS IP.
- [ ] Exit IP differs from your real IP.

Manual:

```bash
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

Must print the **VPS IP**.

---

## 6. Browser / Android

### Firefox
- [ ] Manual proxy -> SOCKS host `127.0.0.1`, port `1080`, SOCKS v5.
- [ ] "Proxy DNS when using SOCKS v5" enabled.
- [ ] <https://api.ipify.org> shows the VPS IP.
- [ ] <https://dnsleaktest.com> shows the VPS DNS.

### Android
- [ ] NekoBox/v2rayNG -> SOCKS5 `127.0.0.1:1080`.
- [ ] Termux excluded from the proxy.
- [ ] Wake-lock active while XRV runs.
- [ ] Browser shows the VPS IP.

---

## 7. Certificate lifecycle

- [ ] `sudo bash xrv-install.sh --cert` -> **Show** displays dates.
- [ ] **Dry run** succeeds.
- [ ] Optional **Force new** succeeds and reloads HAProxy without downtime.
- [ ] Optional **Replace domain** deletes the old files and issues the new name.
- [ ] Optional **Revoke and delete** works on a throwaway domain.

After a renewal, confirm:

```bash
sudo systemctl status certbot.timer
sudo certbot certificates
```

---

## 8. Update and rotate

- [ ] `sudo bash xrv-install.sh --update` keeps the config and key.
- [ ] `sudo bash xrv-install.sh --rotate-key` creates a new key.
- [ ] Old clients fail until updated; new key works after updating one client.

---

## 9. Uninstall

On the client:

```bash
bash xrv-client.sh --uninstall
```

On the VPS:

```bash
sudo bash xrv-install.sh --uninstall
```

- [ ] Services stopped and disabled.
- [ ] Ports closed if requested.
- [ ] Config/key removed only if requested.

---

## Success criteria

- [ ] Server: both services active, public health 200, TLS 1.3 trusted.
- [ ] Client: `ready: local SOCKS5 is listening`, live exit IP is the VPS.
- [ ] Doctor: no FAIL lines on both sides.
- [ ] Certificate renews, or the dry run proves it will.
- [ ] No tunnel key or deployment ID appears in any log.
