#!/usr/bin/env bash
# Builds the XRV protocol engine and tun2socks from source. No downloaded
# executable and no prebuilt library is trusted.
set -Eeuo pipefail

ABI="${1:-arm64-v8a}"
case "$ABI" in
    arm64-v8a)   triple=aarch64-linux-android;      arch=arm64 ;;
    armeabi-v7a) triple=armv7a-linux-androideabi;   arch=arm ;;
    x86_64)      triple=x86_64-linux-android;       arch=amd64 ;;
    *) echo "Unsupported ABI: $ABI" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
ndk="${ANDROID_NDK_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/ndk/28.2.13676358}"
host_tag="linux-x86_64"
[[ -d "$ndk/toolchains/llvm/prebuilt/$host_tag" ]] || host_tag="$(ls "$ndk/toolchains/llvm/prebuilt" | head -1)"
clang="$ndk/toolchains/llvm/prebuilt/$host_tag/bin/${triple}23-clang"
sysroot_include="$ndk/toolchains/llvm/prebuilt/$host_tag/sysroot/usr/include"

[[ -x "$clang" ]] || { echo "Android NDK API 23 compiler not found: $clang" >&2; exit 1; }
[[ -f "$sysroot_include/jni.h" ]] || { echo "Android JNI headers not found: $sysroot_include/jni.h" >&2; exit 1; }

go_bin="${GO_BIN:-go}"
command -v "$go_bin" >/dev/null 2>&1 || { echo "Go toolchain not found: $go_bin" >&2; exit 1; }

out="$root/generated/$ABI"
mkdir -p "$out/include" "$root/build/hev-obj"

# One self-contained library: Go engine + JNI entry points.  A SONAME is
# mandatory so nothing ever records a build-directory path in DT_NEEDED.
(
    cd "$root/engine"
    CGO_ENABLED=1 GOOS=android GOARCH="$arch" CC="$clang" \
        CGO_CFLAGS="-I$sysroot_include" \
        "$go_bin" build -trimpath -buildmode=c-shared \
        -ldflags='-s -w -extldflags=-Wl,-soname,libxrvbridge.so' \
        -o "$out/libxrvbridge.so" ./mobile
)
mv "$out/libxrvbridge.h" "$out/include/libxrvbridge.h"

# tun2socks (hev-socks5-tunnel) is built as a second library and driven by
# XrvVpnService through its documented JNI class hev/htproxy/TProxyService.
# Build it in a scratch directory first: ndk-build clears its output directory
# on every run, which would otherwise delete the Go engine built above.
"$ndk/ndk-build" \
    NDK_PROJECT_PATH="$root/tun2socks" \
    APP_BUILD_SCRIPT="$root/tun2socks/Android.mk" \
    APP_ABI="$ABI" \
    APP_MODULES=hev-socks5-tunnel \
    APP_PLATFORM=android-23 \
    NDK_OUT="$root/build/hev-obj" \
    NDK_LIBS_OUT="$root/build/hev-libs" \
    -j"${XRV_BUILD_JOBS:-4}"
install -m 0644 "$root/build/hev-libs/$ABI/libhev-socks5-tunnel.so" "$out/libhev-socks5-tunnel.so"
