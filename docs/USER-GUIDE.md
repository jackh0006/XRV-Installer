# XRV — the complete plain-language guide

This guide explains the whole project in everyday words. You do not need to
know networking, Linux, or Google Apps Script before starting. Every step says
what to do, what you should see, and what to do if it does not happen.

If you only remember one thing, remember this:

> The **tunnel key** is the only key to your tunnel. Never post it, never send
> it, never put it in a screenshot.

---

## 1. What XRV actually does

Imagine you want to send a letter, but you do not want the post office to read
it or to know where it is going.

XRV does three things:

1. It locks your letter inside a strong box.
2. It puts that box inside an ordinary-looking envelope addressed to Google.
3. It sends the envelope to a small computer that **you** control. That computer
   opens the box and delivers the letter to the real destination.

The post office only sees a normal envelope going to Google. Google only sees a
locked box. Only your computer and your small server know how to open it.

The small computer you control is called a **VPS**. The program on your phone or
laptop is called the **client**. The program on the VPS is called the **relay**
or **server**.

```
Your app
   |
   |  talks to 127.0.0.1:1080  (a local door on your own device)
   v
XRV client  --- encrypted --->  Google  --->  your VPS  --->  the internet
```

Nothing is sent to the XRV authors. There is no account, no tracking, and no
telemetry.

---

## 2. Words used in this guide

You will see these words in the installer. Here is what they mean:

| Word | Simple meaning |
|---|---|
| **VPS** | A small computer you rent that stays on all the time. |
| **Domain** | A nickname for that computer, like `vpn.example.com`. |
| **IP address** | The computer's number, like `203.0.113.10`. |
| **Port** | A door number on the computer. XRV uses `8443` by default. |
| **Certificate** | An ID badge that proves the domain really belongs to your server. |
| **Tunnel key** | A 64-character password. The only key to your tunnel. |
| **Deployment ID** | A long code from Google that points to your Apps Script. It starts with `AKfycb`. |
| **SOCKS5** | The local door your browser or app uses: `127.0.0.1:1080`. |
| **Termux** | A terminal app for Android that lets you run Linux programs. |
| **Apps Script** | A small Google program that forwards your encrypted bytes to the VPS. |

---

## 3. What you need before starting

### A small server

- Ubuntu 22.04 or 24.04, or Debian 12.
- 64-bit Intel/AMD (`amd64`) or 64-bit ARM (`arm64`).
- Root access.
- About 200 MB of free space.
- A public IPv4 address.

### A domain name

A domain is strongly recommended. It lets the server show a real certificate.
An IP address alone cannot normally have a trusted certificate.

In your domain provider's DNS panel, add:

```
Type: A
Name: vpn          (or @ for the root domain)
Value: YOUR_VPS_IPV4
TTL: 300
```

Wait a few minutes. You can check it from your own computer:

```bash
nslookup vpn.example.com
```

You want to see your VPS IP in the answer.

### Ports

Open these in **both** places: your VPS firewall and your hosting provider's
firewall panel.

| Port | Why |
|---|---|
| SSH port (usually 22) | So you can log in. |
| 80 | Let's Encrypt uses it for a few seconds to prove you own the domain. |
| 8443 | The encrypted tunnel. You can choose 443 instead. |

### Google

One Google account is enough to start. Two accounts give more daily quota.

### Your device

- Linux with `curl` and `tar`.
- Or Android with Termux installed from **F-Droid** (not the Play Store).

---

## 4. Part one: set up the server

This is the small computer that stays on all the time.

### Step 1 — log in

Use SSH. Your hosting provider gives you the exact command, usually:

```bash
ssh root@YOUR_VPS_IPV4
```

### Step 2 — get the installer

```bash
curl -fsSLO https://raw.githubusercontent.com/jackh0006/XRV-Installer/main/xrv-install.sh
```

If `curl` is missing:

```bash
apt update && apt install -y curl
```

