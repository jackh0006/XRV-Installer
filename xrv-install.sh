#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# XRV v1.1.1 — hardened GooseRelayVPN server installer and manager.
#
# Main server installer for Linux amd64/arm64 VPS.
# Client installer (Ubuntu amd64 + Termux arm64) lives in xrv-client.sh.
#
# Project: https://github.com/Kianmhz/GooseRelayVPN
# Repo:    https://github.com/jackh0006/XRV-Installer
#
# Design goals:
#   * Make every step explain itself in plain language.
#   * Never leave a half-finished, insecure, or silent failure behind.
#   * Prefer the smallest possible attack surface: dedicated service users,
#     TLS 1.3 only, strict systemd sandboxes, pinned release checksums.
#   * Be idempotent: re-running is safe, and updates keep existing keys.

set -Eeuo pipefail
IFS=$'\n\t'
umask 022

# =====================================================================
# VERSION & METADATA
# =====================================================================
XRV_VERSION="1.1.1"
XRV_APP="XRV"
XRV_AUTHOR="jackh0006 <jackh109867@gmail.com>"
XRV_PROJECT="https://github.com/Kianmhz/GooseRelayVPN"
XRV_REPO="jackh0006/XRV-Installer"
XRV_BRANCH="${XRV_BRANCH:-master}"
XRV_RAW_BASE="https://raw.githubusercontent.com/${XRV_REPO}/${XRV_BRANCH}"
CLIENT_SCRIPT_URL="${XRV_CLIENT_SCRIPT_URL:-${XRV_RAW_BASE}/xrv-client.sh}"

# Upstream release is pinned on purpose. Never silently follow "latest":
# a moving target makes the checksum guarantee meaningless.
RELAY_RELEASE="${XRV_RELAY_RELEASE:-v1.7.1}"
RELAY_BASE="https://github.com/Kianmhz/GooseRelayVPN/releases/download/${RELAY_RELEASE}"

# SHA-256 values are copied from the upstream release asset digests.
# They are the only code we execute as root, so they are pinned and checked.
SERVER_SHA256_AMD64="${XRV_SERVER_SHA256_AMD64:-7917f68357bdb745ef058f8c7b01921eeb7ee4079cd8a7040108622cb29eb260}"
SERVER_SHA256_ARM64="${XRV_SERVER_SHA256_ARM64:-36b6aae93555adf86730da433a4a70452c4b213ca3055a1d01f7de04fa3c73eb}"
CLIENT_SCRIPT_SHA256="${XRV_CLIENT_SCRIPT_SHA256:-aa5c4687a809bee26f29fb1035544118065782f598bebe53ccdbe0995bba5908}"

# =====================================================================
# PATHS
# =====================================================================
STATE_DIR="/etc/xrv"
STATE_FILE="${STATE_DIR}/state.conf"
SERVER_CONFIG="${STATE_DIR}/server_config.json"
TUNNEL_KEY_FILE="${STATE_DIR}/tunnel_key"
CODE_GS_FILE="${STATE_DIR}/Code.gs"
SERVER_DIR="/opt/xrv"
SERVER_BIN="${SERVER_DIR}/bin/xrv-server"
SERVER_SERVICE="xrv-relay"
SERVER_UNIT="/etc/systemd/system/${SERVER_SERVICE}.service"

HAPROXY_CONFIG="/etc/haproxy/xrv.cfg"
HAPROXY_CERT_DIR="/etc/haproxy/certs"
HAPROXY_SERVICE="xrv-haproxy"
HAPROXY_UNIT="/etc/systemd/system/${HAPROXY_SERVICE}.service"
HAPROXY_USER="haproxy"

CERTBOT_HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
CERTBOT_HOOK="${CERTBOT_HOOK_DIR}/xrv-haproxy.sh"

LOG_DIR="/var/log/xrv"
LOG_FILE="${XRV_LOG_FILE:-${LOG_DIR}/install.log}"

DEFAULT_PUBLIC_PORT="8443"
DEFAULT_BACKEND_PORT="9443"

# =====================================================================
# COLORS & OUTPUT
# =====================================================================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  MAGENTA=$'\033[35m'
  CYAN=$'\033[36m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RESET=$'\033[0m'
else
  RED=""
  GREEN=""
  YELLOW=""
  MAGENTA=""
  CYAN=""
  BOLD=""
  DIM=""
  RESET=""
fi
CHECK="✔"
CROSS="✘"
WARN="!"
BULLET="•"

XRV_FAILED=0
ASSUME_YES="${XRV_ASSUME_YES:-0}"
JSON_OUTPUT=0
NONINTERACTIVE="${XRV_NONINTERACTIVE:-0}"

init_log() {
  local dir
  dir="$(dirname "$LOG_FILE")"
  mkdir -p "$dir" 2>/dev/null || {
    LOG_FILE=""
    return 0
  }
  chmod 750 "$dir" 2>/dev/null || true
  touch "$LOG_FILE" 2>/dev/null || {
    LOG_FILE=""
    return 0
  }
  chmod 640 "$LOG_FILE" 2>/dev/null || true
}

log_raw() {
  [[ -n "$LOG_FILE" ]] || return 0
  [[ -d "$(dirname "$LOG_FILE")" ]] || return 0
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(redact "$*")" >>"$LOG_FILE" 2>/dev/null || true
}

redact() {
  local s="$1"
  s="${s//"${TUNNEL_KEY:-}"/"[REDACTED]"}"
  printf '%s' "$s" | sed -E \
    -e 's/AKfycb[A-Za-z0-9_-]{8,}/AKfycb…[REDACTED]/g' \
    -e 's/(tunnel_key["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?)[0-9a-fA-F]{64}/\1[REDACTED]/g'
}

info() {
  printf '%s[INFO]%s %s\n' "$CYAN" "$RESET" "$*"
  log_raw "INFO  $*"
}
ok() {
  printf '%s %s[OK]%s %s\n' "$CHECK" "$GREEN" "$RESET" "$*"
  log_raw "OK    $*"
}
warn() {
  printf '%s %s[WARN]%s %s\n' "$WARN" "$YELLOW" "$RESET" "$*"
  log_raw "WARN  $*"
}
error() {
  printf '%s %s[FAIL]%s %s\n' "$CROSS" "$RED" "$RESET" "$*" >&2
  log_raw "ERROR $*"
  XRV_FAILED=1
}
die() {
  error "$*"
  exit 1
}
step() {
  printf '\n%s%s==>%s %s\n' "$MAGENTA" "$BOLD" "$RESET" "$*"
  log_raw "STEP  $*"
}
substep() { printf '    %s %s\n' "$BULLET" "$*"; }
blank() { printf '\n'; }

on_error() {
  local exit_code="$1" line="$2"
  if [[ "${XRV_FAILED:-0}" != "1" ]]; then
    printf '\n%s%sSomething stopped working.%s\n' "$BOLD" "$RED" "$RESET" >&2
    printf '  Exit code: %s\n' "$exit_code" >&2
    printf '  Where:     line %s of the installer\n' "$line" >&2
    printf '  Full log:  %s\n' "${LOG_FILE:-not available}" >&2
    printf '\nWhat to do: read the last lines above. The log has the exact command\n' >&2
    printf 'and its output. Nothing was hidden from you.\n' >&2
    log_raw "FATAL exit=${exit_code} line=${line}"
  fi
  exit "$exit_code"
}
if [[ "${XRV_LIB_ONLY:-0}" != "1" ]]; then
  trap 'on_error "$?" "$LINENO"' ERR
fi

banner() {
  [[ -t 1 ]] && clear 2>/dev/null || true
  printf '%s' "$CYAN"
  cat <<'XRV_BANNER'
   _____ _____
  |_   _|_   _|
    | |   | |
    | |   | |
    |_|   |_|
XRV_BANNER
  printf '%s' "$RESET"
  printf '%s%s v%s%s — hardened GooseRelayVPN installer\n' "$BOLD" "$XRV_APP" "$XRV_VERSION" "$RESET"
  printf '%sServer: Ubuntu/Debian amd64 or arm64  •  Client: xrv-client.sh%s\n' "$DIM" "$RESET"
  printf '%sby %s%s\n' "$DIM" "$XRV_AUTHOR" "$RESET"
}

pause() {
  [[ -t 0 ]] || return 0
  printf '\n%sPress Enter to continue...%s ' "$DIM" "$RESET"
  IFS= read -r _ || true
}

# =====================================================================
# INPUT HELPERS
# =====================================================================
ask() {
  # ask <variable> <prompt> [default]
  local __var="$1" __prompt="$2" __default="${3-}" __line=""
  if [[ "$NONINTERACTIVE" == "1" ]]; then
    printf -v "$__var" '%s' "$__default"
    return 0
  fi
  printf '%s' "$__prompt" >&2
  if ! IFS= read -r __line; then
    printf '\n' >&2
    die "Input ended unexpectedly. Re-run the installer in an interactive terminal."
  fi
  if [[ -z "$__line" && -n "$__default" ]]; then
    __line="$__default"
  fi
  printf -v "$__var" '%s' "$__line"
}

ask_secret() {
  # ask_secret <variable> <prompt>
  local __var="$1" __prompt="$2" __line=""
  if [[ ! -t 0 ]]; then
    die "A secret must be typed in an interactive terminal, or passed with a flag."
  fi
  printf '%s' "$__prompt" >&2
  if ! IFS= read -rs __line; then
    printf '\n' >&2
    die "Input ended unexpectedly."
  fi
  printf '\n' >&2
  printf -v "$__var" '%s' "$__line"
}

confirm() {
  # confirm <question> [default:no]
  local question="$1" default="${2:-no}" answer
  if [[ "$ASSUME_YES" == "1" ]]; then
    info "AUTO-YES: $question"
    return 0
  fi
  if [[ "$NONINTERACTIVE" == "1" ]]; then
    [[ "$default" == "yes" ]]
    return
  fi
  while true; do
    if [[ "$default" == "yes" ]]; then
      ask answer "$question [Y/n]: " "y"
    else
      ask answer "$question [y/N]: " "n"
    fi
    case "${answer,,}" in
      y | yes) return 0 ;;
      n | no | "") return 1 ;;
      *) warn "Please answer y (yes) or n (no)." ;;
    esac
  done
}

