# XRV v1.1.1 — GitHub standards, donations, and Pages fix

v1.1.1 does not change the tunnel protocol. It makes the repository match
GitHub's community standards, adds the author's public donation addresses, and
fixes the failing documentation deployment.

## Downloads

| File | Platform |
|------|----------|
| `xrv-install.sh` | Server manager: Ubuntu/Debian amd64 or arm64 VPS |
| `xrv-client.sh` | Client: Linux amd64/arm64 and Android Termux arm64 |
| `SHA256SUMS.txt` | Checksums for every attached file |

```bash
sha256sum -c SHA256SUMS.txt
```

## Added

- `DONATE.md` with every public crypto address copied from the author's
  `BNB-Terminal-Wallet` and `X-Wallet` repositories.
- `.github/FUNDING.yml`, `.github/CODEOWNERS`, issue forms, and a pull request
  template.
- `CITATION.cff` for GitHub's **Cite this repository** button.
- README badges for CI, release, license, platforms, security policy and PRs.
- A standard `SUPPORT.md` with the exact information a useful report needs.
- Pinned every GitHub Action to a commit SHA.

## Changed

- v1.1.0 was merged onto `main`, keeping the standard community files already
  present there.
- CI runs syntax checks, warning-level ShellCheck, the full test suite, and both
  `--help` screens.
- The release workflow attaches both installers, checksums, documentation and
  release notes.
- `main` is the single default branch. The old `master` branch is removed.

## Safety: existing HAProxy configuration

v1.1 uses a **dedicated** `/etc/haproxy/xrv.cfg` and `xrv-haproxy.service`.
It never rewrites your existing `/etc/haproxy/haproxy.cfg`.

If you installed v1.0, that older version put a marked block into the distro
config. v1.1 removes **only that exact marked block**:

- a timestamped backup is made first;
- every unrelated line is kept;
- the file's owner and mode are preserved;
- the result is checked with `haproxy -c`;
- if the check fails, the backup is restored automatically.

If the block is incomplete or ambiguous, the installer refuses to edit the
file. If another program owns the tunnel port, the installer reports the exact
process instead of stopping or reconfiguring it.

## Fixed

- **Build Documentation** failed with:

  ```
  Error: Creating Pages deployment failed
  HttpError: Not Found
  Ensure GitHub Pages has been enabled
  ```

  GitHub Pages was not enabled for the repository. It is now enabled with the
  workflow build type, and the workflow uses pinned `configure-pages`,
  `upload-pages-artifact`, and `deploy-pages` actions.

## Verification

- `bash -n` on every shell file.
- ShellCheck warning-level clean.
- Full unit and integration suite, including the offline client install,
  generated server config, generated HAProxy config, and release checksums.
- Server install exercised end-to-end in an isolated Linux sandbox for both
  HTTP-only and TLS-front modes.
- Client v1.7.1 downloaded, checksum-verified, started and stopped on Linux
  amd64; Termux arm64 archive and architecture verified.
- Documentation workflow re-run against the updated `main` after enabling
  Pages.

## Upgrade

No config or key migration is required from v1.1.0.

```bash
sudo bash xrv-install.sh --update
bash xrv-client.sh --update
```
