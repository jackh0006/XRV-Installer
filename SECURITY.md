# Security policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.1.x   | yes       |
| 1.0.x   | no — upgrade to 1.1.x |

## Reporting a vulnerability

Please do **not** open a public issue for a vulnerability that could expose
users. Use GitHub's private security advisory:

<https://github.com/jackh0006/XRV-Installer/security/advisories/new>

Include:

- the version and platform;
- the exact command or configuration;
- what you observed and what you expected;
- whether a tunnel key, certificate, or server was exposed.

You will get an acknowledgement as soon as possible. Please allow time for a
fix before publishing details.

## What XRV protects

- **Payload confidentiality and integrity:** AES-256-GCM end to end between
  the client and your VPS. Google Apps Script forwards bytes it cannot read.
- **Traffic shape:** the client talks TLS to a Google edge with a Google SNI.
- **Server transport:** TLS 1.3 only on the public relay port, with a trusted
  Let's Encrypt certificate.
- **Local exposure:** the SOCKS5 listener is bound to `127.0.0.1` by default.
- **Privileges:** the relay and TLS front run as unprivileged service users
  inside systemd sandboxes.
- **Supply chain:** the upstream release is pinned and checksum-verified before
  it is installed.
- **Secrets:** the tunnel key is validated, stored mode 600, and redacted from
  logs. It is never printed by the installer.

## What XRV does not protect

- **Google sees metadata:** connection times, byte counts, and that you use a
  Google Apps Script deployment. It does not see plaintext or the key.
- **Your VPS provider sees exit traffic**, including destination addresses.
- **A stolen tunnel key** gives full access to the relay. Rotate it immediately:
  `sudo bash xrv-install.sh --rotate-key`, then update every client.
- **A compromised VPS or client** defeats the tunnel.
- **Anonymity:** this is not Tor. Your Google account, Apps Script deployment,
  VPS account, and payment methods can be linked.
- **Daily quota:** Apps Script quotas apply per Google account. Heavy use can
  exhaust them; the client rotates and backs off, but cannot create quota.

## Operational guidance

1. Keep the VPS patched. `unattended-upgrades` is your friend.
2. Use SSH keys, not passwords. Do not expose SSH to the whole internet if you
   can restrict it to your own addresses.
3. Leave UFW enabled. The installer opens only SSH, port 80 for ACME, and the
   tunnel port.
4. Do not reuse the tunnel key anywhere else.
5. Keep `client_config.json` out of backups, chats, screenshots and Git.
6. Run `sudo bash xrv-install.sh --check` after any network or DNS change.
7. If a certificate is compromised, use the certificate manager's
   **Revoke and delete** option and issue a new one.
8. Review `/var/log/xrv/install.log` and the journal after upgrades. Secrets are
   redacted, but operational details remain.

## Hardening details

- HAProxy exposes only `path_beg /tunnel` and `path /healthz`; everything else
  is answered with 404.
- TLS 1.3 only: `ssl-min-ver TLSv1.3`, TLS 1.3 cipher suites, no tickets.
- systemd: `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`,
  `PrivateTmp`, `PrivateDevices`, `RestrictAddressFamilies`,
  `CapabilityBoundingSet=` (relay) or only `CAP_NET_BIND_SERVICE` (TLS front).
- The relay binds `127.0.0.1:9443`; only HAProxy is public.
- Archive extraction rejects absolute paths, traversal and links.
- Downloads are HTTPS-only (`--proto '=https'`), retried, and pinned by SHA-256.

## Dependency and release integrity

The installer executes only:

- standard Ubuntu/Debian packages installed through `apt`;
- the pinned GooseRelayVPN v1.7.1 archive, after SHA-256 verification;
- scripts and configuration it generates itself.

`xrv-install.sh` contains a pinned SHA-256 for `xrv-client.sh` when it downloads
the client script from this repository. If you modify the client script, update
that value in the same release.