# =====================================================================
# VALIDATION
# =====================================================================
valid_domain() { [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; }
valid_ipv4() {
  local IFS='.' octets x
  read -r -a octets <<<"$1"
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for x in "${octets[@]}"; do
    [[ "$x" =~ ^[0-9]{1,3}$ ]] || return 1
    ((10#$x <= 255)) || return 1
  done
}
valid_host() { valid_domain "$1" || valid_ipv4 "$1"; }
valid_port() { [[ "$1" =~ ^[0-9]+$ ]] && (($1 >= 1 && $1 <= 65535)); }
valid_email() { [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]]; }
valid_tunnel_key() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
valid_relay_url() {
  [[ "$1" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?/tunnel/?$ ]] ||
    [[ "$1" =~ ^https?://\[[0-9a-fA-F:]+\](:[0-9]{1,5})?/tunnel/?$ ]]
}
valid_socks_proxy() {
  [[ "$1" =~ ^socks5://[A-Za-z0-9._-]+:[0-9]{1,5}$ ]] || return 1
  local port="${1##*:}"
  valid_port "$port"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "This part must run on the VPS as root. Use: sudo bash $0"
  fi
  return 0
}

require_command() {
  local cmd="$1" hint="${2:-}"
  if ! command_exists "$cmd"; then
    die "The tool '$cmd' is missing.${hint:+ $hint}"
  fi
}

# =====================================================================
# FILESYSTEM / DOWNLOAD HELPERS
# =====================================================================
mktemp_dir() { mktemp -d "${TMPDIR:-/tmp}/xrv.XXXXXXXX"; }

sha256_of() {
  local file="$1"
  if command_exists sha256sum; then
    sha256sum "$file" | awk '{print $1}'
  elif command_exists openssl; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    die "No SHA-256 tool found. Install coreutils or openssl."
  fi
}

verify_sha256() {
  local file="$1" expected="$2" label="${3:-file}"
  [[ -n "$expected" ]] || die "No pinned SHA-256 for $label. Refusing to install unverified code."
  local actual
  actual="$(sha256_of "$file")"
  if [[ "$actual" != "$expected" ]]; then
    error "Security check failed for $label."
    printf '  Expected: %s\n  Actual:   %s\n' "$expected" "$actual" >&2
    printf '  What this means: the download is not the exact file we trust.\n' >&2
    printf '  What to do: delete it, check your network/proxy, and try again.\n' >&2
    die "Checksum mismatch. Nothing was installed."
  fi
  ok "SHA-256 verified: $label"
}

download_file() {
  # download_file <url> <output> [sha256] [proxy]
  local url="$1" out="$2" expected="${3:-}" proxy="${4:-}"
  local -a args=(
    --fail --location --silent --show-error
    --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 300
    --proto '=https' --tlsv1.2
  )
  [[ -n "$proxy" ]] && args+=(--proxy "$proxy")
  command_exists curl || die "curl is missing. On Ubuntu: sudo apt install curl"
  curl "${args[@]}" --output "$out" "$url" || {
    error "Download failed: $url"
    printf '  What to do:\n' >&2
    printf '   1. Check the server can reach the internet:  curl -I https://github.com\n' >&2
    printf '   2. If you use a proxy, pass it with --download-proxy URL\n' >&2
    printf '   3. Try again; the file may be temporarily unavailable.\n' >&2
    die "Could not download the file. Nothing was installed."
  }
  if [[ -n "$expected" ]]; then
    verify_sha256 "$out" "$expected" "$(basename "$url")"
  fi
}

safe_extract_tar() {
  # Reject absolute paths, traversal and links before extracting.
  local archive="$1" dest="$2"
  install -d -m 700 "$dest"
  if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
    die "The archive contains an unsafe path. Refusing to extract it."
  fi
  if tar -tvzf "$archive" | grep -Eq '^[lh]'; then
    die "The archive contains a link. Refusing to extract it."
  fi
  tar --no-same-owner --no-same-permissions -xzf "$archive" -C "$dest"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'amd64' ;;
    aarch64 | arm64) printf 'arm64' ;;
    *) die "Unsupported CPU architecture: $(uname -m). This installer supports amd64 and arm64." ;;
  esac
}

server_url_for_arch() {
  local arch
  arch="$(detect_arch)"
  if [[ "$arch" == "amd64" ]]; then
    printf '%s' "${XRV_SERVER_URL:-${RELAY_BASE}/GooseRelayVPN-server-${RELAY_RELEASE}-linux-amd64.tar.gz}"
  else
    printf '%s' "${XRV_SERVER_URL_ARM64:-${RELAY_BASE}/GooseRelayVPN-server-${RELAY_RELEASE}-linux-arm64.tar.gz}"
  fi
}

server_sha_for_arch() {
  local arch
  arch="$(detect_arch)"
  if [[ "$arch" == "amd64" ]]; then
    printf '%s' "$SERVER_SHA256_AMD64"
  else
    printf '%s' "$SERVER_SHA256_ARM64"
  fi
}

verify_binary_arch() {
  local file="$1" expected="$2"
  command_exists file || {
    warn "The 'file' tool is missing; skipping architecture display."
    return 0
  }
  local out
  out="$(file -b "$file" 2>/dev/null || true)"
  case "$expected" in
    amd64) [[ "$out" == *"x86-64"* ]] || {
      error "This file is not an amd64 binary: $out"
      return 1
    } ;;
    arm64) [[ "$out" == *"aarch64"* || "$out" == *"ARM aarch64"* ]] || {
      error "This file is not an arm64 binary: $out"
      return 1
    } ;;
  esac
  ok "Binary architecture verified: $expected"
}

# =====================================================================
# STATE
# =====================================================================
CLI_DOMAIN="${XRV_DOMAIN:-}"
CLI_EMAIL="${XRV_EMAIL:-}"
CLI_MODE=""
CLI_PUBLIC_PORT="${XRV_PUBLIC_PORT:-}"
CLI_UPSTREAM_PROXY="${XRV_UPSTREAM_PROXY:-}"

XRV_DOMAIN="${XRV_DOMAIN:-}"
XRV_EMAIL="${XRV_EMAIL:-}"
XRV_MODE="${XRV_MODE:-tls}"
XRV_PUBLIC_PORT="${XRV_PUBLIC_PORT:-$DEFAULT_PUBLIC_PORT}"
XRV_BACKEND_PORT="${XRV_BACKEND_PORT:-$DEFAULT_BACKEND_PORT}"
XRV_UPSTREAM_PROXY="${XRV_UPSTREAM_PROXY:-}"
XRV_ACME_STOP_SERVICES="${XRV_ACME_STOP_SERVICES:-}"

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
  # Explicit flags/environment always win over saved state.
  [[ -n "${CLI_DOMAIN:-}" ]] && XRV_DOMAIN="$CLI_DOMAIN"
  [[ -n "${CLI_EMAIL:-}" ]] && XRV_EMAIL="$CLI_EMAIL"
  [[ -n "${CLI_MODE:-}" ]] && XRV_MODE="$CLI_MODE"
  [[ -n "${CLI_PUBLIC_PORT:-}" ]] && XRV_PUBLIC_PORT="$CLI_PUBLIC_PORT"
  [[ -n "${CLI_UPSTREAM_PROXY:-}" ]] && XRV_UPSTREAM_PROXY="$CLI_UPSTREAM_PROXY"
  if [[ -n "${CLI_DOMAIN:-}" && -z "${CLI_MODE:-}" ]] && valid_domain "$CLI_DOMAIN"; then
    XRV_MODE="tls"
  fi
  : "${XRV_DOMAIN:=}"
  : "${XRV_EMAIL:=}"
  : "${XRV_MODE:=tls}"
  : "${XRV_PUBLIC_PORT:=$DEFAULT_PUBLIC_PORT}"
  : "${XRV_BACKEND_PORT:=$DEFAULT_BACKEND_PORT}"
  : "${XRV_UPSTREAM_PROXY:=}"
  : "${XRV_ACME_STOP_SERVICES:=}"
}

save_state() {
  install -d -m 750 -o root -g xrv "$STATE_DIR"
  local tmp
  tmp="$(mktemp "${STATE_DIR}/.state.XXXXXX")"
  chmod 600 "$tmp"
  {
    printf 'XRV_DOMAIN=%q\n' "$XRV_DOMAIN"
    printf 'XRV_EMAIL=%q\n' "$XRV_EMAIL"
    printf 'XRV_MODE=%q\n' "$XRV_MODE"
    printf 'XRV_PUBLIC_PORT=%q\n' "$XRV_PUBLIC_PORT"
    printf 'XRV_BACKEND_PORT=%q\n' "$XRV_BACKEND_PORT"
    printf 'XRV_UPSTREAM_PROXY=%q\n' "$XRV_UPSTREAM_PROXY"
    printf 'XRV_ACME_STOP_SERVICES=%q\n' "$XRV_ACME_STOP_SERVICES"
    printf 'XRV_INSTALLED_AT=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$tmp"
  mv -f "$tmp" "$STATE_FILE"
  chmod 600 "$STATE_FILE"
}

# =====================================================================
# SYSTEM HELPERS
# =====================================================================
install_packages() {
  local -a packages=(haproxy certbot curl ca-certificates openssl tar gzip file sed gawk ufw)
  local missing=() p
  for p in "${packages[@]}"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "Required packages are already installed"
    return 0
  fi
  info "Missing packages: ${missing[*]}"
  info "They are standard Ubuntu tools. Installing them now."
  run "Refreshing package lists" apt-get update -qq
  run "Installing server packages" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
}

run() {
  # run <title> <command> [args...]
  local title="$1"
  shift
  local log rc=0
  log="$(mktemp)"
  printf '\n%s==>%s %s\n' "$MAGENTA" "$RESET" "$title"
  log_raw "RUN   $title :: $*"
  if "$@" >"$log" 2>&1; then
    ok "$title"
    if [[ -s "$log" ]]; then
      tail -n 8 "$log" | sed 's/^/    /'
    fi
    rm -f "$log"
    return 0
  else
    rc=$?
    error "$title failed (exit code $rc)"
    printf '    Last lines of the real output:\n' >&2
    tail -n 40 "$log" | sed 's/^/    /' >&2 || true
    log_raw "FAILED $title (exit $rc)"
    rm -f "$log"
    return "$rc"
  fi
}

file_mode() { stat -c '%a' "$1" 2>/dev/null || printf 'missing'; }
file_owner() { stat -c '%U:%G' "$1" 2>/dev/null || printf 'missing'; }

public_ipv4() {
  local ip=""
  ip="$(curl -4 -fsS --noproxy '*' --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$ip" ]] || ip="$(curl -4 -fsS --noproxy '*' --max-time 8 https://ifconfig.co/ip 2>/dev/null || true)"
  printf '%s' "$ip"
}

domain_ipv4s() {
  local domain="$1"
  getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u
}

port_listening() {
  local port="$1"
  ss -ltnH "sport = :${port}" 2>/dev/null | awk 'NF{print; exit}'
}

port_owner_commands() {
  local port="$1"
  ss -ltnpH "sport = :${port}" 2>/dev/null |
    sed -n 's/.*users:((\"\([^\"]*\)\",pid=\([0-9]*\).*/\1 pid=\2/p' |
    sort -u
}

# =====================================================================
# SERVICE USERS & DIRECTORIES
# =====================================================================
ensure_users_and_dirs() {
  if ! getent group xrv >/dev/null 2>&1; then
    run "Creating the 'xrv' service group" groupadd --system xrv
  fi
  if ! id -u xrv >/dev/null 2>&1; then
    run "Creating the unprivileged 'xrv' service user" \
      useradd --system --gid xrv --home-dir "$SERVER_DIR" --shell /usr/sbin/nologin --no-create-home xrv
  fi
  run "Creating server directories" install -d -m 755 -o root -g root "$SERVER_DIR" "$SERVER_DIR/bin"
  run "Creating private config directory" install -d -m 750 -o root -g xrv "$STATE_DIR"
  if id -u "$HAPROXY_USER" >/dev/null 2>&1; then
    install -d -m 750 -o root -g "$HAPROXY_USER" "$HAPROXY_CERT_DIR"
  else
    warn "The '$HAPROXY_USER' user does not exist yet; cert directory will be fixed after HAProxy install."
    install -d -m 750 -o root -g root "$HAPROXY_CERT_DIR"
  fi
  install -d -m 750 -o root -g xrv "$LOG_DIR"
}

# =====================================================================
# SERVER BINARY
# =====================================================================
migrate_legacy_installation() {
  local old_key="/root/xrv-tunnel-key.txt"
  local old_config="/root/xrv-server-config.json"
  if [[ ! -f "$TUNNEL_KEY_FILE" && -f "$old_key" ]]; then
    local key
    key="$(tr -d '[:space:]' <"$old_key" 2>/dev/null || true)"
    if valid_tunnel_key "$key"; then
      write_tunnel_key "$key"
      info "Migrated the tunnel key from the v1.0 location ($old_key)."
      info "Existing clients keep working with the same key."
    else
      warn "The old key at $old_key is not valid; a new key will be generated."
    fi
  fi
  if [[ -z "$XRV_UPSTREAM_PROXY" && -f "$old_config" ]] && command_exists python3; then
    local proxy
    proxy="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("upstream_proxy",""))' "$old_config" 2>/dev/null || true)"
    if [[ -n "$proxy" ]] && valid_socks_proxy "$proxy"; then
      XRV_UPSTREAM_PROXY="$proxy"
      info "Migrated the upstream proxy setting from the v1.0 config."
    fi
  fi
}

install_server_binary() {
  local url sha arch workdir tarball binary
  arch="$(detect_arch)"
  url="$(server_url_for_arch)"
  sha="$(server_sha_for_arch)"
  workdir="$(mktemp_dir)"
  tarball="${workdir}/server.tar.gz"

  download_file "$url" "$tarball" "$sha" "${XRV_DOWNLOAD_PROXY:-}"
  run "Checking archive integrity" tar -tzf "$tarball"
  safe_extract_tar "$tarball" "$workdir"

  binary="$(find "$workdir" -maxdepth 3 -type f -name 'goose-server' -print -quit)"
  [[ -n "$binary" ]] || die "The release archive does not contain goose-server. Nothing was installed."
  verify_binary_arch "$binary" "$arch" || die "Wrong CPU architecture. Nothing was installed."

  install -d -m 755 -o root -g root "${SERVER_DIR}/bin"
  if [[ -f "$SERVER_BIN" ]]; then
    cp -a "$SERVER_BIN" "${SERVER_BIN}.bak.$(date +%Y%m%d-%H%M%S)" || true
  fi
  run "Installing the relay server binary" install -m 755 -o root -g root "$binary" "$SERVER_BIN"
  local version
  version="$("$SERVER_BIN" -version 2>/dev/null | head -n 1 || true)"
  ok "Installed relay binary${version:+ ($version)}"
  rm -rf "$workdir"
}

