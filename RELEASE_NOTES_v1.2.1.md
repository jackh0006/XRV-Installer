# XRV v1.2.1 — safe ACME coexistence

This release makes certificate handling safe around an existing web server,
HAProxy installation, or tunnel that owns TCP port 80.

- A certificate that is valid for at least 30 days is reused without touching
  port 80.
- If a fresh HTTP-01 certificate is required, pass an exact systemd unit with
  `--acme-stop-service hedioum.service`. XRV validates it, pauses it only for
  the ACME check, restores it immediately, and saves the same renewal hooks.
- A conflicting public port now stops the installer before it changes UFW,
  packages, files, or services.

```bash
sudo bash xrv-install.sh --server --non-interactive --yes \\
  --domain vpn.example.com --email admin@example.com \\
  --public-port 10443 --backend-port 9443 \\
  --acme-stop-service hedioum.service
```

The private backend remains loopback-only. XRV continues to use its own
`xrv-haproxy` service and never edits an existing HAProxy configuration.
