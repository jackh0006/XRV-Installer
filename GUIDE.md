# XRV — The Complete Guide (Start to Finish)

XRV is a private tunnel for your internet traffic. It carries your traffic
inside ordinary HTTPS requests to Google, through a small server that you
control, and out to the real internet.

This guide starts at zero. It explains what XRV is, why you might need it, how
to build the server and client, how to install the Android app and the Linux
package, how to test everything, and what to do when something goes wrong.
You do not need to know networking first.

The most important rule:

> Your **tunnel key** is the only key to your tunnel. Never post it, send it,
> or show it in a screenshot.

---

## 1. What XRV does, in plain words

Imagine you want to send a letter, but you do not want the post office to read
it or to know where it is going.

XRV does three things:

1. It locks your letter inside a strong box.
2. It puts the box inside an ordinary envelope addressed to Google.
3. It sends the envelope to a small computer that **you** rent. That computer
   opens the box and delivers the letter to the real destination.

The post office only sees a normal envelope going to Google. Google only sees
a locked box. Only your phone or computer and your own small server know how to
open the box.

```
Your app
  -> 127.0.0.1:1080          (a private door on your own device)
  -> XRV client              (locks the traffic)
  -> HTTPS to a Google edge  (looks like ordinary Google traffic)
  -> Google Apps Script      (a dumb forwarder)
  -> your VPS :8443/tunnel   (TLS 1.3, HAProxy)
  -> the real internet
```

Nothing is sent to the XRV authors. There is no account, no tracking, no ads,
and no telemetry.

### What XRV protects

- The local network (hotel Wi-Fi, school Wi-Fi, airport Wi-Fi) cannot read your
  traffic.
- Your internet provider sees HTTPS to Google, not the sites you visit.
- The traffic between your device and your server has its own AES-256-GCM
  encryption. Google does not hold the key.
- Your server is the only exit. You control it.

### What XRV does not do

- It is not a magic anonymity network. Your server can see the traffic that
  leaves it. Use a server you trust.
- It does not hide the fact that you use Google.
- It does not protect a device that is already infected.
- It does not make you invisible to a global observer who can watch both ends.
- On Android, it cannot run at the same time as another full-device VPN.
  Android allows only one VPN at a time.

### Why someone would need it

- You use public Wi-Fi and do not want strangers reading your traffic.
- You want a private exit in another country for your own server or home
  network.
- You want a simple, open-source tunnel that does not require a paid VPN
  subscription.
- You want to learn how a modern encrypted relay works.

---

## 2. Words used in this guide

| Word | Simple meaning |
|---|---|
| **VPS** | A small computer you rent that stays on all the time. |
| **Domain** | A nickname for that computer, such as `vpn.example.com`. |
| **IP address** | The computer's number, such as `203.0.113.10`. |
| **Port** | A door number on the computer. XRV uses `8443` by default. |
| **Certificate** | An ID badge that proves the domain belongs to your server. |
| **Tunnel key** | A 64-character password. The only key to your tunnel. |
| **Deployment ID** | A long code from Google that points to your Apps Script. It starts with `AKfycb`. |
| **SOCKS5** | The local door your browser or app uses: `127.0.0.1:1080`. |
| **Apps Script** | A small Google program that forwards encrypted bytes to your VPS. |
| **TUN mode** | Android's system-wide VPN mode. Every app uses XRV. |
| **Proxy-only mode** | A local SOCKS5 proxy. Only apps that you point at it use XRV. |
| **Per-app proxy** | Choose which Android apps use the VPN. |

---

## 3. What you need

### A server

- Ubuntu 22.04 or 24.04, or Debian 12.
- 64-bit Intel/AMD (`amd64`) or 64-bit ARM (`arm64`).
- Root access.
- About 200 MB of free disk space.
- A public IPv4 address.

### A domain (strongly recommended)

A domain lets the server show a real certificate. An IP address alone cannot
normally have a trusted certificate.

In your domain provider's DNS panel, add:

```
Type: A
Name: vpn          (or @ for the root domain)
Value: YOUR_VPS_IPV4
TTL: 300
```

Wait a few minutes, then check:

```bash
nslookup vpn.example.com
```

You want your VPS IP in the answer.

### Ports

Open these in **both** your VPS firewall and your hosting provider's firewall:

| Port | Why |
|---|---|
| SSH (usually 22) | So you can log in. |
| 80 | Let's Encrypt uses it for a few seconds. |
| 8443 | The encrypted tunnel. You can choose 443 instead. |

### Google

One Google account is enough to start. Two accounts give more daily quota.

### Your devices

- **Android:** arm64 phone or tablet, Android 6.0 or newer.
- **Linux:** amd64, arm64, armhf, or i386. The `.deb` works on Debian/Ubuntu;
  other distributions can use `xrv-client.sh`.

---