# =====================================================================
# SERVER CONFIG
# =====================================================================
generate_tunnel_key() {
  local entropy key
  entropy="$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null || echo 4096)"
  if [[ "$entropy" =~ ^[0-9]+$ ]] && ((entropy < 256)); then
    warn "The kernel entropy pool looks low ($entropy). Waiting for it to fill."
    sleep 2
  fi
  key="$(openssl rand -hex 32)"
  valid_tunnel_key "$key" || die "The system random generator returned an invalid key. Refusing to continue."
  printf '%s' "$key"
}

read_tunnel_key() {
  if [[ -f "$TUNNEL_KEY_FILE" ]]; then
    local key
    key="$(cat "$TUNNEL_KEY_FILE" 2>/dev/null || true)"
    key="${key//[[:space:]]/}"
    if valid_tunnel_key "$key"; then
      printf '%s' "$key"
      return 0
    fi
    warn "Existing tunnel key file is invalid; a new key will be created."
  fi
  return 1
}

write_tunnel_key() {
  local key="$1" tmp
  tmp="$(mktemp "${STATE_DIR}/.key.XXXXXX")"
  printf '%s\n' "$key" >"$tmp"
  chmod 600 "$tmp"
  chown xrv:xrv "$tmp"
  mv -f "$tmp" "$TUNNEL_KEY_FILE"
  chmod 600 "$TUNNEL_KEY_FILE"
  chown xrv:xrv "$TUNNEL_KEY_FILE"
  ok "Tunnel key stored at $TUNNEL_KEY_FILE (owner xrv, mode 600)"
}

render_server_config() {
  local host="$1" port="$2" key="$3" proxy="$4" debug="$5"
  printf '{\n'
  printf '  "server_host": "%s",\n' "$host"
  printf '  "server_port": %s,\n' "$port"
  printf '  "tunnel_key": "%s",\n' "$key"
  if [[ -n "$proxy" ]]; then
    printf '  "upstream_proxy": "%s",\n' "$proxy"
  else
    printf '  "upstream_proxy": "",\n'
  fi
  printf '  "debug_timing": %s\n' "$debug"
  printf '}\n'
}

write_server_config() {
  local host="$1" port="$2" key="$3" proxy="$4"
  local tmp
  tmp="$(mktemp "${STATE_DIR}/.config.XXXXXX")"
  render_server_config "$host" "$port" "$key" "$proxy" "false" >"$tmp"
  chmod 600 "$tmp"
  chown xrv:xrv "$tmp"
  mv -f "$tmp" "$SERVER_CONFIG"
  chmod 600 "$SERVER_CONFIG"
  chown xrv:xrv "$SERVER_CONFIG"
  ok "Server config written: $SERVER_CONFIG (owner xrv, mode 600)"
}

validate_server_config() {
  local file="$1"
  command_exists python3 || {
    warn "python3 is missing; skipping deep JSON validation."
    return 0
  }
  python3 - "$file" <<'PY'
import json, re, sys
path = sys.argv[1]
with open(path) as f:
    c = json.load(f)
key = c.get("tunnel_key", "")
assert isinstance(key, str) and re.fullmatch(r"[0-9a-f]{64}", key), "tunnel_key must be 64 lowercase hex characters"
assert isinstance(c.get("server_port"), int) and 1 <= c["server_port"] <= 65535, "server_port must be 1-65535"
assert c.get("server_host") in ("127.0.0.1", "0.0.0.0"), "server_host must be 127.0.0.1 or 0.0.0.0"
proxy = c.get("upstream_proxy", "")
assert proxy == "" or re.match(r"^socks5h?://[A-Za-z0-9._:-]+$", proxy), "upstream_proxy must be socks5://host:port or empty"
print("VALID")
PY
  ok "Server config passed validation"
}

# =====================================================================
# SYSTEMD: RELAY
# =====================================================================
write_server_unit() {
  cat >"$SERVER_UNIT" <<'UNIT'
[Unit]
Description=XRV GooseRelayVPN exit relay
Documentation=https://github.com/Kianmhz/GooseRelayVPN
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=xrv
Group=xrv
WorkingDirectory=/opt/xrv
ExecStart=/opt/xrv/bin/xrv-server -config /etc/xrv/server_config.json
Restart=on-failure
RestartSec=2s
TimeoutStopSec=15s
UMask=0077
LimitNOFILE=131072
LimitNPROC=4096

# Sandbox: the relay needs the network and its config, nothing else.
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectProc=invisible
ProcSubset=pid
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
SystemCallArchitectures=native
CapabilityBoundingSet=
AmbientCapabilities=

[Install]
WantedBy=multi-user.target
UNIT
  chmod 644 "$SERVER_UNIT"
  ok "systemd unit written: $SERVER_UNIT"
}

start_server_service() {
  run "Reloading systemd" systemctl daemon-reload
  run "Enabling the relay service at boot" systemctl enable "$SERVER_SERVICE"
  if ! run "Starting the relay service" systemctl restart "$SERVER_SERVICE"; then
    error "The relay service failed to start."
    journalctl -u "$SERVER_SERVICE" -n 40 --no-pager 2>/dev/null | sed 's/^/    /' >&2 || true
    die "Read the journal lines above; they name the exact cause."
  fi
  sleep 1
  if systemctl is-active --quiet "$SERVER_SERVICE"; then
    ok "Relay service is running"
  else
    error "The relay service did not stay running."
    printf '  Last 40 journal lines:\n' >&2
    journalctl -u "$SERVER_SERVICE" -n 40 --no-pager 2>/dev/null | sed 's/^/    /' >&2 || true
    die "Relay failed to start. Read the lines above; they name the exact cause."
  fi
}

backend_health_url() {
  printf 'http://127.0.0.1:%s/healthz' "$XRV_BACKEND_PORT"
}

wait_for_backend() {
  local max="${1:-30}" elapsed=0 code
  url="$(backend_health_url)"
  while ((elapsed < max)); do
    code="$(curl -sS --noproxy '*' -m 5 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
    if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
      ok "Relay answers locally: $url (HTTP $code)"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  error "The relay did not answer at $url after ${max}s (last HTTP ${code:-000})."
  printf '  Last 40 journal lines:\n' >&2
  journalctl -u "$SERVER_SERVICE" -n 40 --no-pager 2>/dev/null | sed 's/^/    /' >&2 || true
  printf '  What to do: the journal above says why. Common causes are a wrong\n' >&2
  printf '  config path, a port already in use, or a key with the wrong length.\n' >&2
  return 1
}

# =====================================================================
# HAProxy (dedicated service, TLS 1.3 only)
# =====================================================================
haproxy_config() {
  local domain="$1" public_port="$2" backend_port="$3" cert_file="$4"
  cat <<EOF
# XRV managed HAProxy configuration. Do not edit by hand.
# Regenerate with: sudo xrv-install.sh --cert
global
    log stdout format raw local0
    maxconn 20000
    nbthread 2
    ssl-default-bind-ciphersuites TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.3 no-tls-tickets
    ssl-default-bind-curves X25519:P-256:P-384
    stats socket /run/${HAPROXY_SERVICE}/admin.sock mode 600 level admin
    stats timeout 30s

defaults
    log global
    mode http
    option httplog
    option dontlognull
    option redispatch
    retries 3
    timeout connect 5s
    timeout client 5m
    timeout server 5m
    timeout http-request 15s
    timeout http-keep-alive 30s
    timeout check 5s
    maxconn 8000

frontend xrv_tls_in
    bind *:${public_port} ssl crt ${cert_file} alpn h2,http/1.1 ssl-min-ver TLSv1.3
    mode http
    option forwardfor
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Forwarded-Port ${public_port}
    http-response del-header Server
    acl xrv_tunnel path_beg /tunnel
    acl xrv_health path /healthz
    http-request deny deny_status 404 unless xrv_tunnel or xrv_health
    default_backend xrv_back

backend xrv_back
    mode http
    balance roundrobin
    option httpchk GET /healthz
    http-check expect status 200
    http-reuse always
    timeout connect 5s
    timeout server 5m
    timeout tunnel 1h
    server xrv1 127.0.0.1:${backend_port} check inter 5s fall 3 rise 2 maxconn 2048
EOF
}

write_haproxy_config() {
  local domain="$1" public_port="$2" backend_port="$3"
  local cert_file="${HAPROXY_CERT_DIR}/${domain}.pem"
  local tmp
  install -d -m 755 -o root -g root /etc/haproxy
  tmp="$(mktemp "${STATE_DIR}/.haproxy.XXXXXX")"
  haproxy_config "$domain" "$public_port" "$backend_port" "$cert_file" >"$tmp"
  chmod 640 "$tmp"
  chown root:"$HAPROXY_USER" "$tmp"
  mv -f "$tmp" "$HAPROXY_CONFIG"
  chmod 640 "$HAPROXY_CONFIG"
  chown root:"$HAPROXY_USER" "$HAPROXY_CONFIG"
  ok "HAProxy config written: $HAPROXY_CONFIG"
}

write_haproxy_unit() {
  cat >"$HAPROXY_UNIT" <<'UNIT'
[Unit]
Description=XRV TLS front (HAProxy, TLS 1.3 only)
Documentation=https://github.com/Kianmhz/GooseRelayVPN
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=haproxy
Group=haproxy
RuntimeDirectory=xrv-haproxy
RuntimeDirectoryMode=0750
ExecStartPre=/usr/sbin/haproxy -c -q -f /etc/haproxy/xrv.cfg
ExecStart=/usr/sbin/haproxy -Ws -f /etc/haproxy/xrv.cfg -p /run/xrv-haproxy/haproxy.pid
ExecReload=/bin/kill -USR2 $MAINPID
KillMode=mixed
Restart=on-failure
RestartSec=2s
LimitNOFILE=65536
UMask=0077

NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectProc=invisible
ProcSubset=pid
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
UNIT
  chmod 644 "$HAPROXY_UNIT"
  ok "systemd unit written: $HAPROXY_UNIT"
}

validate_haproxy_config() {
  require_command haproxy "Install it with: sudo apt install haproxy"
  if ! haproxy -c -q -f "$HAPROXY_CONFIG" >/tmp/xrv-haproxy-check.log 2>&1; then
    error "HAProxy rejected the generated configuration."
    sed 's/^/    /' /tmp/xrv-haproxy-check.log >&2 || true
    rm -f /tmp/xrv-haproxy-check.log
    die "This is an installer bug, not your mistake. Please report the output above."
  fi
  rm -f /tmp/xrv-haproxy-check.log
  ok "HAProxy configuration is valid"
}

build_haproxy_pem() {
  local domain="$1"
  local live="/etc/letsencrypt/live/${domain}"
  [[ -f "${live}/fullchain.pem" && -f "${live}/privkey.pem" ]] ||
    die "Certificate files for $domain are missing under $live."
  install -d -m 750 -o root -g "$HAPROXY_USER" "$HAPROXY_CERT_DIR"
  local tmp
  tmp="$(mktemp "${HAPROXY_CERT_DIR}/.pem.XXXXXX")"
  cat "${live}/fullchain.pem" "${live}/privkey.pem" >"$tmp"
  chmod 640 "$tmp"
  chown root:"$HAPROXY_USER" "$tmp"
  mv -f "$tmp" "${HAPROXY_CERT_DIR}/${domain}.pem"
  chmod 640 "${HAPROXY_CERT_DIR}/${domain}.pem"
  chown root:"$HAPROXY_USER" "${HAPROXY_CERT_DIR}/${domain}.pem"
  ok "Certificate bundle ready: ${HAPROXY_CERT_DIR}/${domain}.pem"
}

check_public_port_free() {
  local port="$1"
  local out
  out="$(port_listening "$port")"
  [[ -z "$out" ]] && return 0
  if systemctl is-active --quiet "$HAPROXY_SERVICE" 2>/dev/null; then
    return 0
  fi
  local owners
  owners="$(port_owner_commands "$port")"
  if [[ "$owners" == *"haproxy"* && "$owners" == *"xrv"* ]]; then
    return 0
  fi
  error "TCP port ${port} is already used by: ${owners:-an unknown process}"
  printf '  What to do: choose another public port with --public-port, or stop\n' >&2
  printf '  the program above. Two programs cannot own one port.\n' >&2
  return 1
}

strip_old_xrv_block() {
  # Pure filter: remove only the exact v1.0 managed block. Every other line is
  # printed unchanged. This is safe to unit-test without touching /etc.
  awk '
    $0 == "# BEGIN XRV managed GooseRelayVPN" { skip=1; next }
    $0 == "# END XRV managed GooseRelayVPN" { skip=0; next }
    !skip { print }
  ' "$1"
}

