# XRV Android client (arm64)

This directory is the complete source for the XRV Android app: a modern,
encrypted relay client with two connection modes.

| Mode | What it does | Best for |
| --- | --- | --- |
| **TUN · system-wide** | Creates an Android `VpnService` interface and forwards every app's TCP traffic through the encrypted relay. DNS is handled by the exit (no local DNS leak). | Normal phone use. One tap protects everything. |
| **Proxy only** | Runs an authenticated SOCKS5 listener on `127.0.0.1` and creates no VPN interface. | Apps that accept a proxy, such as v2rayNG, or when another VPN must stay connected. |

The app has no analytics, ads, telemetry or remote configuration. The only
network endpoint is the Apps Script deployment ID entered by the owner.

## Settings and diagnostics

The gear button opens a settings screen that matches the Linux client's useful
options:

- **Per-app proxy (TUN only)** — all apps, only selected apps, or all except
  selected apps. The picker lists installed apps and the VPN is rebuilt with
  Android's allow/deny lists on the next connection. XRV always excludes
  itself so its relay traffic cannot loop through its own tunnel.
- **Google edge** — the carrier receives the selected edge as `host:443`
  (the Linux config layer does the same; a bare IP would fail every dial).
  The same four Google entry points as `xrv-client.sh`
  (`216.239.32.120`, `216.239.34.120`, `216.239.36.120`, `216.239.38.120`).
  **Find fastest** performs a real HTTPS `generate_204` request to each
  candidate, shows latency, and stores the fastest. Add or remove IPv4
  candidates in the text field. **Use automatic edge** restores the default.
- **Performance** — uplink batching (default 25 ms) and 1–3 concurrent idle
  polls. The idle default scales from 1 to 3 with the number of deployments.
- **Test tunnel** — opens a real request to `https://api.ipify.org` through
  the authenticated local SOCKS5 listener, shows the exit IP and latency, and
  compares it with the phone's direct IP. This is the same live check as
  `xrv-client.sh --check`.
- **Logs** — an in-app viewer for app events and native carrier output. Keys,
  deployment IDs and proxy credentials are redacted, app events persist to
  private storage, and the crash handler records the final stack trace.
- **Battery settings** — opens Android's optimisation screen for Huawei/EMUI
  reliability.

The traffic counters in the status card are real SOCKS payload bytes counted
inside the engine, not raw TUN/hev packet bookkeeping. They stay at zero until
an app actually sends traffic.

When the proxy address is copied, the share link ends in `#XRV`, so v2rayNG
imports the profile with the name **XRV** instead of `none`. The link includes
the generated SOCKS username/password and is cleared from the clipboard after
60 seconds.

## Security properties

- Relay frames use AES-256-GCM; the 64-hex tunnel key must match the VPS.
- The deployment IDs and tunnel key are encrypted at rest with a
  non-exportable Android Keystore AES-256-GCM key.
- The tunnel key is never logged, written to a world-readable file, or put in
  an APK resource.
- `usesCleartextTraffic=false` plus a network-security config that trusts only
  system CAs. User-installed MITM CAs are not trusted, and the Go engine is
  restricted to the immutable system trust directory too.
- Backups and device-transfer extraction are disabled for app data.
- The Go engine keeps a bounded in-memory log buffer with keys, deployment
  IDs and proxy credentials redacted. App events persist privately.
- TUN mode excludes the XRV process from its own VPN, preventing a routing
  loop. It never exposes the SOCKS listener beyond loopback.
- The loopback SOCKS5 listener requires a randomly generated RFC 1929
  username/password. The Copy action includes them; TUN mode passes them to
  hev internally.
- `QUERY_ALL_PACKAGES` is used only to populate the local per-app picker. The
  package list never leaves the device.
- The app logs are stored in private app storage with credential/key redaction
  and a bounded size.
- No `QUERY_ALL_PACKAGES`, no accessibility service, no device-admin access.

## Requirements

- Android 6.0 (API 23) or newer, **arm64-v8a**.
- A valid XRV deployment ID (`AKfycb…`) and the matching 64-character
  tunnel key from the XRV installer.
