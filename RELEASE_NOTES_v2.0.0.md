# XRV Android 2.0.0

## Fixed

- **Connect crash.** The old JNI shim recorded an absolute build-machine path
  in `DT_NEEDED`, so loading it on the phone terminated the process. The JNI
  entry points now live inside the engine library, and CI verifies every
  packaged `.so` for absolute dependencies and 16 KB page alignment.
- **Disconnect did not close the SOCKS listener.** The engine now cancels its
  context, closes the listener, and releases the port; the service lifecycle
  was rebuilt around one synchronized engine owner.
- **Missing app icon.** Added a vector XRV shield mark, adaptive icon,
  monochrome icon, round icon, legacy PNGs and a notification icon.
- **Unusable UI.** Replaced the bare form with a Material 3 interface: live
  status card, animated state indicator, traffic/time counters, mode selector,
  inline validation, encrypted-profile summary, copyable proxy address,
  details dialog, dark/light themes, and a proper About screen.
- **No TUN mode.** Added a real `VpnService` backed by a source-built
  hev-socks5-tunnel. XRV excludes itself from the tunnel, supplies a mapped DNS
  server, and supports IPv4 plus leak-blocking IPv6 routes.
- **Already-connected VPN confusion.** XRV detects an active VPN, explains that
  Android permits one VPN at a time, offers to take over in TUN mode, and
  offers Proxy-only mode as the coexist option.
- **Android 14/15/16 foreground-service problems.** Uses the `specialUse`
  foreground-service type with a documented subtype, declares the matching
  permission, and avoids the dataSync six-hour timeout.
- **Service races.** Starting one mode waits for the other service to release
  the engine; stale RUNNING state after a process kill is cleared; watchdog
  detects an unexpectedly stopped tunnel.
- **Security hardening.** No cleartext traffic, no user-installed CAs, no
  backups/device-transfer of credentials, no Go logging of relay identifiers,
  a randomly authenticated loopback proxy, and a minified release with JNI
  keep rules.
- **Port conflicts.** If the chosen local port is busy, XRV picks the next free
  port and displays the real one.
- **CI was building a debug APK and could trip its own secret scan.** CI now
  builds `assembleRelease`, runs tests/lint, verifies the APK, and the tests no
  longer contain literal credential-shaped strings.

## Settings and diagnostics update (2026-11-18)

- **Per-app proxy** for TUN mode: all apps, only selected apps, or all except
  selected apps, with a searchable installed-app picker.
- **Google edge testing and custom IPs**: probes the same four Google entry
  points as `xrv-client.sh` with a real HTTPS `generate_204` request, shows
  latency, and stores the fastest edge. Add or remove IPv4 candidates.
- **Real traffic counters**: the status card and notification now count actual
  SOCKS payload bytes from the engine, not raw TUN/hev packet bookkeeping.
- **Live tunnel test**: fetches `https://api.ipify.org` through the
  authenticated SOCKS listener, shows the exit IP/latency, and compares it
  with the phone's direct IP.
- **In-app logs**: app events and native carrier logs with keys, deployment
  IDs and proxy credentials redacted; app events persist privately; crashes
  are recorded with a stack trace.
- **Performance settings**: uplink batching (default 25 ms, matching the Linux
  client) and 1–3 idle polls, scaling from 1 to 3 with deployment count.
- **XRV profile name**: copied proxy links end in `#XRV`, so v2rayNG imports
  the profile as **XRV**, not `none`.
- `QUERY_ALL_PACKAGES` is used only for the local per-app picker; nothing is
  uploaded.

## Modes

- **TUN · system-wide** — Android VPN, all app traffic, mapped DNS.
- **Proxy only** — loopback SOCKS5 with per-install RFC 1929 credentials for
  v2rayNG and other proxy-aware apps; no VPN interface, so it can coexist
  with another active VPN.

## Important upgrade note

The previous 1.2.x APK was debug-signed by CI with an unrecoverable key. This
release uses a dedicated 4096-bit release key, so Android will refuse to
install it over 1.2.x. Uninstall the old app, then install 2.0.0. Your
configuration is not backed up to the cloud by design; re-enter the deployment
ID and tunnel key once.

## Known limit

The relay carries TCP. UDP/QUIC is not supported end to end, so apps that use
QUIC fall back to TCP or lose that specific flow. DNS resolution works through
the tunnel's mapped DNS server. This is a protocol limit and is documented in
`android/OPEN_SOURCE.md`.

## Verification

```bash
sha256sum XRV-arm64.apk
# see XRV-arm64.apk.sha256 for the published asset hash
bash android/scripts/verify-apk.sh XRV-arm64.apk
```