remove_old_xrv_haproxy_block() {
  # v1.1 uses a dedicated /etc/haproxy/xrv.cfg and xrv-haproxy.service.
  # This function ONLY runs for a v1.0 install that put a marked block into
  # the distro config. It preserves every unrelated line, keeps the file's
  # owner/mode, backs up first, and restores the backup if HAProxy rejects the
  # result. If anything is ambiguous, it refuses to edit.
  local file="${1:-/etc/haproxy/haproxy.cfg}"
  [[ -f "$file" ]] || return 0
  grep -qF "# BEGIN XRV managed GooseRelayVPN" "$file" || return 0

  if ! grep -qF "# END XRV managed GooseRelayVPN" "$file"; then
    warn "Found an incomplete old XRV block in $file. Refusing to edit it."
    return 0
  fi

  local tmp backup
  tmp="$(mktemp)"
  backup="${file}.bak.$(date +%Y%m%d-%H%M%S)"
  strip_old_xrv_block "$file" >"$tmp"

  if grep -qF "# BEGIN XRV managed GooseRelayVPN" "$tmp"; then
    warn "Could not safely isolate the old XRV block. $file was not changed."
    rm -f "$tmp"
    return 0
  fi
  if cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    return 0
  fi

  cp -a "$file" "$backup"
  # cat (not install) preserves the existing owner and mode.
  cat "$tmp" >"$file"
  rm -f "$tmp"

  if command_exists haproxy && ! haproxy -c -q -f "$file" >/dev/null 2>&1; then
    cat "$backup" >"$file"
    warn "The edited $file did not pass 'haproxy -c'. Restored the backup."
    warn "Your original HAProxy configuration is unchanged."
    return 0
  fi

  info "Removed only the old v1.0 XRV block from $file."
  info "All other HAProxy lines were kept. Backup: $backup"
  if systemctl is-active --quiet haproxy 2>/dev/null; then
    systemctl reload haproxy || warn "Could not reload the existing haproxy service; it was left running."
  fi
}

start_haproxy_service() {
  check_public_port_free "$XRV_PUBLIC_PORT" || die "Cannot start the TLS front."

  # Never rewrite the distro configuration. The only exception is removing
  # the block that v1.0 itself added, handled by the guarded function above.
  remove_old_xrv_haproxy_block /etc/haproxy/haproxy.cfg
  info "Existing /etc/haproxy/haproxy.cfg is left untouched by the XRV TLS front."

  run "Reloading systemd" systemctl daemon-reload
  run "Enabling the TLS front at boot" systemctl enable "$HAPROXY_SERVICE"
  if ! run "Starting the TLS front" systemctl restart "$HAPROXY_SERVICE"; then
    error "The TLS front failed to start."
    journalctl -u "$HAPROXY_SERVICE" -n 40 --no-pager 2>/dev/null | sed 's/^/    /' >&2 || true
    die "Read the journal lines above; they name the exact cause."
  fi
  sleep 1
  if ! systemctl is-active --quiet "$HAPROXY_SERVICE"; then
    error "The TLS front did not stay running."
    journalctl -u "$HAPROXY_SERVICE" -n 40 --no-pager 2>/dev/null | sed 's/^/    /' >&2 || true
    die "TLS front failed to start. The journal above gives the exact reason."
  fi
  ok "TLS front is running on port $XRV_PUBLIC_PORT"
}

reload_haproxy() {
  if systemctl is-active --quiet "$HAPROXY_SERVICE"; then
    if systemctl reload "$HAPROXY_SERVICE" 2>/dev/null; then
      ok "TLS front reloaded (no downtime)"
    else
      warn "Reload failed; restarting instead."
      systemctl restart "$HAPROXY_SERVICE" || die "TLS front failed to restart."
    fi
  else
    systemctl start "$HAPROXY_SERVICE" || die "TLS front failed to start."
  fi
}

configure_tls_front() {
  local domain="$1"
  require_command haproxy "Install it with: sudo apt install haproxy"
  [[ -f "${HAPROXY_CERT_DIR}/${domain}.pem" ]] || die "Certificate bundle for $domain is missing."
  write_haproxy_config "$domain" "$XRV_PUBLIC_PORT" "$XRV_BACKEND_PORT"
  write_haproxy_unit
  validate_haproxy_config
  start_haproxy_service
}

# =====================================================================
# CERTIFICATES
# =====================================================================
install_certbot_hook() {
  install -d -m 755 -o root -g root "$CERTBOT_HOOK_DIR"
  cat >"$CERTBOT_HOOK" <<'HOOK'
#!/bin/sh
# XRV: rebuild the HAProxy bundle after a successful renewal, then reload.
set -eu
domain="$(basename "${RENEWED_LINEAGE:-}")"
[ -n "$domain" ] || exit 0
live="/etc/letsencrypt/live/$domain"
out="/etc/haproxy/certs/$domain.pem"
[ -f "$live/fullchain.pem" ] && [ -f "$live/privkey.pem" ] || exit 0
tmp="$(mktemp "/etc/haproxy/certs/.$domain.XXXXXX")"
cat "$live/fullchain.pem" "$live/privkey.pem" >"$tmp"
chmod 640 "$tmp"
chown root:haproxy "$tmp"
mv -f "$tmp" "$out"
chmod 640 "$out"
chown root:haproxy "$out"
systemctl reload xrv-haproxy 2>/dev/null || systemctl restart xrv-haproxy 2>/dev/null || true
HOOK
  chmod 755 "$CERTBOT_HOOK"
  ok "Renewal hook installed: $CERTBOT_HOOK"
}

set_renewal_hooks() {
  local domain="$1" pre_hook="$2" post_hook="$3"
  local renewal="/etc/letsencrypt/renewal/${domain}.conf"
  [[ -f "$renewal" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v pre="$pre_hook" -v post="$post_hook" '
    BEGIN { found=0; in_section=0 }
    /^\[renewalparams\]/ {
      print
      if (pre != "") print "pre_hook = " pre
      if (post != "") print "post_hook = " post
      found=1
      in_section=1
      next
    }
    /^\[/ { in_section=0 }
    in_section && /^pre_hook[[:space:]]*=/ { next }
    in_section && /^post_hook[[:space:]]*=/ { next }
    { print }
    END {
      if (found == 0) {
        print ""
        print "[renewalparams]"
        if (pre != "") print "pre_hook = " pre
        if (post != "") print "post_hook = " post
      }
    }
  ' "$renewal" >"$tmp"
  install -m 600 -o root -g root "$tmp" "$renewal"
  rm -f "$tmp"
  ok "Renewal pre/post hooks saved for $domain"
}

check_domain_dns() {
  local domain="$1" public ips
  public="$(public_ipv4)"
  ips="$(domain_ipv4s "$domain" || true)"
  if [[ -z "$ips" ]]; then
    warn "The name $domain does not resolve to any IPv4 address yet."
    printf '  What to do: in your DNS panel add an A record:\n' >&2
    printf '    %s  A  %s\n' "$domain" "${public:-YOUR_VPS_IP}" >&2
    printf '  DNS can take a few minutes to spread. Certificate issuance will fail\n' >&2
    printf '  until this is correct, because Let'\''s Encrypt must reach this server.\n' >&2
    return 1
  fi
  ok "DNS for $domain points to: $(printf '%s' "$ips" | paste -sd ', ' -)"
  if [[ -n "$public" && "$ips" != *"$public"* ]]; then
    warn "This server's public IPv4 is $public, but $domain does not point to it."
    printf '  If you use Cloudflare or another proxy, turn the orange cloud OFF\n' >&2
    printf '  (DNS only) while issuing the certificate, or use a DNS-01 setup.\n' >&2
    return 1
  fi
  return 0
}

port80_conflicts() {
  local owners
  owners="$(ss -ltnpH 'sport = :80' 2>/dev/null | sed -n 's/.*users:((\"\([^\"]*\)\".*/\1/p' | sort -u)"
  printf '%s' "$owners"
}

issue_certificate() {
  local domain="$1" email="$2" force="${3:-no}"
  require_root
  require_command certbot "Install it with: sudo apt install certbot"

  check_domain_dns "$domain" || {
    if ! confirm "DNS is not confirmed. Try the certificate anyway?"; then
      die "Certificate not requested. Fix DNS first, then run: sudo xrv-install.sh --cert"
    fi
  }

  local conflicts stopped=() svc rc=0
  conflicts="$(port80_conflicts)"
  if [[ -n "$conflicts" ]]; then
    warn "TCP port 80 is currently used by: $conflicts"
    printf '  Let'\''s Encrypt needs port 80 for a few seconds to prove you own\n' >&2
    printf '  the domain. Nothing else may listen there during that check.\n' >&2
    local stop_list=""
    for svc in $conflicts; do
      case "$svc" in
        nginx | apache2 | httpd | haproxy | lighttpd | caddy)
          if confirm "Stop '$svc' for about 20 seconds while the certificate is issued?"; then
            systemctl stop "$svc" || warn "Could not stop $svc; continuing anyway."
            stopped+=("$svc")
            stop_list="${stop_list}${stop_list:+ }$svc"
          else
            die "Certificate not requested. Free port 80 and re-run: sudo xrv-install.sh --cert"
          fi
          ;;
        *)
          die "Port 80 is used by '$svc'. Stop it manually, then re-run: sudo xrv-install.sh --cert"
          ;;
      esac
    done
    XRV_ACME_STOP_SERVICES="$stop_list"
  else
    XRV_ACME_STOP_SERVICES=""
  fi

  install_certbot_hook

  local -a args=(
    certonly --standalone --non-interactive --agree-tos
    --email "$email"
    --cert-name "$domain"
    --domain "$domain"
    --key-type ecdsa --elliptic-curve secp256r1
    --preferred-challenges http
    --deploy-hook "$CERTBOT_HOOK"
  )
  if [[ "$force" == "yes" ]]; then
    args+=(--force-renewal)
  else
    args+=(--keep-until-expiring)
  fi
  [[ "${XRV_ACME_STAGING:-0}" == "1" ]] && args+=(--staging)

  if run "Requesting a Let's Encrypt certificate for $domain" certbot "${args[@]}"; then
    rc=0
  else
    rc=1
  fi

  # Always put the machine back the way we found it.
  if [[ ${#stopped[@]} -gt 0 ]]; then
    for svc in "${stopped[@]}"; do
      systemctl start "$svc" || warn "Could not restart $svc; start it manually."
    done
  fi

  if [[ $rc -ne 0 ]]; then
    printf '\n%sThe certificate request failed.%s\n' "$BOLD" "$RED" >&2
    printf '  Read the certbot lines above. The usual causes are:\n' >&2
    printf '   • DNS still points elsewhere  -> fix the A record, wait, retry.\n' >&2
    printf '   • Port 80 closed              -> open 80/tcp in UFW and the cloud firewall.\n' >&2
    printf '   • Port 80 used by a service   -> stop it briefly, retry.\n' >&2
    printf '   • Too many requests today     -> wait (Let'\''s Encrypt rate limit), or test\n' >&2
    printf '                                    with: XRV_ACME_STAGING=1 sudo xrv-install.sh --cert\n' >&2
    die "No certificate was installed. The old certificate, if any, is untouched."
  fi

  if [[ "${XRV_ACME_STAGING:-0}" == "1" ]]; then
    warn "A STAGING certificate was issued. Browsers and Google do NOT trust it."
    warn "Use it for testing only, then issue a real one without XRV_ACME_STAGING."
  fi

  if [[ -n "$XRV_ACME_STOP_SERVICES" ]]; then
    set_renewal_hooks "$domain" "systemctl stop $XRV_ACME_STOP_SERVICES" "systemctl start $XRV_ACME_STOP_SERVICES"
  else
    set_renewal_hooks "$domain" "" ""
  fi

  build_haproxy_pem "$domain"
  if systemctl is-active --quiet "$HAPROXY_SERVICE" 2>/dev/null; then
    reload_haproxy
  fi

  if systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
    run "Enabling automatic certificate renewal" systemctl enable --now certbot.timer
  else
    install_xrv_renew_timer
  fi
}

install_xrv_renew_timer() {
  cat >/etc/systemd/system/xrv-cert-renew.service <<'UNIT'
[Unit]
Description=XRV certificate renewal
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook /etc/letsencrypt/renewal-hooks/deploy/xrv-haproxy.sh
UNIT
  cat >/etc/systemd/system/xrv-cert-renew.timer <<'UNIT'
[Unit]
Description=Twice-daily XRV certificate renewal check

[Timer]
OnCalendar=*-*-* 03,15:17:00
RandomizedDelaySec=6h
Persistent=true

[Install]
WantedBy=timers.target
UNIT
  run "Enabling XRV certificate renewal timer" systemctl enable --now xrv-cert-renew.timer
}

show_certificate() {
  local domain="$1"
  local live="/etc/letsencrypt/live/${domain}"
  if [[ ! -f "${live}/fullchain.pem" ]]; then
    warn "No certificate found for $domain."
    return 1
  fi
  printf '%sCertificate for %s%s\n' "$BOLD" "$domain" "$RESET"
  openssl x509 -in "${live}/fullchain.pem" -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null |
    sed 's/^/  /'
  local end epoch now days
  end="$(openssl x509 -in "${live}/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)"
  if [[ -n "$end" ]]; then
    epoch="$(date -d "$end" +%s 2>/dev/null || true)"
    now="$(date +%s)"
    if [[ -n "$epoch" ]]; then
      days=$(((epoch - now) / 86400))
      if ((days < 0)); then
        error "The certificate expired $((-days)) days ago."
      elif ((days < 14)); then
        warn "The certificate expires in $days days. Renewal should handle it; check: systemctl status certbot.timer"
      else
        ok "The certificate is valid for $days more days."
      fi
    fi
  fi
  if ((EUID == 0)); then
    certbot certificates --cert-name "$domain" 2>/dev/null | sed 's/^/  /' || true
  fi
}

revoke_certificate() {
  local domain="$1"
  require_root
  confirm "Revoke the certificate for $domain? Sites will stop trusting it immediately." || return 0
  local live="/etc/letsencrypt/live/${domain}"
  [[ -f "${live}/cert.pem" ]] || die "No certificate found for $domain."
  certbot revoke --cert-path "${live}/cert.pem" --reason keycompromise --non-interactive ||
    die "Revocation failed. Read the certbot output above."
  certbot delete --cert-name "$domain" --non-interactive || true
  rm -f "${HAPROXY_CERT_DIR}/${domain}.pem"
  warn "The TLS front still serves the old certificate from memory until it restarts."
  warn "Issue a new certificate immediately: sudo xrv-install.sh --cert"
  ok "Certificate revoked and removed."
}

delete_certificate() {
  local domain="$1"
  require_root
  confirm "Delete the certificate files for $domain without revoking them?" || return 0
  certbot delete --cert-name "$domain" --non-interactive || true
  rm -f "${HAPROXY_CERT_DIR}/${domain}.pem"
  warn "The TLS front keeps the old certificate in memory until it restarts."
  ok "Certificate files deleted. The old key material is gone from disk."
}

certificate_menu() {
  require_root
  load_state
  require_command haproxy "Install it with: sudo apt install haproxy"
  require_command certbot "Install it with: sudo apt install certbot"
  id -u "$HAPROXY_USER" >/dev/null 2>&1 || die "The '$HAPROXY_USER' user is missing. Run the server install first."
  ensure_users_and_dirs
  if [[ "${XRV_MODE:-tls}" != "tls" ]]; then
    XRV_MODE="tls"
    XRV_PUBLIC_PORT="$DEFAULT_PUBLIC_PORT"
    info "The certificate manager switches this server to TLS mode."
    ask_public_port
  fi
  if [[ -n "$XRV_DOMAIN" && "$NONINTERACTIVE" != "1" && -z "$XRV_EMAIL" ]]; then
    ask XRV_EMAIL "Email for Let's Encrypt notices: " ""
    valid_email "$XRV_EMAIL" || die "That is not a valid email address."
  fi
  banner
  printf '\n%sCertificate manager%s\n' "$BOLD" "$RESET"
  printf '  Domain: %s\n' "${XRV_DOMAIN:-not configured}"
  printf '  Public port: %s\n' "$XRV_PUBLIC_PORT"
  printf '  Certificate: %s\n\n' "$([[ -n "$XRV_DOMAIN" && -f "${HAPROXY_CERT_DIR}/${XRV_DOMAIN}.pem" ]] && echo present || echo missing)"
  printf '  1) Show certificate and expiry\n'
  printf '  2) Renew now (keeps the same name)\n'
  printf '  3) Force a brand-new certificate\n'
  printf '  4) Replace the domain (delete old files, issue new)\n'
  printf '  5) Revoke and delete (key was stolen / emergency)\n'
  printf '  6) Test automatic renewal (dry run)\n'
  printf '  b) Back\n'
  printf '  0) Exit\n\n'
  local choice domain email
  ask choice "Choice: "
  case "$choice" in
    1)
      [[ -n "$XRV_DOMAIN" ]] && show_certificate "$XRV_DOMAIN" || warn "No domain configured."
      pause
      ;;
    2)
      [[ -n "$XRV_DOMAIN" ]] || die "No domain configured."
      issue_certificate "$XRV_DOMAIN" "$XRV_EMAIL" no
      pause
      ;;
    3)
      [[ -n "$XRV_DOMAIN" ]] || die "No domain configured."
      issue_certificate "$XRV_DOMAIN" "$XRV_EMAIL" yes
      pause
      ;;
    4)
      ask domain "New domain (e.g. vpn.example.com): "
      valid_domain "$domain" || die "That is not a valid domain name."
      ask email "Email for renewal notices [$XRV_EMAIL]: " "$XRV_EMAIL"
      valid_email "$email" || die "That is not a valid email address."
      local old="$XRV_DOMAIN"
      if [[ -n "$old" && "$old" != "$domain" ]]; then
        confirm "Delete the old certificate files for $old first? (not a revocation)" && delete_certificate "$old"
      fi
      XRV_DOMAIN="$domain"
      XRV_EMAIL="$email"
      issue_certificate "$domain" "$email" yes
      configure_tls_front "$domain"
      save_state
      pause
      ;;
    5)
      [[ -n "$XRV_DOMAIN" ]] || die "No domain configured."
      revoke_certificate "$XRV_DOMAIN"
      pause
      ;;
    6)
      [[ -n "$XRV_DOMAIN" ]] || die "No domain configured."
      run "Testing automatic renewal" certbot renew --dry-run --cert-name "$XRV_DOMAIN"
      pause
      ;;
    b | B) return 0 ;;
    0) exit 0 ;;
    *)
      warn "Invalid choice."
      pause
      certificate_menu
      ;;
  esac
}