- For TUN mode, Android's VPN consent (shown once).

## Build

Prerequisites: JDK 21, Android SDK 36, NDK `28.2.13676358`, Go 1.27 or newer,
and `git` with submodules.

```bash
git submodule update --init --recursive
cd android
export ANDROID_HOME="$HOME/Android/Sdk"
export GO_BIN="$(command -v go)"
./gradlew test lint assembleRelease
bash scripts/verify-apk.sh app/build/outputs/apk/release/app-release.apk
cp app/build/outputs/apk/release/app-release.apk XRV-arm64.apk
```

`scripts/build-android-engine.sh` compiles both native libraries from source:

1. `libxrvbridge.so` — the vendored Go relay engine **and** its JNI entry
   points in one library. The first published client linked a second JNI shim
   by an absolute build path, which crashed on a real device; the single
   library and the verification script prevent that regression.
2. `libhev-socks5-tunnel.so` — [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel)
   (MIT), pinned as a submodule and driven through its documented
   `hev.htproxy.TProxyService` JNI class.

The default build produces splits for `arm64-v8a`, `armeabi-v7a`, `x86`, and
`x86_64`, plus a universal APK. To build only one ABI for a quick test, use:

```bash
./gradlew assembleRelease -PxrvAbis=arm64-v8a
```

### Release signing

`assembleRelease` uses, in order:

1. the environment variables `XRV_KEYSTORE`, `XRV_KEYSTORE_PASSWORD`,
   `XRV_KEY_ALIAS`, `XRV_KEY_PASSWORD`;
2. `android/xrv-release.jks` if it exists;
3. the debug key as a fallback, so CI artifacts remain installable.

Keep the release keystore and its password offline. Losing it means future
builds cannot update an installed app in place.

## Verification

`scripts/verify-apk.sh` fails the build if:

- any native library records a build-directory path in `DT_NEEDED`;
- any `LOAD` segment is not aligned for 16 KB-page devices;
- either engine library is missing from `lib/arm64-v8a`;
- the APK signature does not verify.

The app's unit tests cover configuration validation, port selection, formatting
and JSON round-tripping. CI runs `test`, `lint`, `assembleRelease` and the APK
verifier on every Android change.

## Using TUN mode

1. Paste the deployment ID(s), tunnel key and preferred local port.
2. Keep **TUN · system-wide** selected.
3. Tap **Connect** and accept Android's VPN prompt.

Android permits only one active VPN. If another VPN is connected, XRV explains
this before taking over. Starting XRV in TUN mode replaces the other VPN; use
Proxy-only mode if the other VPN must remain active.

On Huawei/EMUI and other battery-optimised phones, open **Battery settings**
in the app and exclude XRV from optimisation. Otherwise Android may suspend
the foreground service.

## Using proxy-only mode

1. Select **Proxy only** and connect.
2. The status card shows `socks5://127.0.0.1:PORT` and the share card shows the
   generated username/password. The Copy action includes them in the URL.
3. In v2rayNG or another proxy client, paste the copied link (it is named
   XRV) or add a **SOCKS5** server with host `127.0.0.1`, the displayed port,
   and those credentials. Use the SOCKS5 hostname form so DNS is resolved by
   the exit.

Do not route another VPN app's outbound through this local proxy while that
same VPN is active: the engine's own HTTPS traffic would then go back through
that VPN. Use TUN mode for system-wide protection. XRV warns about this in the
About screen.

## Known limits

- The relay protocol carries TCP. UDP is not supported end to end, so
  UDP-only/QUIC traffic falls back to TCP or fails; DNS still works because
  mapdns resolves names over the tunnel. This is a protocol limit, not a UI
  setting.
- Android's Private DNS hostname resolution is controlled by the OS; XRV
  supplies its own DNS server and does not read or log query contents.
- The link between the phone and Google is HTTPS; the relay payload has its own
  AES-256-GCM layer to the VPS. XRV does not claim to be a Tor-style anonymity
  network.
- A rooted device can inspect its own process memory. No Android app can
  prevent that.