### Step 3 — start it

```bash
sudo bash xrv-install.sh
```

Choose:

```
1) Install or update the server
```

### Step 4 — answer the questions

The installer will ask for:

1. **Domain** — type `vpn.example.com`.
2. **Email** — a real address. Let's Encrypt uses it only for certificate
   warnings.
3. **Public port** — press Enter for `8443`.
4. **Upstream proxy** — press Enter for none, unless you already run a local
   SOCKS5 proxy such as Cloudflare WARP.

You may also see a question about stopping nginx or Apache for about 20 seconds.
That is normal: the certificate check needs door 80 free for a moment. The
installer puts the service back and records how to do it again next time.

### Step 5 — wait for the green lines

You should see:

```
✔ Relay service is running
✔ Relay answers locally
✔ TLS front is running
✔ Public TLS endpoint is healthy
✔ Apps Script file written
```

At the end it prints your **relay URL**, for example:

```
https://vpn.example.com:8443/tunnel
```

Write it down. You will paste it into the client.

### Step 6 — copy the tunnel key

On the server:

```bash
sudo cat /etc/xrv/tunnel_key
```

It prints 64 characters made of `0-9` and `a-f`. Keep this window open or copy
it somewhere private. Do not email it, chat it, or post it.

### Step 7 — check the server

```bash
sudo bash xrv-install.sh --check
```

You want no `FAIL` lines. Warnings are explained in the output.

If something fails, the installer prints the reason and the exact command to
try next. You can also read:

```bash
sudo journalctl -u xrv-relay -n 50 --no-pager
sudo journalctl -u xrv-haproxy -n 50 --no-pager
```

---

## 5. Part two: create the Google piece

This is the free part that hides your traffic inside ordinary Google HTTPS.

1. Open <https://script.google.com> in a browser.
2. Click **New project**.
3. On the VPS, print the file the installer made:

   ```bash
   sudo cat /etc/xrv/Code.gs
   ```

   Or, after you install the client, use `~/xrv/Code.gs`.

4. Select everything in the editor and delete it.
5. Paste the whole `Code.gs` file.
6. Click **Deploy** -> **New deployment**.
7. Choose **Web app**.
8. Set:
   - **Execute as:** Me
   - **Who has access:** Anyone
9. Click **Deploy**. Approve the Google permission screen.
10. Copy the **Deployment ID**. It is the long code that starts with `AKfycb`.

> If you edit the code later, you must create a **new deployment**. Just saving
> the file does not publish the change.

You can repeat this in a second Google account to get more daily quota. Use a
different `account` label for each account in the client.

---

## 6. Part three: set up your device

### Linux

```bash
curl -fsSLO https://raw.githubusercontent.com/jackh0006/XRV-Installer/main/xrv-client.sh
bash xrv-client.sh
```

If you downloaded the repository already, just run:

```bash
bash xrv-client.sh
```

### Android with Termux

1. Install **Termux** from F-Droid.
2. Open Termux and run:

   ```bash
   pkg update && pkg install -y curl tar
   curl -fsSLO https://raw.githubusercontent.com/jackh0006/XRV-Installer/main/xrv-client.sh
   bash xrv-client.sh
   ```

### Questions the client asks

1. **Relay domain or IP** — type `vpn.example.com`.
2. **Relay port** — press Enter for `8443`.
3. **Deployment ID** — paste the `AKfycb...` code. Press Enter to add another,
   or press Enter on an empty line when done.
4. **Account label** — use the same label for deployments in the same Google
   account, for example `acct-a`. Use `acct-b` for a second account.
5. **Tunnel key** — paste the 64 characters from the server. Nothing appears
   while you type; that is normal.
6. **Local SOCKS port** — press Enter for `1080`.
7. Optional questions:
   - Share with other devices on your network? Say **no** unless you need it.
   - Require a local username and password? Say **no** unless you need it.
   - Download through a proxy? Only if your network requires one.