# =====================================================================
# FIREWALL
# =====================================================================
detect_ssh_ports() {
  local ports=()
  if command_exists sshd; then
    while IFS= read -r p; do
      [[ "$p" =~ ^[0-9]+$ ]] && ports+=("$p")
    done < <(sshd -T 2>/dev/null | awk '$1=="port"{print $2}')
  fi
  if [[ ${#ports[@]} -eq 0 && -f /etc/ssh/sshd_config ]]; then
    while IFS= read -r p; do
      [[ "$p" =~ ^[0-9]+$ ]] && ports+=("$p")
    done < <(awk 'tolower($1)=="port" && $2 ~ /^[0-9]+$/ {print $2}' /etc/ssh/sshd_config 2>/dev/null)
  fi
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    ports+=("$(awk '{print $4}' <<<"$SSH_CONNECTION")")
  fi
  [[ ${#ports[@]} -gt 0 ]] || ports=(22)
  printf '%s\n' "${ports[@]}" | sort -nu
}

firewall_open_ports() {
  local public_port="$1" with_tls="$2"
  local -a ssh_ports
  mapfile -t ssh_ports < <(detect_ssh_ports)
  info "SSH port(s) detected: ${ssh_ports[*]}"

  if command_exists ufw; then
    local p
    for p in "${ssh_ports[@]}"; do
      ufw allow "${p}/tcp" comment 'XRV: SSH (do not lock yourself out)' >/dev/null 2>&1 || true
    done
    if [[ "$with_tls" == "yes" ]]; then
      ufw allow 80/tcp comment 'XRV: Let'\''s Encrypt renewal' >/dev/null 2>&1 || true
    fi
    ufw allow "${public_port}/tcp" comment 'XRV: TLS tunnel' >/dev/null 2>&1 || true

    if ufw status 2>/dev/null | grep -q "Status: active"; then
      run "Reloading UFW rules" ufw reload
    else
      warn "UFW is installed but not active."
      printf '  Enabling it now would also apply any existing deny rules.\n' >&2
      printf '  SSH port(s) %s are allowed first, so you will not lose access.\n' "${ssh_ports[*]}" >&2
      if confirm "Enable the firewall now?" yes; then
        run "Enabling UFW" ufw --force enable
      else
        warn "Firewall left disabled. Open TCP ${public_port} and 80 in your own firewall."
      fi
    fi
    printf '\n%sCurrent firewall rules:%s\n' "$BOLD" "$RESET"
    ufw status numbered 2>/dev/null | sed 's/^/  /' || true
  elif command_exists firewall-cmd; then
    local p
    for p in "${ssh_ports[@]}"; do firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null || true; done
    if [[ "$with_tls" == "yes" ]]; then
      firewall-cmd --permanent --add-port=80/tcp >/dev/null || true
    fi
    firewall-cmd --permanent --add-port="${public_port}/tcp" >/dev/null || true
    run "Reloading firewalld" firewall-cmd --reload
  else
    warn "No supported firewall manager found (ufw/firewalld)."
    printf '  Open these TCP ports in your provider firewall and any local firewall:\n' >&2
    if [[ "$with_tls" == "yes" ]]; then
      printf '    • 80        (Let'\''s Encrypt verification and renewal)\n' >&2
    fi
    printf '    • %-9s (your tunnel)\n' "$public_port"
    printf '    • SSH port(s): %s\n' "${ssh_ports[*]}" >&2
  fi

  if [[ "$with_tls" == "yes" && "$public_port" != "443" ]]; then
    info "Port 443 is not opened because the tunnel uses ${public_port}."
  fi
}

close_firewall_port() {
  local port="$1"
  command_exists ufw || return 0
  if ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw delete allow "${port}/tcp" >/dev/null 2>&1 || true
  fi
}

# =====================================================================
# APPS SCRIPT CODE.GS
# =====================================================================
write_code_gs() {
  local relay_url="$1" dest="${2:-$CODE_GS_FILE}"
  cat >"$dest" <<'CODE_EOF'
// XRV GooseRelay forwarder — paste this into https://script.google.com
// Deploy as: Execute as Me  |  Who has access: Anyone
// The browser never holds your tunnel key; this script only forwards bytes.
//
// This file is generated by the XRV installer. Keep it out of public repos.

const RELAY_URLS = [
  'RELAY_URL_PLACEHOLDER',
];
const FORWARDER_VERSION = 1;
const PROTOCOL_VERSION = 1;
const ENABLE_INVOCATION_COUNTING = false;
const GAS_RELAY_LOOP_RE = /^https?:\/\/script\.google\.com\/macros\//i;

function doPost(e) {
  for (let i = 0; i < RELAY_URLS.length; i++) {
    if (GAS_RELAY_LOOP_RE.test(RELAY_URLS[i])) {
      throw new Error('relay_loop_detected: RELAY_URLS must point to your VPS /tunnel endpoint, not Apps Script');
    }
  }
  if (ENABLE_INVOCATION_COUNTING) bumpInvocationCount_();
  const payload = (e && e.postData && e.postData.contents) || '';
  let lastError = 'no RELAY_URLS configured';
  for (let i = 0; i < RELAY_URLS.length; i++) {
    try {
      const resp = UrlFetchApp.fetch(RELAY_URLS[i], {
        method: 'post',
        contentType: 'text/plain',
        payload: payload,
        muteHttpExceptions: true,
        followRedirects: false,
        deadline: 30
      });
      const status = resp.getResponseCode();
      const text = resp.getContentText();
      if (status === 200) {
        return ContentService.createTextOutput(text).setMimeType(ContentService.MimeType.TEXT);
      }
      lastError = 'upstream status ' + status + ': ' + text.slice(0, 1024);
    } catch (err) {
      lastError = 'upstream fetch error: ' + String(err);
    }
  }
  throw new Error(lastError);
}

function doGet(e) {
  if (e && e.parameter && e.parameter.legacy === '1') {
    return ContentService.createTextOutput('XRV forwarder OK').setMimeType(ContentService.MimeType.TEXT);
  }
  const props = PropertiesService.getScriptProperties();
  const today = pacificDateKey_();
  const count = parseInt(props.getProperty('count_' + today) || '0', 10);
  return ContentService.createTextOutput(JSON.stringify({
    ok: true, date: today, count: count,
    version: FORWARDER_VERSION, protocol: PROTOCOL_VERSION
  })).setMimeType(ContentService.MimeType.JSON);
}

function pacificDateKey_() {
  return Utilities.formatDate(new Date(), 'America/Los_Angeles', 'yyyy-MM-dd');
}

function bumpInvocationCount_() {
  try {
    const props = PropertiesService.getScriptProperties();
    const today = pacificDateKey_();
    const key = 'count_' + today;
    const raw = props.getProperty(key);
    if (raw === null) pruneStaleCounts_(props, today);
    props.setProperty(key, String((raw === null ? 0 : parseInt(raw, 10)) + 1));
  } catch (err) {}
}

function pruneStaleCounts_(props, today) {
  const keep = 'count_' + today;
  const keys = props.getKeys();
  for (let i = 0; i < keys.length; i++) {
    if (keys[i].indexOf('count_') === 0 && keys[i] !== keep) props.deleteProperty(keys[i]);
  }
}
CODE_EOF
  sed -i "s|RELAY_URL_PLACEHOLDER|${relay_url}|" "$dest"
  chmod 644 "$dest"
  ok "Apps Script file written: $dest"
}

# =====================================================================
# INSTALL FLOWS
# =====================================================================
existing_installation_summary() {
  load_state
  printf '  service      : %s\n' "$(systemctl is-active --quiet "$SERVER_SERVICE" 2>/dev/null && echo "active" || echo "inactive/missing")"
  printf '  binary       : %s\n' "$([[ -x "$SERVER_BIN" ]] && echo "$SERVER_BIN" || echo "missing")"
  printf '  config       : %s\n' "$([[ -f "$SERVER_CONFIG" ]] && echo "$SERVER_CONFIG" || echo "missing")"
  printf '  tunnel key   : %s\n' "$([[ -f "$TUNNEL_KEY_FILE" ]] && echo "$TUNNEL_KEY_FILE" || echo "missing")"
  printf '  TLS front    : %s\n' "$(systemctl is-active --quiet "$HAPROXY_SERVICE" 2>/dev/null && echo "active" || echo "inactive/missing")"
  printf '  domain       : %s\n' "${XRV_DOMAIN:-none}"
  printf '  public port  : %s\n' "${XRV_PUBLIC_PORT:-$DEFAULT_PUBLIC_PORT}"
  printf '  cert         : %s\n' "$([[ -n "${XRV_DOMAIN:-}" && -f "${HAPROXY_CERT_DIR}/${XRV_DOMAIN}.pem" ]] && echo "present" || echo "none")"
}

server_existing_menu() {
  load_state
  banner
  printf '\n%sExisting installation detected%s\n' "$BOLD" "$RESET"
  existing_installation_summary
  printf '\n  1) Keep it as-is and go back (recommended)\n'
  printf '  2) Update the relay binary only (config and key kept)\n'
  printf '  3) Redo TLS certificate and TLS front (key and binary kept)\n'
  printf '  4) Full reinstall (may generate a new key)\n'
  printf '  5) Uninstall\n'
  printf '  b) Back\n'
  printf '  0) Exit\n\n'
  local choice
  ask choice "Choice: "
  case "$choice" in
    1 | b | B) return 1 ;;
    2)
      XRV_UPDATE_ONLY=1
      return 0
      ;;
    3)
      XRV_REDO_TLS=1
      return 0
      ;;
    4)
      warn "A full reinstall can create a NEW tunnel key. Every client would then"
      warn "need the new key before it can connect again."
      if confirm "Generate a new key?" no; then
        XRV_PRESERVE_KEY=0
      else
        XRV_PRESERVE_KEY=1
      fi
      return 0
      ;;
    5)
      uninstall_flow
      return 1
      ;;
    0) exit 0 ;;
    *)
      warn "Invalid choice."
      pause
      server_existing_menu
      ;;
  esac
}

