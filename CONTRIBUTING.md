# Contributing to XRV Installer

Thanks for helping. This project installs networking software as root, so
changes are reviewed for safety first and features second.

## Before you send a change

```bash
bash -n xrv-install.sh xrv-client.sh
shellcheck -S warning -x xrv-install.sh xrv-client.sh tests/*.sh
bash tests/run-all.sh
```

`tests/run-all.sh` also runs:

- an offline client install into a temporary home;
- the generated server config through JSON validation;
- the generated HAProxy config through `haproxy -c` when HAProxy is installed;
- the pinned release checksums against the upstream GitHub API.

## Rules

1. **Never log secrets.** The tunnel key and deployment IDs must stay out of
   logs. `tests/test-client-install.sh` checks this for the client.
2. **Never bypass TLS verification.** No `curl -k`, no
   `--no-check-certificate`, no `InsecureSkipVerify`.
3. **Pin downloads.** Any remote archive must have a SHA-256 checked before it
   is extracted or executed. If you bump the release, update the digest in both
   scripts and the tests.
4. **Explain failures.** A user should see what failed, why, and the exact
   command that fixes it. Do not print a raw stack trace as the only message.
5. **Keep the client standalone.** `xrv-client.sh` must work when downloaded
   and executed by itself, including in Termux.
6. **Do not touch unrelated files.** HAProxy changes belong in
   `/etc/haproxy/xrv.cfg`, never in a distro config with other sites.
7. **Keep systemd sandboxes.** Do not add `ProtectSystem=no` or extra
   capabilities to make a bug disappear.
8. **No new runtime dependencies without a fallback.** Linux and Termux differ.

## Testing a server change

Use a disposable VPS. At minimum:

```bash
sudo bash xrv-install.sh --check
sudo systemctl status xrv-relay xrv-haproxy --no-pager
curl -v https://your-domain:8443/healthz
sudo bash xrv-install.sh --cert   # dry run
```

Complete [LIVE_TEST_CHECKLIST.md](LIVE_TEST_CHECKLIST.md) before a release.

## Testing a client change

```bash
bash xrv-client.sh --check
~/xrv/start-xrv.sh
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

Test on Ubuntu amd64 and, if the change touches platform code, Termux arm64.

## Commit messages

Use a short imperative subject line, then explain the reason. Example:

```
client: reject busy SOCKS port in non-interactive mode

Leaving the port busy produced a confusing runtime failure. The installer now
stops and suggests --socks-port instead.
```

## Release process

1. Update `XRV_VERSION`, `CHANGELOG.md`, and the `xrv-client.sh` SHA-256 in
   `xrv-install.sh`.
2. Run the full suite.
3. Commit.
4. Tag `vX.Y.Z`.
5. Push the tag. The release workflow attaches the scripts, docs, and
   `SHA256SUMS.txt`.

## Reporting security issues

See [SECURITY.md](SECURITY.md). Do not open a public issue for a vulnerability.