The client downloads the official program, checks its fingerprint, and sets
everything up in `~/xrv`.

At the end it asks:

```
Start the tunnel now?
```

Say **yes**. Wait for:

```
pre-flight OK
ready: local SOCKS5 is listening
```

`pre-flight OK` means the client reached Google and your server. If it says
`pre-flight FAILED` with `404`, the Deployment ID is wrong or the Web App is not
published for Anyone.

---

## 7. Make your browser use it

### Firefox

1. Open **Settings**.
2. Search for **Network Settings**.
3. Click **Settings...**.
4. Choose **Manual proxy configuration**.
5. SOCKS Host: `127.0.0.1`
6. Port: `1080`
7. Choose **SOCKS v5**.
8. Tick **Proxy DNS when using SOCKS v5**.
9. Click **OK**.

### Chrome or Edge

Install an extension such as FoxyProxy or SwitchyOmega, then add:

```
Type: SOCKS5
Host: 127.0.0.1
Port: 1080
```

### Android

In NekoBox or v2rayNG:

```
Type: SOCKS5
Host: 127.0.0.1
Port: 1080
```

Then **exclude Termux** from the proxy. If you do not, Termux loses the
connection it needs to keep the tunnel alive.

### Test it

In a terminal:

```bash
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

The answer must be the **VPS IP**, not your real IP.

You can also open <https://api.ipify.org> in the browser.

---

## 8. Everyday use

### Linux

```bash
~/xrv/start-xrv.sh     # start
~/xrv/stop-xrv.sh      # stop
~/xrv/status-xrv.sh    # is it running?
```

### Termux

```bash
cd ~/xrv
./start-xrv.sh
```

Press `Ctrl+C` or run `./stop-xrv.sh` to stop.

### Check everything

```bash
bash xrv-client.sh --check
```

On the server:

```bash
sudo bash xrv-install.sh --check
```

### Logs

```bash
tail -n 50 ~/xrv/xrv-client.log
```

The tunnel key and deployment IDs are hidden in logs.

---

## 9. Certificates in plain words

A certificate is an ID badge. It expires. The installer renews it by itself.

To look at it or replace it:

```bash
sudo bash xrv-install.sh --cert
```

Choices:

| Choice | What it means |
|---|---|
| Show | See the dates and how many days are left. |
| Renew | Ask for a fresh badge now. |
| Force new | Throw away the old files and get a new badge. |
| Replace domain | Use a new domain name. The old files are removed first. |
| Revoke and delete | Emergency only: the badge was stolen or the key leaked. |
| Dry run | Practise renewal without changing anything. |

You normally do not need to touch this menu. The timer checks twice a day.

---

## 10. Updating

Server:

```bash
sudo bash xrv-install.sh --update
```

This replaces only the relay program. Your config and tunnel key stay the same.

Client:

```bash
bash xrv-client.sh --update
```

This replaces only the client program. Your config and tunnel key stay the same.

If you want a **new tunnel key**:

```bash
sudo bash xrv-install.sh --rotate-key
```

Then every client needs the new key. Old clients will stop working until they
get it.

---

## 11. Common problems in plain words

### “Could not download”

Your device cannot reach GitHub.

- Check:

  ```bash
  curl -I https://github.com
  ```

- If your network needs a proxy, pass it:

  ```bash
  bash xrv-client.sh --proxy http://127.0.0.1:8080
  ```

### “Checksum mismatch”

The file you received is not the exact file we trust. Nothing was installed.
Try again on another network. Do not skip this check.

### “Port 80 is already used”

Another web server is using the door Let's Encrypt needs. The installer offers
to stop it for about 20 seconds and put it back. Say yes if it is nginx or
Apache. If it is something else, stop it yourself and run:

```bash
sudo bash xrv-install.sh --cert
```

### “DNS does not point to this server”

The domain's address does not match the VPS.

1. Open your domain provider's DNS page.
2. Set the A record to the VPS IPv4.
3. Wait a few minutes.
4. Try again.

If Cloudflare is in front, set the record to **DNS only** (grey cloud) while
issuing the certificate.

### “Pre-flight FAILED … 404” on the client

The Apps Script deployment ID is wrong, deleted, or not public.

1. Open the Apps Script project.
2. **Deploy** -> **Manage deployments**.
3. Make sure access is **Anyone**.
4. Copy the ID between `/s/` and `/exec`.
5. Add it again:

   ```bash
   bash xrv-client.sh --deployment AKfycb...
   ```

### “Port 1080 is busy”

Something is already using the local door.

```bash
~/xrv/stop-xrv.sh
```

Or choose another port:

```bash
bash xrv-client.sh --socks-port 1081
```

### Browser shows my real IP

The browser is not using the tunnel.

1. Check the SOCKS settings: `127.0.0.1`, port `1080`, SOCKS v5.
2. Check that the client is running:

   ```bash
   ~/xrv/status-xrv.sh
   ```

3. Make sure another VPN's TUN mode is off. Two tunnels at once do not work.

### Termux stops when the screen turns off

- The start script takes a wake-lock.
- Disable battery optimization for Termux in Android settings.
- Exclude Termux from the proxy in NekoBox or v2rayNG.

### The server test fails

```bash
sudo bash xrv-install.sh --check --json
sudo journalctl -u xrv-relay -n 50 --no-pager
sudo journalctl -u xrv-haproxy -n 50 --no-pager
```

The first failing line names the cause. Do not edit files at random; fix that
one line.

---

## 12. Safety rules

1. Never share `client_config.json`. It contains the tunnel key.
2. Never share the 64-character key or a screenshot of it.
3. Never send a private key or recovery phrase to anyone. No maintainer will
   ask for one.
4. Run one VPN at a time. Turn off other TUN/TAP VPNs before starting XRV.
5. Keep the VPS updated.
6. Keep your SSH key private and your SSH port restricted if possible.
7. If the key leaks, rotate it immediately and update every client.

---

## 13. Removing everything

Client:

```bash
bash xrv-client.sh --uninstall
```

Server:

```bash
sudo bash xrv-install.sh --uninstall
```

The server script asks before deleting the certificate, the config, the key, or
the firewall rules.

---

## 14. What XRV cannot do

XRV hides the contents of your traffic from the network between you and your
VPS. It does not make you invisible.

- Google can see that you use Google and how much data you send.
- Your VPS provider can see the destinations your VPS connects to.
- A stolen tunnel key or a compromised server breaks the tunnel.
- Apps Script has a daily limit per Google account.
- This is not an anonymity network like Tor.

For the full threat model, read [SECURITY.md](../SECURITY.md).

---

## 15. Help and donations

- **Bug or documentation problem:** open an
  [issue](https://github.com/jackh0006/XRV-Installer/issues/new/choose).
- **Security problem:** use a
  [private advisory](https://github.com/jackh0006/XRV-Installer/security/advisories/new).
- **What to include:** [SUPPORT.md](../SUPPORT.md).
- **Optional donations:** [DONATE.md](../DONATE.md).

A donation is optional. It does not buy support, priority, or a different
license.

---

## 16. One-page summary

```text
SERVER
  sudo bash xrv-install.sh          -> choose 1
  sudo cat /etc/xrv/tunnel_key      -> copy 64 characters
  relay URL: https://YOUR-DOMAIN:8443/tunnel

GOOGLE
  script.google.com -> New project -> paste /etc/xrv/Code.gs
  Deploy -> New deployment -> Web app
  Execute as Me, access Anyone -> copy AKfycb...

CLIENT
  bash xrv-client.sh
  paste relay URL, port 8443, AKfycb..., tunnel key
  ./start-xrv.sh

BROWSER
  SOCKS5 127.0.0.1:1080
  test: curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

That is the whole project.