ask_tls_details() {
  local domain email
  if [[ "$NONINTERACTIVE" == "1" ]]; then
    valid_domain "$XRV_DOMAIN" || die "Non-interactive mode needs --domain NAME."
    valid_email "$XRV_EMAIL" || die "Non-interactive mode needs --email ADDRESS."
    XRV_MODE="tls"
    return 0
  fi
  while true; do
    ask domain "Domain name for the tunnel (e.g. vpn.example.com): " "${XRV_DOMAIN:-}"
    domain="${domain,,}"
    domain="${domain%.}"
    if valid_domain "$domain"; then break; fi
    warn "That does not look like a domain name. Example: vpn.example.com"
  done
  while true; do
    ask email "Email for Let's Encrypt notices (certificate expiry warnings): " "${XRV_EMAIL:-}"
    if valid_email "$email"; then break; fi
    warn "That does not look like an email address. Example: you@example.com"
  done
  XRV_DOMAIN="$domain"
  XRV_EMAIL="$email"
  XRV_MODE="tls"
}

ask_public_port() {
  local port
  if [[ "$NONINTERACTIVE" == "1" ]]; then
    valid_port "$XRV_PUBLIC_PORT" || die "Invalid public port '$XRV_PUBLIC_PORT'."
    case "$XRV_PUBLIC_PORT" in
      80 | 9443) die "Public port must not be 80 or 9443. Use 8443 or 443." ;;
    esac
    XRV_BACKEND_PORT="$DEFAULT_BACKEND_PORT"
    return 0
  fi
  while true; do
    ask port "Public TLS port [${XRV_PUBLIC_PORT:-$DEFAULT_PUBLIC_PORT}]: " "${XRV_PUBLIC_PORT:-$DEFAULT_PUBLIC_PORT}"
    if ! valid_port "$port"; then
      warn "A port is a whole number from 1 to 65535. Try 8443."
      continue
    fi
    case "$port" in
      80)
        warn "Port 80 is reserved for the certificate renewal check. Choose 8443 or 443."
        continue
        ;;
      9443)
        warn "Port 9443 is the private relay backend. Choose 8443 or 443."
        continue
        ;;
    esac
    break
  done
  XRV_PUBLIC_PORT="$port"
  XRV_BACKEND_PORT="$DEFAULT_BACKEND_PORT"
}

ask_upstream_proxy() {
  local proxy
  printf '\n%sOptional: route the VPS outbound traffic through a local SOCKS5 proxy.%s\n' "$BOLD" "$RESET"
  printf 'Use this only if you already run one (for example Cloudflare WARP on\n'
  printf 'socks5://127.0.0.1:40000). Leave empty for a direct connection.\n'
  ask proxy "Upstream SOCKS5 proxy [${XRV_UPSTREAM_PROXY:-none}]: " "${XRV_UPSTREAM_PROXY:-}"
  if [[ -z "$proxy" ]]; then
    XRV_UPSTREAM_PROXY=""
    return 0
  fi
  if ! valid_socks_proxy "$proxy"; then
    warn "That is not a valid socks5://host:port address. Leaving it empty."
    XRV_UPSTREAM_PROXY=""
    return 0
  fi
  XRV_UPSTREAM_PROXY="$proxy"
  local hp="${proxy#socks5*://}"
  local host="${hp%:*}" p="${hp##*:}"
  if ! timeout 3 bash -c "exec 3<>/dev/tcp/${host}/${p}" 2>/dev/null; then
    warn "Nothing is listening at ${host}:${p} right now."
    printf '  The relay will still start, but outbound traffic will fail until\n' >&2
    printf '  that proxy is running. Start it first, then: sudo xrv-install.sh --update\n' >&2
  else
    ok "Upstream proxy is reachable: $proxy"
  fi
}

install_server_flow() {
  require_root
  load_state
  banner

  if [[ -f "$STATE_FILE" || -x "$SERVER_BIN" ]] && [[ "$NONINTERACTIVE" != "1" ]] && [[ "${XRV_UPDATE_ONLY:-0}" != "1" ]]; then
    if ! server_existing_menu; then
      ok "Keeping the existing installation. Nothing changed."
      return 0
    fi
  fi

  if [[ "${XRV_UPDATE_ONLY:-0}" == "1" && -f "$SERVER_CONFIG" ]]; then
    step "Updating the relay binary (config and tunnel key are kept)"
    install_packages
    ensure_users_and_dirs
    validate_server_config "$SERVER_CONFIG"
    install_server_binary
    write_server_unit
    start_server_service
    wait_for_backend 30 || die "The updated relay is not healthy."
    ok "Relay binary updated. Config and key were kept."
    XRV_UPDATE_ONLY=0
    return 0
  fi

  step "Collecting your choices"
  if [[ "${XRV_REDO_TLS:-0}" == "1" ]]; then
    install_packages
    ensure_users_and_dirs
    ask_tls_details
    firewall_open_ports "$XRV_PUBLIC_PORT" yes
    issue_certificate "$XRV_DOMAIN" "$XRV_EMAIL" yes
    configure_tls_front "$XRV_DOMAIN"
    write_code_gs "https://${XRV_DOMAIN}:${XRV_PUBLIC_PORT}/tunnel"
    save_state
    ok "TLS certificate and TLS front updated. The relay and key were not touched."
    XRV_REDO_TLS=0
    return 0
  fi

  if [[ "${XRV_MODE:-tls}" == "http" ]]; then
    warn "HTTP-only mode is available for special cases, but it is NOT the default."
    warn "Traffic is still AES-256-GCM encrypted end to end, but the hop from"
    warn "Google to your VPS is not protected by TLS. Use a domain when you can."
    if ! confirm "Continue without a TLS certificate?" no; then
      XRV_MODE="tls"
    fi
  fi

  if [[ "$XRV_MODE" == "tls" ]]; then
    if [[ -z "$XRV_DOMAIN" || -z "$XRV_EMAIL" ]]; then
      ask_tls_details
    fi
    ask_public_port
    ask_upstream_proxy
  else
    XRV_PUBLIC_PORT="$DEFAULT_BACKEND_PORT"
    if ! valid_ipv4 "$XRV_DOMAIN"; then
      ask XRV_DOMAIN "Public IPv4 of this VPS (used by Apps Script): " ""
    fi
    valid_ipv4 "$XRV_DOMAIN" || die "HTTP mode needs the VPS public IPv4 address (pass --domain IP)."
    ask_upstream_proxy
  fi

  step "Installing the operating system pieces"
  install_packages
  ensure_users_and_dirs

  step "Preparing the firewall"
  if [[ "$XRV_MODE" == "tls" ]]; then
    firewall_open_ports "$XRV_PUBLIC_PORT" yes
  else
    firewall_open_ports "$XRV_PUBLIC_PORT" no
  fi

  if [[ "$XRV_MODE" == "tls" ]]; then
    step "Getting a trusted TLS certificate"
    issue_certificate "$XRV_DOMAIN" "$XRV_EMAIL" no
  fi

  step "Installing the relay"
  migrate_legacy_installation
  install_server_binary

  local key=""
  if [[ "${XRV_PRESERVE_KEY:-1}" == "1" ]]; then
    key="$(read_tunnel_key || true)"
  fi
  if [[ -z "$key" ]]; then
    key="$(generate_tunnel_key)"
    ok "Generated a new 256-bit tunnel key"
  else
    ok "Kept the existing tunnel key"
  fi
  write_tunnel_key "$key"

  if [[ "$XRV_MODE" == "tls" ]]; then
    write_server_config "127.0.0.1" "$XRV_BACKEND_PORT" "$key" "$XRV_UPSTREAM_PROXY"
  else
    write_server_config "0.0.0.0" "$XRV_BACKEND_PORT" "$key" "$XRV_UPSTREAM_PROXY"
  fi
  validate_server_config "$SERVER_CONFIG"
  write_server_unit
  start_server_service
  wait_for_backend || die "The relay is not healthy. Nothing else will work until this is fixed."

  if [[ "$XRV_MODE" == "tls" ]]; then
    step "Starting the TLS front"
    configure_tls_front "$XRV_DOMAIN"
    step "Testing the public TLS endpoint"
    if health_check_public; then
      ok "Public TLS endpoint is healthy"
    else
      warn "The public endpoint did not answer yet. Check the error notes below."
      diagnose_public_endpoint || true
    fi
  fi

  step "Writing the Google Apps Script file"
  local relay_url
  if [[ "$XRV_MODE" == "tls" ]]; then
    relay_url="https://${XRV_DOMAIN}:${XRV_PUBLIC_PORT}/tunnel"
  else
    relay_url="http://${XRV_DOMAIN}:${XRV_PUBLIC_PORT}/tunnel"
  fi
  write_code_gs "$relay_url"

  save_state
  show_server_summary "$relay_url"
}

health_check_public() {
  local url
  if [[ "$XRV_MODE" == "tls" ]]; then
    url="https://${XRV_DOMAIN}:${XRV_PUBLIC_PORT}/healthz"
  else
    url="http://${XRV_DOMAIN}:${XRV_PUBLIC_PORT}/healthz"
  fi
  curl -fsS --noproxy '*' --max-time 10 --resolve "${XRV_DOMAIN}:${XRV_PUBLIC_PORT}:127.0.0.1" "$url" >/dev/null 2>&1 ||
    curl -fsS --noproxy '*' --max-time 10 "$url" >/dev/null 2>&1
}

