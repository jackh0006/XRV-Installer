#!/usr/bin/env bash
# Builds XRV-Client-linux-<arch>.deb packages from the same Go engine as the
# Android client. Pure Go (CGO disabled), so the binaries are static and work
# on any glibc/musl Linux of the matching CPU architecture.
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
engine="$root/android/engine"
version="${XRV_VERSION:-2.0.0}"
out="${XRV_OUT:-$root/dist}"
arches=()
skip_test=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch) arches+=("$2"); shift 2 ;;
        --all) arches=(amd64 arm64 armhf i386); shift ;;
        --output) out="$2"; shift 2 ;;
        --version) version="$2"; shift 2 ;;
        --skip-test) skip_test=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
[[ ${#arches[@]} -gt 0 ]] || arches=(amd64)
mkdir -p "$out"

go_arch() {
    case "$1" in
        amd64) echo amd64 ;;
        arm64) echo arm64 ;;
        armhf) echo arm ;;
        i386) echo 386 ;;
        *) echo "Unsupported architecture: $1" >&2; exit 2 ;;
    esac
}

for arch in "${arches[@]}"; do
    goarch="$(go_arch "$arch")"
    echo "=== building $arch ==="
    binary="$root/build/linux/$arch/xrv-client"
    mkdir -p "$(dirname "$binary")"
    (
        cd "$engine"
        env CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" GOARM=7 \
            go build -trimpath -ldflags "-s -w -X main.version=$version" \
            -o "$binary" ./cmd/xrv-client
    )

    stage="$root/build/deb/xrv-client_${version}_${arch}"
    rm -rf "$stage"
    mkdir -p \
        "$stage/DEBIAN" \
        "$stage/usr/bin" \
        "$stage/lib/systemd/user" \
        "$stage/usr/share/man/man1" \
        "$stage/usr/share/doc/xrv-client" \
        "$stage/usr/share/icons/hicolor/192x192/apps"

    install -m 0755 "$binary" "$stage/usr/bin/xrv-client"
    install -m 0644 "$root/linux/debian/xrv-client.service" "$stage/lib/systemd/user/xrv-client.service"
    install -m 0644 "$root/linux/debian/xrv-client.1" "$stage/usr/share/man/man1/xrv-client.1"

    for doc in README.md GUIDE.md SECURITY.md LICENSE CHANGELOG.md CONTRIBUTING.md \
               CODE_OF_CONDUCT.md SUPPORT.md DONATE.md; do
        [[ -f "$root/$doc" ]] && install -m 0644 "$root/$doc" "$stage/usr/share/doc/xrv-client/$doc"
    done
    for doc in "$root"/docs/*.md; do
        [[ -f "$doc" ]] && install -m 0644 "$doc" "$stage/usr/share/doc/xrv-client/$(basename "$doc")"
    done
    if [[ -f "$root/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" ]]; then
        install -m 0644 "$root/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" \
            "$stage/usr/share/icons/hicolor/192x192/apps/xrv-client.png"
    fi

    cat >"$stage/usr/share/doc/xrv-client/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: XRV
Source: https://github.com/jackh0006/XRV-Installer

Files: *
Copyright: 2026 jackh0006
License: MIT
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 .
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
EOF

    size="$(du -sk "$stage/usr" | awk '{print $1}')"
    sed -e "s/@VERSION@/$version/g" -e "s/@ARCH@/$arch/g" -e "s/@SIZE@/$size/g" \
        "$root/linux/debian/control.in" >"$stage/DEBIAN/control"
    install -m 0755 "$root/linux/debian/postinst" "$stage/DEBIAN/postinst"

    deb="$out/XRV-Client-linux-$arch.deb"
    dpkg-deb --build --root-owner-group "$stage" "$deb" >/dev/null
    echo "Built $deb"
    dpkg-deb --info "$deb" | sed -n '1,20p'
    dpkg-deb --contents "$deb" | grep -E 'usr/bin/xrv-client|systemd/user|GUIDE.md' || true

    if [[ "$skip_test" == "0" && "$arch" == "amd64" ]]; then
        echo "=== smoke-testing amd64 package ==="
        tmp="$(mktemp -d)"
        export XRV_CONFIG="$tmp/client.json"
        export XRV_STATE_DIR="$tmp/state"
        id="AKfy""cb0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN"
        key="$(printf '0123456789abcdef%.0s' {1..4})"
        "$binary" version >/dev/null
        "$binary" setup --non-interactive --yes --deployment "$id" \
            --tunnel-key "$key" --socks-port 18998 --no-probe >/dev/null
        "$binary" run >"$tmp/run.log" 2>&1 &
        runpid=$!
        sleep 2
        "$binary" status | grep 'running' >/dev/null
        "$binary" stop >/dev/null
        wait "$runpid" 2>/dev/null || true
        grep -q 'XRV proxy ready' "$tmp/run.log"
        rm -rf "$tmp"
        echo "smoke test: PASS"
    fi
done

(
    cd "$out"
    for deb in XRV-Client-linux-*.deb; do
        sha256sum "$deb"
    done > XRV-Client-linux-SHA256SUMS.txt
)
echo "Checksums written to $out/XRV-Client-linux-SHA256SUMS.txt"