## 4. Part one: set up the server

### Step 1 — log in

```bash
ssh root@YOUR_VPS_IPV4
```

### Step 2 — get the installer

```bash
curl -fsSLO https://raw.githubusercontent.com/jackh0006/XRV-Installer/main/xrv-install.sh
sudo bash xrv-install.sh
```

Choose **1) Install or update the server**.

### Step 3 — answer the questions

The installer asks for:

1. Your domain (for example `vpn.example.com`).
2. Your email (for the certificate).
3. A public tunnel port (default `8443`).
4. A private backend port (default `19443`; it stays on `127.0.0.1`).

It installs HAProxy, Certbot, the relay, a dedicated `xrv` user, a strict
systemd service, and a firewall rule for only the ports that are needed.

### Step 4 — wait for the green lines

You should see checks for the relay, the certificate, and the public TLS
endpoint. If a check fails, the installer prints the exact next command.

### Step 5 — copy the tunnel key

```bash
sudo cat /etc/xrv/tunnel_key
```

This is 64 hexadecimal characters. Keep it private. You will paste it into the
Android app or the Linux client.

### Step 6 — create the Google piece

1. Open <https://script.google.com> and create a new project.
2. Replace the code with the contents of `/etc/xrv/Code.gs` on your server.
3. Set `RELAY_URL` inside the file to your server, for example
   `https://vpn.example.com:8443/tunnel`.
4. Click **Deploy → New deployment → Web app**.
5. Set **Execute as: Me** and **Who has access: Anyone**.
6. Copy the **Deployment ID**. It starts with `AKfycb`.
7. Repeat with a second Google account if you want more quota.

You can copy `Code.gs` to your computer with:

```bash
sudo cat /etc/xrv/Code.gs
```

### Step 7 — check the server

```bash
sudo bash xrv-install.sh --check
```

