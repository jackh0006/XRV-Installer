# Support

## Where to ask

- **Reproducible bug or documentation gap:** open an
  [issue](https://github.com/jackh0006/XRV-Installer/issues/new/choose).
- **Security vulnerability:** use the private advisory form:
  <https://github.com/jackh0006/XRV-Installer/security/advisories/new>.
  Do not open a public issue for a vulnerability.
- **Donations:** optional, see [DONATE.md](DONATE.md).

## Before opening an issue

1. Use the latest release or state the exact commit.
2. Run the built-in doctor:

   ```bash
   sudo bash xrv-install.sh --check --json
   bash xrv-client.sh --check
   ```

3. Collect the redacted logs:

   ```bash
   sudo tail -n 100 /var/log/xrv/install.log
   sudo journalctl -u xrv-relay -n 50 --no-pager
   sudo journalctl -u xrv-haproxy -n 50 --no-pager
   tail -n 50 ~/xrv/xrv-client.log
   ```

4. Remove secrets and private data. **Never** attach:

   - `client_config.json` or `server_config.json`
   - `/etc/xrv/tunnel_key` or the 64-character tunnel key
   - private keys, recovery phrases, Apps Script editor links
   - public IPs, domains, or email addresses you want to keep private

## What to include

- XRV version or commit.
- Server OS and CPU architecture, or client platform (Ubuntu amd64, Termux
  arm64, Linux arm64).
- Exact commands and the smallest reproduction.
- The exact error text, with secrets redacted.
- Whether the tunnel works without TLS (HTTP mode) to isolate certificate
  problems.
- Output of `haproxy -c -f /etc/haproxy/xrv.cfg` on the server, if relevant.

## Scope

Maintainers support the scripts in this repository and the pinned upstream
release they install. We cannot debug:

- a modified script or config;
- a fork of the upstream GooseRelayVPN binary;
- a compromised VPS, Google account, or client device;
- Apps Script quota limits or Google account suspensions;
- third-party VPN apps on Android.

## Response expectations

This is a volunteer project. Security reports are prioritised. There is no
paid support tier and no guaranteed response time. A donation does not create a
support entitlement.

## Community standards

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
