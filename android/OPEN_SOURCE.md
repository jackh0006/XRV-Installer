# XRV Android source and verification

This directory is the complete source for the XRV Android SOCKS5 client. It
vendors the protocol implementation from [GooseRelayVPN](https://github.com/Kianmhz/GooseRelayVPN), under its MIT license; see `engine/` and the repository-root `LICENSE`.

The client has no analytics, ads, remote configuration, or network endpoint
other than the Apps Script deployment IDs explicitly entered by its owner.
Credentials are encrypted at rest with an Android Keystore AES-GCM key and are
never placed in logs or an APK resource.

Build an arm64 release APK:

```bash
cd android
./gradlew assembleRelease
cp app/build/outputs/apk/release/app-release.apk XRV-arm64.apk
```

`scripts/build-android-engine.sh` compiles the vendored Go source locally with
the Android NDK. The release build only targets `arm64-v8a`, deliberately: an
APK must never claim ABI support it has not built and tested.

Verification:

```bash
cd android
./gradlew lint test assembleRelease
sha256sum app/build/outputs/apk/release/app-release.apk
```

Before publishing, install the exact artifact on a physical arm64 Android 6.0+
device and use a unique disposable tunnel key to prove a SOCKS5 connection.
Do not treat an APK as "proven" merely because it compiles.

## Using the local proxy

After XRV reports connected, it listens only on `127.0.0.1:1080` by default.
In another Android application such as v2rayNG, choose an upstream SOCKS5 proxy
and set its host to `127.0.0.1` and its port to the port configured in XRV.
XRV intentionally never exposes this proxy to Wi-Fi or mobile-network peers.