All critical checks should say PASS. If not, read
[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

---

## 5. Part two: install the Android app

### Download

From the latest release:

```
XRV-Client-Android-arm64.apk        (recommended for most phones)
XRV-Client-Android-universal.apk    (all CPU types)
```

The universal APK includes arm64, 32-bit ARM, x86, and x86_64.

### Install

1. Uninstall any older XRV app first. Older releases used a different signing
   key.
2. Open the APK and allow installation when Android asks.
3. Open **XRV**.

### Configure

1. Expand **Configuration**.
2. Paste a deployment ID (a full `/exec` URL also works).
3. Paste the 64-character tunnel key.
4. Set the local port (default `1080`).
5. Tap **Connect**.

### TUN mode

TUN mode creates a full-device VPN. Every app uses XRV.

- Android shows its own VPN permission dialog. Accept it once.
- Android allows only one VPN at a time. If another VPN is active, XRV explains
  the conflict and offers to replace it or switch to proxy mode.
- On Huawei/EMUI, open **Settings → Battery settings** and exclude XRV from
  battery optimization. Otherwise Android may suspend the tunnel.

### Proxy-only mode

Proxy-only mode does not create a VPN. It opens an authenticated SOCKS5 proxy
on `127.0.0.1`.

1. Select **Proxy only** and connect.
2. The status card shows the port and the share card shows the generated
   username and password.
3. Tap **Copy**. The copied link looks like:
   `socks5://user:password@127.0.0.1:1080#XRV`
4. In v2rayNG or another SOCKS5 client, import or paste that link. The profile
   name is **XRV**, not `none`.

Use proxy-only mode when another VPN must stay connected, or when you only want
specific apps to use XRV.

### Per-app proxy (TUN only)

Open the gear icon → **Settings** → **Per-app proxy**.

- **Only selected apps**: only the apps you check use XRV.
- **All except selected apps**: checked apps bypass XRV.
- Tap **Choose apps**, search, and check the apps.
- Tap **Save**.
- Reconnect the VPN to apply the new list.

XRV always excludes itself so its own relay traffic cannot loop through its own
tunnel.

### Find the best Google edge

Open **Settings → Google edge**.

- The list starts with the four standard Google edges.
- Tap **Find fastest Google edge**. The app makes a real HTTPS request to each
  candidate and shows the latency.
- The fastest working edge is saved and used for the next connection.
- Add or remove IPv4 addresses in the candidate box.
- Tap **Use automatic edge** to return to the built-in default.

If no edge is chosen yet, the app runs this test automatically on the first
connection.

### Test the tunnel

Open **Settings → Test tunnel**.

XRV requests `https://api.ipify.org` through the authenticated local SOCKS5
proxy. It shows:

- The tunnel exit IP.
- The latency.
- The phone's direct IP.
- A warning if the two IPs are the same (traffic may not be using XRV).

### Logs

Open **Settings → View logs**.

- App events and native relay logs are shown together.
- Tunnel keys, deployment IDs, and proxy credentials are redacted.
- App events persist in private storage.
- Crashes are recorded with a stack trace.
- Use **Copy** to share the log when asking for help; use **Clear** to erase it.

### Traffic counters

The status card shows real SOCKS payload bytes, not raw VPN packet bookkeeping.
The counters stay at zero until an app actually sends traffic. The notification
shows the same values.

---

## 6. Part three: install the Linux client

### Debian / Ubuntu package

Download the package that matches your computer:

```
XRV-Client-linux-amd64.deb    (most Intel/AMD computers)
XRV-Client-linux-arm64.deb    (64-bit ARM)
XRV-Client-linux-armhf.deb    (32-bit ARM)
XRV-Client-linux-i386.deb     (32-bit Intel)
```

Install:

```bash
sudo dpkg -i XRV-Client-linux-amd64.deb
```

If dependencies are missing:

```bash
sudo apt-get -f install
```

### Configure

```bash
xrv-client setup
```

Answer the questions:

1. Paste your deployment ID or IDs.
2. Paste the tunnel key (hidden while typing).
3. Choose the local port (default `1080`).
4. The client tests the four Google edges and saves the fastest.

The setup prints a proxy link that ends in `#XRV` and includes the generated
username and password.

### Run

In a terminal:

```bash
xrv-client run
```

It prints:

```
XRV proxy ready.
  Proxy: socks5://user:password@127.0.0.1:1080#XRV
```

Leave it running, or run it in the background as a user service:

```bash
systemctl --user enable --now xrv-client
```

Check:

```bash
systemctl --user status xrv-client --no-pager
```

### Test

```bash
xrv-client test
```

It prints the tunnel exit IP, latency, and the direct IP. If they are the same,
traffic is not using XRV.

For a full check:

```bash
xrv-client check
```

### Use the proxy

- **Firefox:** Settings → Network Settings → Manual proxy → SOCKS Host
  `127.0.0.1`, port `1080`, SOCKS v5, proxy DNS when using SOCKS v5.
- **Chrome/Edge:** use the system proxy or an extension that supports SOCKS5.
- **v2rayNG/NekoBox:** add a SOCKS5 server with the printed username and
  password.
- **Terminal test:**
  ```bash
  curl --socks5-hostname --proxy-user 'user:password' \
    http://127.0.0.1:1080 https://api.ipify.org
  ```

### Commands

```bash
xrv-client setup      # configure
xrv-client run        # start in the foreground
xrv-client probe      # test Google edges (--write saves the fastest)
xrv-client test       # live exit-IP test
xrv-client check      # process + listener + live test
xrv-client status     # is it running?
xrv-client stop       # stop the background client
xrv-client logs       # last 500 log lines
xrv-client config     # redacted configuration
xrv-client version
```

### Other Linux distributions

The client is a static Go binary with no C library dependency. On Fedora,
Arch, openSUSE, and others, use the repository's `xrv-client.sh` installer or
extract the binary from the matching `.deb`:

```bash
dpkg-deb -x XRV-Client-linux-amd64.deb ./xrv
sudo install -m 0755 ./xrv/usr/bin/xrv-client /usr/local/bin/xrv-client
```

Then run `xrv-client setup`.

### Android TUN vs. Linux proxy

The Android app's TUN mode uses Android's `VpnService` to route every app.
Linux does not have that single API. The Linux package provides the same
encrypted relay engine, authenticated local SOCKS5 proxy, edge testing, tunnel
test, and logs as the Android app's **proxy-only mode**. Point applications at
the local proxy, or use your distribution's VPN tooling for system-wide
routing.

---

## 7. Using XRV with v2rayNG or another app

1. Start XRV in **Proxy only** mode.
2. Copy the proxy link from the app or the Linux client.
3. Import it into v2rayNG, NekoBox, or another SOCKS5 client.
4. The profile name is **XRV**.
5. Use the SOCKS5 hostname form so DNS is resolved by your exit, not your
   local network.

Do not route another VPN app's outbound traffic back through the same local
proxy while that VPN is active. That can create a loop. For system-wide
protection, use XRV's TUN mode.

---

## 8. Everyday use

### Android

- Tap **Connect**.
- The notification shows the active mode and real traffic.
- Tap **Disconnect** in the app or in the notification when you are done.

### Linux

```bash
xrv-client run
# or
systemctl --user start xrv-client
```

Stop:

```bash
xrv-client stop
# or
systemctl --user stop xrv-client
```

### Updating

- **Android:** install the new APK over the existing one. If Android refuses
  because of a signing change, uninstall first.
- **Linux:** `sudo dpkg -i XRV-Client-linux-<arch>.deb`.

### Removing

Android: uninstall the app.

Linux:

```bash
systemctl --user disable --now xrv-client
sudo dpkg -r xrv-client
rm -rf ~/.config/xrv ~/.local/state/xrv
```

---

## 9. Troubleshooting

### No traffic on Android

1. Open **Settings → Test tunnel**. Read the result.
2. Open **Settings → View logs**. Look for the last `[carrier]` or `[fronting]`
   line.
3. `HTTP 404`: the Apps Script deployment is not live or is not set to
   **Anyone**. Redeploy it and copy the new deployment ID.
4. `HTTP 403`: the deployment is not shared publicly, or a Google account
   quota is exhausted.
5. `HTTP 429`: too many requests. Wait, add another deployment, or lower
   **Concurrent idle polls** in Settings.
6. `certificate` or `TLS`: the device clock is wrong, or the network blocks the
   Google edge. Try **Find fastest Google edge**, then reconnect.
7. If another VPN is active, use Proxy-only mode or turn the other VPN off.

### “Another VPN is active”

Android permits only one VPN. XRV explains the conflict. Choose **Use TUN
anyway** to replace the other VPN, or **Use proxy mode instead** to keep it.

### First connection takes longer

If no Google edge is saved, XRV tests the candidates first. This can take about
six seconds. Later connections reuse the saved edge.

### Proxy imports as “none”

Copy the link from the share card. It ends in `#XRV`, and the clipboard label is
XRV. If you type the address by hand, add `#XRV` at the end.

### My proxy port is busy

XRV automatically chooses the next free port. The status card and the copied
link show the real port.

### Huawei phone stops the tunnel

Open **Settings → Battery settings** and exclude XRV from battery
optimization. Also allow XRV in Huawei's **Protected apps** or startup manager.

### Linux `xrv-client test` says “not listening”

Start the client first:

```bash
xrv-client run
# or
systemctl --user start xrv-client
```

### Linux service keeps restarting

Run:

```bash
xrv-client setup
systemctl --user restart xrv-client
journalctl --user -u xrv-client -n 50 --no-pager
```

The service needs a valid configuration in `~/.config/xrv/client.json`.

### The exit IP equals the direct IP

The tunnel is not carrying traffic. Run the edge test, check the logs, and
confirm the deployment ID and tunnel key match the server.

### The server check fails

On the VPS:

```bash
sudo bash xrv-install.sh --check
sudo systemctl status xrv-relay xrv-haproxy --no-pager
sudo journalctl -u xrv-relay -n 50 --no-pager
sudo journalctl -u xrv-haproxy -n 50 --no-pager
```

### Learn more

- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)
- [`docs/USER-GUIDE.md`](docs/USER-GUIDE.md)
- [`SECURITY.md`](SECURITY.md)
- [`SUPPORT.md`](SUPPORT.md)