diagnose_public_endpoint() {
  if [[ "$XRV_MODE" != "tls" ]]; then
    return 0
  fi
  printf '\n%sWhy the public test can fail%s\n' "$BOLD" "$RESET"
  if ! systemctl is-active --quiet "$HAPROXY_SERVICE"; then
    printf '  • The TLS front is not running: systemctl status %s\n' "$HAPROXY_SERVICE"
  fi
  if ! ss -ltn "sport = :${XRV_PUBLIC_PORT}" 2>/dev/null | grep -q .; then
    printf '  • Nothing is listening on TCP %s.\n' "$XRV_PUBLIC_PORT"
  fi
  if ! getent ahostsv4 "$XRV_DOMAIN" >/dev/null 2>&1; then
    printf '  • The name %s does not resolve yet.\n' "$XRV_DOMAIN"
  fi
  if command_exists ufw && ! ufw status 2>/dev/null | grep -q "${XRV_PUBLIC_PORT}.*ALLOW"; then
    printf '  • UFW does not show an allow rule for %s/tcp.\n' "$XRV_PUBLIC_PORT"
  fi
  printf '  • Your cloud provider firewall must also allow TCP %s.\n' "$XRV_PUBLIC_PORT"
  printf '  • Test from outside the VPS: curl -v https://%s:%s/healthz\n' "$XRV_DOMAIN" "$XRV_PUBLIC_PORT"
}

show_server_summary() {
  local relay_url="$1"
  printf '\n%s%sInstallation complete%s\n' "$BOLD" "$GREEN" "$RESET"
  printf '  Relay URL for Apps Script : %s\n' "$relay_url"
  printf '  Apps Script file          : %s\n' "$CODE_GS_FILE"
  printf '  Tunnel key file           : %s\n' "$TUNNEL_KEY_FILE"
  printf '  Server config             : %s\n' "$SERVER_CONFIG"
  printf '  Logs                      : journalctl -u %s  and  %s\n' "$SERVER_SERVICE" "$LOG_FILE"
  printf '  Upstream project          : %s\n' "$XRV_PROJECT"
  printf '\n%sNext steps%s\n' "$BOLD" "$RESET"
  printf '  1. On your PC/phone, run the client installer:\n'
  printf '       bash xrv-client.sh\n'
  printf '  2. When it asks for the relay, enter:\n'
  printf '       %s\n' "$relay_url"
  printf '  3. When it asks for the tunnel key, run this on the VPS and paste it:\n'
  printf '       sudo cat %s\n' "$TUNNEL_KEY_FILE"
  printf '  4. In https://script.google.com, create a Web App from:\n'
  printf '       sudo cat %s\n' "$CODE_GS_FILE"
  printf '     Deploy as: Execute as Me / Who has access: Anyone.\n'
  printf '  5. Copy the Deployment ID (starts with AKfycb) into the client installer.\n'
  printf '\n%sImportant%s\n' "$BOLD" "$RESET"
  printf '  • Never share the tunnel key or client_config.json.\n'
  printf '  • If the key leaks: sudo xrv-install.sh --rotate-key, then update every client.\n'
  printf '  • Check health any time: sudo xrv-install.sh --check\n'
}

rotate_key() {
  require_root
  load_state
  banner
  warn "Rotating the key disconnects every client until they get the new key."
  confirm "Generate and install a new tunnel key now?" || return 0
  [[ -f "$SERVER_CONFIG" ]] || die "No server config found. Install the server first."
  local key
  key="$(generate_tunnel_key)"
  write_tunnel_key "$key"
  if [[ "$XRV_MODE" == "tls" ]]; then
    write_server_config "127.0.0.1" "$XRV_BACKEND_PORT" "$key" "$XRV_UPSTREAM_PROXY"
  else
    write_server_config "0.0.0.0" "$XRV_BACKEND_PORT" "$key" "$XRV_UPSTREAM_PROXY"
  fi
  systemctl restart "$SERVER_SERVICE" || die "Relay failed to restart after key rotation."
  wait_for_backend 30 || die "Relay is not healthy after key rotation."
  ok "New key installed. Update every client with: sudo cat $TUNNEL_KEY_FILE"
}

# =====================================================================
# DOCTOR
# =====================================================================
declare -a CHECK_RESULTS=()
check_add() { CHECK_RESULTS+=("$1|$2|$3"); }
check_pass() {
  check_add "PASS" "$1" "${2:-}"
  printf '%s %s[OK]%s %s %s\n' "$CHECK" "$GREEN" "$RESET" "$1" "${2:-}"
}
check_fail() {
  check_add "FAIL" "$1" "${2:-}"
  printf '%s %s[FAIL]%s %s %s\n' "$CROSS" "$RED" "$RESET" "$1" "${2:-}"
}
check_warn() {
  check_add "WARN" "$1" "${2:-}"
  printf '%s %s[WARN]%s %s %s\n' "$WARN" "$YELLOW" "$RESET" "$1" "${2:-}"
}

doctor_flow() {
  load_state
  CHECK_RESULTS=()
  banner
  printf '\n%sXRV Doctor%s\n' "$BOLD" "$RESET"
  printf 'Each line below is one thing we checked, and what we found.\n'

  if [[ "$(uname -s)" == "Linux" ]]; then
    check_pass "Operating system" "$(uname -s) $(uname -r) ($(uname -m))"
  else
    check_fail "Operating system" "This server manager only supports Linux."
  fi
  if [[ "$EUID" -eq 0 ]]; then
    check_pass "Root access" "deep checks are available"
  else
    check_warn "Root access" "run with sudo for the complete check"
  fi

  local avail
  avail="$(df -Pk / | awk 'NR==2{print $4}')"
  if [[ "$avail" =~ ^[0-9]+$ ]] && ((avail > 204800)); then
    check_pass "Free disk space" "$((avail / 1024)) MiB"
  else
    check_fail "Free disk space" "less than 200 MiB free"
  fi

  if systemctl is-active --quiet "$SERVER_SERVICE"; then
    check_pass "Relay service" "$SERVER_SERVICE is active"
  else
    check_fail "Relay service" "$SERVER_SERVICE is not active (systemctl status $SERVER_SERVICE)"
  fi

  if [[ -x "$SERVER_BIN" ]]; then
    check_pass "Relay binary" "$SERVER_BIN"
  else
    check_fail "Relay binary" "missing at $SERVER_BIN"
  fi

  if [[ -f "$SERVER_CONFIG" ]]; then
    if validate_server_config "$SERVER_CONFIG" >/dev/null 2>&1; then
      check_pass "Server config" "valid JSON and valid values"
    else
      check_fail "Server config" "invalid (run: python3 -m json.tool $SERVER_CONFIG)"
    fi
  else
    check_fail "Server config" "missing at $SERVER_CONFIG"
  fi

  if [[ -f "$TUNNEL_KEY_FILE" ]]; then
    local kperm kown key
    kperm="$(file_mode "$TUNNEL_KEY_FILE")"
    kown="$(file_owner "$TUNNEL_KEY_FILE")"
    key="$(cat "$TUNNEL_KEY_FILE" 2>/dev/null || true)"
    if valid_tunnel_key "${key//[[:space:]]/}"; then
      check_pass "Tunnel key" "64 hex characters"
    else
      check_fail "Tunnel key" "not 64 lowercase hex characters"
    fi
    if [[ "$kperm" == "600" ]]; then
      check_pass "Tunnel key permissions" "600 ($kown)"
    else
      check_fail "Tunnel key permissions" "$kperm ($kown); run: chmod 600 $TUNNEL_KEY_FILE"
    fi
  else
    check_fail "Tunnel key" "missing at $TUNNEL_KEY_FILE"
  fi

  if command_exists curl; then
    if curl -fsS --noproxy '*' -m 5 "$(backend_health_url)" >/dev/null 2>&1; then
      check_pass "Local relay health" "$(backend_health_url)"
    else
      check_fail "Local relay health" "$(backend_health_url) did not answer"
    fi
  fi

  if [[ "$XRV_MODE" == "tls" ]]; then
    if systemctl is-active --quiet "$HAPROXY_SERVICE"; then
      check_pass "TLS front" "$HAPROXY_SERVICE is active"
    else
      check_fail "TLS front" "$HAPROXY_SERVICE is not active"
    fi
    if [[ -f "$HAPROXY_CONFIG" ]] && haproxy -c -q -f "$HAPROXY_CONFIG" >/dev/null 2>&1; then
      check_pass "TLS front config" "HAProxy accepts it"
    else
      check_fail "TLS front config" "HAProxy rejects $HAPROXY_CONFIG"
    fi
    if [[ -n "$XRV_DOMAIN" ]]; then
      local cert="${HAPROXY_CERT_DIR}/${XRV_DOMAIN}.pem"
      if [[ -f "$cert" ]]; then
        if openssl x509 -in "/etc/letsencrypt/live/${XRV_DOMAIN}/fullchain.pem" -checkend 1209600 -noout >/dev/null 2>&1; then
          check_pass "Certificate" "valid for more than 14 days"
        else
          check_warn "Certificate" "expires within 14 days or cannot be read"
        fi
      else
        check_fail "Certificate" "missing at $cert"
      fi
      if command_exists getent; then
        local ips public
        ips="$(domain_ipv4s "$XRV_DOMAIN" | paste -sd ', ' -)"
        public="$(public_ipv4)"
        if [[ -n "$ips" ]]; then
          check_pass "DNS" "$XRV_DOMAIN -> $ips"
          if [[ -n "$public" && "$ips" != *"$public"* ]]; then
            check_warn "DNS vs public IP" "domain is $ips, server is $public"
          fi
        else
          check_fail "DNS" "$XRV_DOMAIN does not resolve"
        fi
      fi
      if command_exists openssl && [[ -f "$cert" ]]; then
        local tlsout
        tlsout="$(echo | timeout 10 openssl s_client -connect "${XRV_DOMAIN}:${XRV_PUBLIC_PORT}" \
          -servername "$XRV_DOMAIN" -verify_return_error -CAfile /etc/ssl/certs/ca-certificates.crt 2>&1 || true)"
        if grep -q "Verify return code: 0 (ok)" <<<"$tlsout" && grep -q "TLSv1.3" <<<"$tlsout"; then
          check_pass "Public TLS" "trusted certificate, TLS 1.3"
        else
          check_fail "Public TLS" "handshake or trust failed (curl -v https://${XRV_DOMAIN}:${XRV_PUBLIC_PORT}/healthz)"
        fi
      fi
      if command_exists curl; then
        if curl -fsS --noproxy '*' -m 10 "https://${XRV_DOMAIN}:${XRV_PUBLIC_PORT}/healthz" >/dev/null 2>&1; then
          check_pass "Public health endpoint" "https://${XRV_DOMAIN}:${XRV_PUBLIC_PORT}/healthz"
        else
          check_fail "Public health endpoint" "did not answer (cloud firewall? DNS? TLS front?)"
        fi
      fi
    else
      check_warn "Domain" "no domain configured"
    fi
    if systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
      if systemctl is-active --quiet certbot.timer; then
        check_pass "Renewal timer" "certbot.timer is active"
      else
        check_warn "Renewal timer" "certbot.timer is not active (systemctl enable --now certbot.timer)"
      fi
    fi
  else
    check_warn "TLS" "HTTP-only mode is active; a domain and certificate are recommended"
  fi

  if command_exists ufw; then
    if ufw status 2>/dev/null | grep -q "Status: active"; then
      if ufw status 2>/dev/null | grep -qE "${XRV_PUBLIC_PORT}/tcp.*ALLOW|${XRV_PUBLIC_PORT}.*ALLOW"; then
        check_pass "Firewall" "UFW allows TCP ${XRV_PUBLIC_PORT}"
      else
        check_fail "Firewall" "UFW is active but TCP ${XRV_PUBLIC_PORT} is not allowed"
      fi
    else
      check_warn "Firewall" "UFW is inactive; your provider firewall may still protect you"
    fi
  fi

  printf '\n%sVerdict%s\n' "$BOLD" "$RESET"
  local fails=0 warns=0 line
  for line in "${CHECK_RESULTS[@]}"; do
    [[ "$line" == FAIL\|* ]] && fails=$((fails + 1))
    [[ "$line" == WARN\|* ]] && warns=$((warns + 1))
  done
  if ((fails == 0)); then
    if ((warns > 0)); then
      ok "Everything critical passed ($warns warning(s) to review)."
    else
      ok "Everything critical passed."
    fi
  else
    error "$fails critical check(s) failed. Fix the FAIL lines first."
  fi

  if [[ "$JSON_OUTPUT" == "1" ]]; then
    if ! command_exists python3; then
      warn "JSON output needs python3, which is not installed."
    else
      python3 - "${CHECK_RESULTS[@]}" <<'PY'
import json, sys
rows = []
for raw in sys.argv[1:]:
    status, name, detail = (raw.split("|", 2) + ["", ""])[:3]
    rows.append({"status": status, "check": name, "detail": detail})
fails = sum(1 for r in rows if r["status"] == "FAIL")
print(json.dumps({
    "version": "1.1.1",
    "verdict": "OK" if fails == 0 else "FAIL",
    "failed": fails,
    "checks": rows
}, indent=2))
PY
    fi
  fi

  if ((fails == 0)); then
    return 0
  fi
  return 1
}

