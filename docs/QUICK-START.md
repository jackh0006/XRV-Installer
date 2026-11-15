# XRV Quick Start

Follow the four boxes in this order. Every command is safe to copy exactly.

> Keep the 64-character tunnel key private. It is a password for your tunnel.

## Box 1 — point a domain at your VPS

At your domain provider, add an **A** record:

```text
vpn.example.com  →  YOUR_VPS_IP
```

Open TCP `80` and one public tunnel port in your cloud firewall. If you are
not sure which tunnel port to use, let XRV offer a free one.

## Box 2 — install the server

SSH into the VPS, then run these commands one at a time:

```bash
curl -fsSLO https://raw.githubusercontent.com/jackh0006/XRV-Installer/main/xrv-install.sh
sudo bash xrv-install.sh
```

Choose **Install or update the server**. Enter your domain and email, then
follow the on-screen questions. When it finishes, it must say the public TLS
endpoint is healthy.

Save these private values for the client:

```bash
sudo cat /etc/xrv/tunnel_key
sudo cat /etc/xrv/Code.gs
```

If XRV says TCP 80 belongs to another service, do not stop random services.
Give XRV the exact known systemd unit only when a new certificate is required:

```bash
sudo bash xrv-install.sh --server --acme-stop-service hedioum.service
```

## Box 3 — make the Google forwarder

1. Go to <https://script.google.com> and create a **New project**.
2. Delete the sample code.
3. Paste all of the private `Code.gs` text from Box 2.
4. Choose **Deploy** → **New deployment** → **Web app**.
5. Copy the deployment URL or its `AKfycb...` ID.

## Box 4 — install the client

On your Linux computer or Android Termux, run:

```bash
curl -fsSLO https://raw.githubusercontent.com/jackh0006/XRV-Installer/main/xrv-client.sh
bash xrv-client.sh
```

Enter the VPS domain. XRV checks familiar public HTTPS ports and then asks you
to confirm the correct one. Paste the `AKfycb...` deployment ID and the tunnel
key. Keep the default local SOCKS5 address: `127.0.0.1:1080`.

## Finished

Set your browser or app to SOCKS5 `127.0.0.1`, port `1080`, then verify:

```bash
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

It should show your VPS IP. If it does not, run:

```bash
bash xrv-client.sh --check
```