---

## 10. Security rules

1. Never share the tunnel key.
2. Use a server you control and trust.
3. Keep the server updated:
   ```bash
   sudo apt update && sudo apt upgrade
   ```
4. Do not install a “root certificate” that someone else gave you.
5. Download only from this repository's releases.
6. Verify the checksum:
   ```bash
   sha256sum -c XRV-Client-linux-SHA256SUMS.txt
   ```
7. On Android, verify the APK checksum before installing if you downloaded it
   somewhere other than the release page.
8. Remember that the server can see traffic after it decrypts it. XRV protects
   the path; it does not blind the exit.

---

## 11. Verifying the release

Every release includes checksum files. For example:

```bash
sha256sum XRV-Client-Android-arm64.apk
```

Compare the output with `XRV-Client-Android-SHA256SUMS.txt`.

The Android APK is signed with the XRV release key. The Linux packages are
standard Debian packages with a documented MIT license and source link.

The GitHub Actions pipelines build, test, lint, package, and verify every
artifact. The Android pipeline also checks:

- No absolute build-directory paths in native libraries.
- 16 KB memory-page alignment.
- The correct ABIs.
- A valid APK signature.

---

## 12. One-page summary

1. Rent a small Ubuntu VPS.
2. Point a domain at it.
3. Run `sudo bash xrv-install.sh` and choose server install.
4. Create the Apps Script deployment with `Code.gs`.
5. Copy the deployment ID and `/etc/xrv/tunnel_key`.
6. Install the Android APK or the Linux `.deb`.
7. Paste the deployment ID and key.
8. Connect in TUN mode (Android) or start the local proxy (Linux).
9. Tap **Test tunnel** or run `xrv-client test`.
10. Keep the tunnel key private.

That is the whole project. Everything else is explanation and troubleshooting.

---

## 13. License and source

XRV is MIT-licensed open source. The full source, build scripts, tests, and
release pipelines are in
<https://github.com/jackh0006/XRV-Installer>.

The Android client vendors the GooseRelayVPN engine under its MIT license.
The TUN mode uses hev-socks5-tunnel under its MIT license. See
[`LICENSE`](LICENSE) and [`android/OPEN_SOURCE.md`](android/OPEN_SOURCE.md).
