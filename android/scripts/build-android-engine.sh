#!/usr/bin/env bash
# Builds the protocol engine from source; no downloaded executable is trusted.
set -Eeuo pipefail
ABI="${1:-arm64-v8a}"
case "$ABI" in arm64-v8a) triple=aarch64-linux-android; arch=arm64;; armeabi-v7a) triple=armv7a-linux-androideabi; arch=arm;; x86_64) triple=x86_64-linux-android; arch=amd64;; *) echo "Unsupported ABI: $ABI" >&2; exit 2;; esac
root="$(cd "$(dirname "$0")/.." && pwd)"
ndk="${ANDROID_NDK_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/ndk/28.2.13676358}"
clang="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/${triple}23-clang"
[[ -x "$clang" ]] || { echo "Android NDK API 23 compiler not found: $clang" >&2; exit 1; }
out="$root/generated/$ABI"; mkdir -p "$out/include"
(cd "$root/engine" && CGO_ENABLED=1 GOOS=android GOARCH="$arch" CC="$clang" go build -trimpath -buildmode=c-shared -ldflags='-s -w' -o "$out/libxrvbridge.so" ./mobile)
mv "$out/libxrvbridge.h" "$out/include/libxrvbridge.h"
