# XRV v1.0 — Live Test Checklist

## Prerequisites

### VPS (Ubuntu 22.04/24.04 amd64)
- [ ] Fresh VPS, root access
- [ ] Domain pointing to VPS IP (A record)
- [ ] Ports 22, 80, 443, 8443 open (cloud firewall + UFW)
- [ ] 2 Google accounts ready

### Client (Linux amd64 or Android Termux arm64)
- [ ] Linux: any distro with curl, python3, ss
- [ ] Android: Termux (F-Droid), storage permission granted

---

## Phase 1: VPS Install (as root)

```bash
# On VPS
cd /root
bash <(curl -fsSL https://raw.githubusercontent.com/jackh0006/XRV-Installer/main/xrv-install.sh)
# Select: 2) Server installation
# Follow prompts:
#   - Domain: vpn.example.com
#   - Email: admin@example.com
#   - Let certbot complete
```

### VPS Verification (run test-on-vps.sh)

```bash
bash test-on-vps.sh
```

**Expected all OK:**
- [ ] xrv-relay active
- [ ] haproxy active
- [ ] Backend healthz: HTTP 200
- [ ] Public endpoint: HTTP 200
- [ ] HAProxy cert present
- [ ] Ports 9443, 8443 listening

---

## Phase 2: Apps Script Deployments (2 Google accounts × 2 deployments each)

For EACH Google account:
1. Go to https://script.google.com → New project
2. Delete sample code, paste `Code.gs` from client folder
3. Verify `RELAY_URLS = ['https://vpn.example.com:8443/tunnel']`
4. Deploy → New deployment → Web app → Execute as: Me, Who has access: Anyone → Deploy
5. Copy Deployment ID (AKfycb...)
6. Repeat for 2nd deployment in same account (different script file or same with different config)

**Result:** 4 Deployment IDs across 2 accounts

---

## Phase 3: Client Install (Linux)

```bash
# On client machine (no root)
bash <(curl -fsSL https://raw.githubusercontent.com/jackh0006/XRV-Installer/main/xrv-install.sh)
# Select: 3) Client installation → 1) Linux amd64
# Follow prompts:
#   - Enter 4 Deployment IDs (AKfycb...)
#   - Account labels: acct-a, acct-b, acct-c, acct-d
#   - Tunnel key from VPS: cat /root/xrv-tunnel-key.txt
#   - Relay URL: https://vpn.example.com:8443/tunnel
```

### Start Client

```bash
cd ~/xrv
./start-xrv.sh
# Wait for:
#   - "pre-flight OK"
#   - "ready: local SOCKS5 is listening"
```

### Client Verification (run test-client.sh)

```bash
bash test-client.sh
```

**Expected all OK:**
- [ ] client_config.json present
- [ ] goose-client binary executable
- [ ] SOCKS5 port 1080 listening
- [ ] SOCKS5 LIVE — exit IP: <VPS_IP>
- [ ] Traffic routed through VPS (IP differs from local)
- [ ] Client config schema valid
- [ ] 4 Deployment IDs configured

---

## Phase 4: Browser Test

1. Firefox → Settings → Network Settings → Settings...
2. Manual proxy → SOCKS Host: 127.0.0.1 Port: 1080
3. SOCKS v5 + "Proxy DNS when using SOCKS v5" → OK
4. Visit https://api.ipify.org → **Must show VPS IP**
5. Visit https://dnsleaktest.com → Run standard test → **Must show VPS DNS**

---

## Phase 5: Android Test (Optional)

```bash
# On Linux machine (prepares folder for phone)
bash xrv-install.sh
# Select: 3) Client installation → 2) Android arm64
# Follow prompts (same as Linux)
# Transfer ~/xrv-android folder to phone (scp, USB, cloud)
```

On phone (Termux):
```bash
cd ~/storage/downloads/XRV-android
chmod +x goose-client start-xrv.sh stop-xrv.sh
./start-xrv.sh
# Wait for pre-flight OK → ready
```

In NekoBox/v2rayNG:
- SOCKS5 127.0.0.1:1080
- **EXCLUDE Termux from proxy** (critical!)
- Test: visit https://api.ipify.org in browser → shows VPS IP

---

## Phase 6: Doctor & Ongoing Ops

```bash
# VPS health
bash xrv-install.sh → 6) Doctor v2
bash xrv-install.sh → 7) Status & health

# Add more deployments later
bash xrv-install.sh → 4) Deployment-ID manager → 2) Add

# View audit log
cat /var/log/xrv/audit.log   # VPS
cat ~/.xrv/logs/audit.log    # Client
```

---

## Troubleshooting Quick Reference

| Symptom | Fix |
|---------|-----|
| "Connection reset" / "pre-flight fails" | Another VPN TUN is ON (v2rayN, etc.) — turn off |
| SOCKS5 port busy | `./stop-xrv.sh` then restart |
| "Blacklisted for 3s" in logs | NORMAL — quota rotation, ignore if bytes > 0 |
| Exit IP = local IP | Tunnel not working, check client logs |
| Certbot fails | Check domain DNS, ports 80/443 open, try `--dry-run` first |
| HAProxy won't start | `haproxy -c -f /etc/haproxy/haproxy.cfg` for config errors |

---

## Success Criteria ✅

- [ ] VPS: xrv-relay + HAProxy running, healthz 200 on public endpoint
- [ ] Client: start-xrv.sh → pre-flight OK → ready
- [ ] Browser via SOCKS5 → api.ipify.org shows VPS IP
- [ ] DNS leak test shows VPS DNS
- [ ] Doctor v2 → Verdict: OK
- [ ] Can add/remove deployment IDs via menu 4

---

## Next: GitHub Release

```bash
cd ~/xrv-installer
./push-to-github.sh
# Then tag release:
git tag v1.0.0 && git push origin v1.0.0
# GitHub Actions will auto-create release
```