# =====================================================================
# STATUS
# =====================================================================
status_flow() {
  load_state
  banner
  printf '\n%sXRV status%s\n' "$BOLD" "$RESET"
  local v
  for v in "$SERVER_SERVICE" "$HAPROXY_SERVICE"; do
    if systemctl is-active --quiet "$v" 2>/dev/null; then
      printf '  %-14s %sactive%s\n' "$v" "$GREEN" "$RESET"
    else
      printf '  %-14s %sinactive%s\n' "$v" "$RED" "$RESET"
    fi
  done
  printf '  %-14s %s\n' "domain" "${XRV_DOMAIN:-none}"
  printf '  %-14s %s\n' "public port" "$XRV_PUBLIC_PORT"
  printf '  %-14s %s\n' "backend" "$(backend_health_url)"
  if command_exists curl; then
    printf '  %-14s %s\n' "backend HTTP" "$(curl -sS --noproxy '*' -m 5 -o /dev/null -w '%{http_code}' "$(backend_health_url)" 2>/dev/null || echo 'no answer')"
  fi
  if [[ -n "$XRV_DOMAIN" ]]; then
    show_certificate "$XRV_DOMAIN" || true
  fi
  printf '\n  Recent relay log:\n'
  journalctl -u "$SERVER_SERVICE" -n 8 --no-pager 2>/dev/null | sed 's/^/    /' || true
}

# =====================================================================
# UNINSTALL
# =====================================================================
uninstall_flow() {
  require_root
  load_state
  banner
  printf '\n%sUninstall XRV from this server%s\n' "$BOLD" "$RESET"
  confirm "Stop and remove the XRV relay and TLS front?" || return 0

  systemctl disable --now "$SERVER_SERVICE" 2>/dev/null || true
  systemctl disable --now "$HAPROXY_SERVICE" 2>/dev/null || true
  rm -f "$SERVER_UNIT" "$HAPROXY_UNIT"
  rm -f /etc/systemd/system/xrv-cert-renew.service /etc/systemd/system/xrv-cert-renew.timer
  systemctl daemon-reload

  rm -f "$HAPROXY_CONFIG" "$CERTBOT_HOOK"
  rm -rf "$SERVER_DIR"
  ok "Relay binary and runtime directory removed"

  if confirm "Delete /etc/xrv (config, state and tunnel key) as well?" no; then
    rm -rf "$STATE_DIR"
    ok "Configuration removed"
  else
    info "Kept $STATE_DIR so you can reinstall without losing the key."
  fi

  if confirm "Delete the XRV certificate bundle from $HAPROXY_CERT_DIR?" no; then
    rm -f "${HAPROXY_CERT_DIR}/${XRV_DOMAIN}.pem" 2>/dev/null || true
    ok "HAProxy certificate bundle removed"
  fi

  if confirm "Delete the Let's Encrypt certificate files for ${XRV_DOMAIN:-the domain} (no revocation)?" no; then
    [[ -n "$XRV_DOMAIN" ]] && certbot delete --cert-name "$XRV_DOMAIN" --non-interactive || true
  fi

  if confirm "Remove the XRV firewall rules (80, ${XRV_PUBLIC_PORT})?" no; then
    close_firewall_port 80
    close_firewall_port "$XRV_PUBLIC_PORT"
    ok "Firewall rules removed"
  fi

  if id -u xrv >/dev/null 2>&1 && confirm "Remove the 'xrv' service user?" no; then
    userdel xrv 2>/dev/null || true
  fi

  ok "Uninstall finished."
}

# =====================================================================
# CLIENT DELEGATION
# =====================================================================
run_client_installer() {
  local local_script dir tmp
  if [[ "$EUID" -eq 0 ]]; then
    warn "This is the VPS server manager, running as root."
    warn "The client installer belongs on your own PC or phone, not usually on the VPS."
    if ! confirm "Run the client installer on this VPS anyway?" no; then
      printf '  Download it on your device with:\n' >&2
      printf '    curl -fsSLO %s\n' "$CLIENT_SCRIPT_URL" >&2
      printf '    bash xrv-client.sh\n' >&2
      return 0
    fi
  fi
  dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
  local_script="${dir}/xrv-client.sh"
  if [[ -f "$local_script" ]]; then
    if [[ -n "$CLIENT_SCRIPT_SHA256" ]]; then
      verify_sha256 "$local_script" "$CLIENT_SCRIPT_SHA256" "xrv-client.sh"
    fi
    info "Starting the standalone client installer: $local_script"
    exec bash "$local_script"
  fi

  info "Downloading the standalone client installer from the project repo."
  tmp="$(mktemp "${TMPDIR:-/tmp}/xrv-client.XXXXXX.sh")"
  download_file "$CLIENT_SCRIPT_URL" "$tmp" "$CLIENT_SCRIPT_SHA256" "${XRV_DOWNLOAD_PROXY:-}"
  chmod 700 "$tmp"
  bash "$tmp"
  rm -f "$tmp"
}

# =====================================================================
# MENU
# =====================================================================
main_menu() {
  local choice
  while true; do
    banner
    printf '\n%sXRV v%s — server manager%s\n' "$BOLD" "$XRV_VERSION" "$RESET"
    printf '  1) Install or update the server (this VPS)\n'
    printf '  2) Client installer (Linux amd64 / Termux arm64)\n'
    printf '  3) Certificate manager (issue / renew / replace / revoke)\n'
    printf '  4) Rotate the tunnel key\n'
    printf '  5) Doctor (full health check, exact causes)\n'
    printf '  6) Status and logs\n'
    printf '  7) Uninstall\n'
    printf '  h) Help\n'
    printf '  0) Exit\n\n'
    ask choice "Choice: "
    case "$choice" in
      1)
        install_server_flow || true
        pause
        ;;
      2)
        run_client_installer || true
        pause
        ;;
      3)
        certificate_menu || true
        pause
        ;;
      4)
        rotate_key || true
        pause
        ;;
      5)
        doctor_flow || true
        pause
        ;;
      6)
        status_flow || true
        pause
        ;;
      7)
        uninstall_flow || true
        pause
        ;;
      h | H)
        usage
        pause
        ;;
      0)
        ok "Bye. (XRV ${XRV_VERSION})"
        exit 0
        ;;
      *)
        warn "Invalid choice. Type 1-7, h, or 0."
        pause
        ;;
    esac
  done
}

usage() {
  cat <<'HELP_EOF'
XRV v1.1.1 — hardened GooseRelayVPN server installer

USAGE
  sudo bash xrv-install.sh                 interactive menu
  sudo bash xrv-install.sh --check         full health check
  sudo bash xrv-install.sh --server        install/update non-interactively
  sudo bash xrv-install.sh --cert          certificate manager
  sudo bash xrv-install.sh --rotate-key    generate a new tunnel key
  sudo bash xrv-install.sh --uninstall     remove XRV from this server

NON-INTERACTIVE SERVER OPTIONS
  --domain NAME          domain name for TLS (e.g. vpn.example.com)
  --email ADDRESS        Let's Encrypt contact address
  --public-port PORT     public TLS port (default 8443)
  --http                 HTTP-only mode (no domain/certificate; not recommended)
  --tls                  force TLS mode when a saved state says HTTP
  --upstream-proxy URL   optional socks5://127.0.0.1:40000 for outbound routing
  --yes                  answer yes to confirmations
  --staging              use the Let's Encrypt staging service (testing only)
  --json                 machine-readable doctor output
  --download-proxy URL   proxy used only for downloads
  --rotate-key           replace the tunnel key (disconnects old clients)

WHAT THE INSTALLER DOES
  1. Installs haproxy, certbot and standard tools from Ubuntu/Debian.
  2. Opens only the ports that are needed (SSH, 80 for ACME, your TLS port).
  3. Requests a trusted ECDSA certificate and renews it automatically.
  4. Installs the relay as an unprivileged 'xrv' systemd service.
  5. Runs HAProxy TLS 1.3-only in its own sandboxed service.
  6. Writes Code.gs with your relay URL and prints the exact client steps.

SAFETY NOTES
  • The relay checksum is pinned. A mismatch stops the install.
  • The tunnel key is never printed in logs. It is stored 600, owned by xrv.
  • Re-running is safe: config and key are kept unless you ask for a new key.
  • Full log (no secrets): /var/log/xrv/install.log

CLIENT
  The standalone client installer for Ubuntu amd64 and Termux arm64 is:
    bash xrv-client.sh
HELP_EOF
}

# =====================================================================
# TOP-LEVEL DISPATCH
# =====================================================================
main() {
  local mode="menu"
  local -a positional=()

  while (($# > 0)); do
    case "$1" in
      --help | -h)
        usage
        return 0
        ;;
      --version | -V)
        printf 'XRV %s\n' "$XRV_VERSION"
        return 0
        ;;
      --dry-run)
        if bash -n "${BASH_SOURCE[0]}" 2>/dev/null; then
          ok "Syntax check passed."
        else
          bash -n "${BASH_SOURCE[0]}" || true
          die "Syntax check failed."
        fi
        return 0
        ;;
      --check | --doctor) mode="doctor" ;;
      --server | --install) mode="server" ;;
      --cert | --certificates) mode="cert" ;;
      --update) mode="update" ;;
      --rotate-key | --rotate) mode="rotate" ;;
      --uninstall) mode="uninstall" ;;
      --http)
        CLI_MODE="http"
        XRV_MODE="http"
        ;;
      --staging) XRV_ACME_STAGING=1 ;;
      --json) JSON_OUTPUT=1 ;;
      --yes | -y) ASSUME_YES=1 ;;
      --non-interactive) NONINTERACTIVE=1 ;;
      --domain)
        shift || die "--domain needs a value"
        CLI_DOMAIN="$1"
        XRV_DOMAIN="$1"
        ;;
      --email)
        shift || die "--email needs a value"
        CLI_EMAIL="$1"
        XRV_EMAIL="$1"
        ;;
      --public-port)
        shift || die "--public-port needs a value"
        CLI_PUBLIC_PORT="$1"
        XRV_PUBLIC_PORT="$1"
        ;;
      --upstream-proxy)
        shift || die "--upstream-proxy needs a value"
        CLI_UPSTREAM_PROXY="$1"
        XRV_UPSTREAM_PROXY="$1"
        ;;
      --download-proxy)
        shift || die "--download-proxy needs a value"
        XRV_DOWNLOAD_PROXY="$1"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -*) die "Unknown option: $1 (try --help)" ;;
      *) positional+=("$1") ;;
    esac
    shift
  done

  init_log
  load_state

  case "$mode" in
    doctor)
      if doctor_flow; then
        return 0
      fi
      return 1
      ;;
    cert) certificate_menu ;;
    update)
      XRV_UPDATE_ONLY=1
      install_server_flow
      ;;
    rotate) rotate_key ;;
    uninstall) uninstall_flow ;;
    server)
      if [[ "$NONINTERACTIVE" == "1" ]]; then
        if [[ "$XRV_MODE" != "http" ]]; then
          valid_domain "$XRV_DOMAIN" || die "--non-interactive needs a valid --domain, or use --http."
          valid_email "$XRV_EMAIL" || die "--non-interactive needs a valid --email."
        fi
        valid_port "$XRV_PUBLIC_PORT" || die "Invalid --public-port."
        case "$XRV_PUBLIC_PORT" in
          80) die "Port 80 is reserved for Let's Encrypt. Use 8443 or 443." ;;
          9443) die "Port 9443 is the private relay backend. Use 8443 or 443." ;;
        esac
      fi
      install_server_flow
      ;;
    menu) main_menu ;;
    *) die "Unknown mode: $mode" ;;
  esac
}

# Allow tests to source the functions without running anything.
if [[ "${XRV_LIB_ONLY:-0}" == "1" ]]; then
  return 0
fi

main "$@"
