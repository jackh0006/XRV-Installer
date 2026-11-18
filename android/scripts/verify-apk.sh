#!/usr/bin/env bash
# Verifies the exact APK that will be installed. The absolute-DT_NEEDED check
# exists because that defect made the first published client crash on launch.
set -Eeuo pipefail

apk="${1:-app/build/outputs/apk/release/app-release.apk}"
[[ -f "$apk" ]] || { echo "APK not found: $apk" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

unzip -q "$apk" 'lib/*' -d "$tmp"

ndk="${ANDROID_NDK_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/ndk/28.2.13676358}"
readelf_bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
[[ -x "$readelf_bin" ]] || readelf_bin="$(command -v readelf || true)"
[[ -n "$readelf_bin" ]] || { echo "No readelf tool available" >&2; exit 1; }

libs=("$tmp"/lib/*/*.so)
[[ ${#libs[@]} -gt 0 && -f "${libs[0]}" ]] || { echo "APK contains no native libraries" >&2; exit 1; }

for so in "${libs[@]}"; do
    echo "Checking $(basename "$so")"
    if "$readelf_bin" -dW "$so" | grep -E 'NEEDED.*[/\\]' >/dev/null; then
        echo "FAIL: $(basename "$so") records a build-directory path in DT_NEEDED" >&2
        "$readelf_bin" -dW "$so" | grep NEEDED >&2
        exit 1
    fi
    while read -r align; do
        case "$align" in
            0x4000|0x10000|0x20000) ;;
            *) echo "FAIL: $(basename "$so") has LOAD alignment $align (<16 KB)" >&2; exit 1 ;;
        esac
    done < <("$readelf_bin" -lW "$so" | awk '$1 == "LOAD" { print $NF }')
done

unzip -Z1 "$apk" | grep -F 'lib/arm64-v8a/libxrvbridge.so' >/dev/null \
    || { echo "FAIL: arm64 engine is missing from the APK" >&2; exit 1; }
unzip -Z1 "$apk" | grep -F 'lib/arm64-v8a/libhev-socks5-tunnel.so' >/dev/null \
    || { echo "FAIL: TUN engine is missing from the APK" >&2; exit 1; }

sdk="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
apksigner_bin="$(find "$sdk/build-tools" -name apksigner -type f 2>/dev/null | sort -V | tail -1 || true)"
if [[ -n "$apksigner_bin" ]]; then
    "$apksigner_bin" verify "$apk" >/dev/null \
        || { echo "FAIL: APK signature verification failed" >&2; exit 1; }
fi

echo "OK: native libraries, 16 KB alignment, ABIs and signature verified."
