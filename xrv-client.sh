#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# XRV v1.1.0 — standalone GooseRelayVPN client installer for
# Ubuntu/Linux amd64 (also Linux arm64) and Android Termux arm64.
#
# This file is self-contained. You can run it directly:
#   bash xrv-client.sh
# or straight from the repo:
#   bash <(curl -fsSL https://raw.githubusercontent.com/jackh0006/XRV-Installer/master/xrv-client.sh)
#
# It downloads the official GooseRelayVPN client, checks its pinned SHA-256,
# asks a few plain-language questions, writes a safe config, and gives you
# start/stop/status scripts.
#
# Design goals:
#   * Explain every question and every error in normal words.
#   * Never print or log the tunnel key.
#   * Verify the download before executing it.
#   * Work without root. Work in Termux without extra packages where possible.
#   * Be safe to re-run: an update keeps your existing config.

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# =====================================================================
# VERSION & PINNED RELEASE
# =====================================================================
XRV_VERSION="1.1.0"
XRV_APP="XRV"
XRV_AUTHOR="jackh0006 <jackh109867@gmail.com>"
XRV_PROJECT="https://github.com/Kianmhz/GooseRelayVPN"
XRV_REPO="jackh0006/XRV-Installer"
XRV_BRANCH="${XRV_BRANCH:-master}"
RELAY_RELEASE="${XRV_RELAY_RELEASE:-v1.7.1}"
RELAY_BASE="https://github.com/Kianmhz/GooseRelayVPN/releases/download/${RELAY_RELEASE}"

CLIENT_SHA_ANDROID_ARM64="${XRV_CLIENT_SHA_ANDROID_ARM64:-625a297158280abd859ac0512dbb25cb3bb16ac5796a49722d2734fd7cdd7b58}"
CLIENT_SHA_LINUX_AMD64="${XRV_CLIENT_SHA_LINUX_AMD64:-6fc55a8f54522dacffecf17d965ec26db5589767a6ef964a2c7ab7ec79c77115}"
CLIENT_SHA_LINUX_ARM64="${XRV_CLIENT_SHA_LINUX_ARM64:-c2d4c92665d914fd3d694380b1e08d10c2b3b0ec5c5f8bb00d7164caa67e260e}"

DEFAULT_EDGE="216.239.38.120"
GOOGLE_EDGES=("216.239.32.120" "216.239.34.120" "216.239.36.120" "216.239.38.120")

# =====================================================================
# OPTIONS / STATE
# =====================================================================
HOME_DIR="${XRV_CLIENT_HOME:-$HOME/xrv}"
RELAY_INPUT="${XRV_RELAY_URL:-}"
RELAY_HOST="${XRV_RELAY_HOST:-}"
RELAY_PORT="${XRV_RELAY_PORT:-8443}"
RELAY_SCHEME="${XRV_RELAY_SCHEME:-}"
RELAY_URL=""
RELAY_BASE_URL=""
PLATFORM="${XRV_PLATFORM:-}"
PLATFORM_URL=""
PLATFORM_SHA=""
IS_TERMUX=0
IS_LINUX=0

DEPLOYMENTS=()
TUNNEL_KEY="${XRV_TUNNEL_KEY:-}"
TUNNEL_KEY_FILE_ARG="${XRV_TUNNEL_KEY_FILE:-}"
SOCKS_PORT="${XRV_SOCKS_PORT:-1080}"
SOCKS_USER="${XRV_SOCKS_USER:-}"
SOCKS_PASS="${XRV_SOCKS_PASS:-}"
LAN_SHARE=0
COALESCE_MS="${XRV_COALESCE_MS:-25}"
IDLE_SLOTS=2
EDGE="${XRV_EDGE:-}"
DOWNLOAD_PROXY="${XRV_DOWNLOAD_PROXY:-${HTTPS_PROXY:-}}"
OFFLINE_BINARY="${XRV_OFFLINE_BINARY:-}"

ASSUME_YES=0
NONINTERACTIVE="${XRV_NONINTERACTIVE:-0}"
NO_PROBE=0
NO_HEALTH=0
NO_START=0
SKIP_ARCH=0
INSTALL_SERVICE=0
SERVICE_EXPLICIT=0
DO_UPDATE=0
DO_UNINSTALL=0
DO_CHECK=0
PURGE=0

LOG_FILE="${XRV_LOG_FILE:-${HOME}/.xrv/logs/install.log}"
XRV_FAILED=0

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

init_log() {
  local dir
  dir="$(dirname "$LOG_FILE")"
  mkdir -p "$dir" 2>/dev/null || {
    LOG_FILE=""
    return 0
  }
  chmod 700 "$dir" 2>/dev/null || true
  touch "$LOG_FILE" 2>/dev/null || {
    LOG_FILE=""
    return 0
  }
  chmod 600 "$LOG_FILE" 2>/dev/null || true
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

on_error() {
  local exit_code="$1" line="$2"
  if [[ "${XRV_FAILED:-0}" != "1" ]]; then
    printf '\n%s%sSomething stopped working.%s\n' "$BOLD" "$RED" "$RESET" >&2
    printf '  Exit code: %s\n' "$exit_code" >&2
    printf '  Where:     line %s of the client installer\n' "$line" >&2
    printf '  Log file:  %s\n' "${LOG_FILE:-not available}" >&2
    printf '\nNothing was hidden. The last lines above name the exact command\n' >&2
    printf 'that failed. Fix that, then run this installer again.\n' >&2
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
  cat <<'BANNER'
   _____ _____
  |_   _|_   _|
    | |   | |
    | |   | |
    |_|   |_|
BANNER
  printf '%s' "$RESET"
  printf '%s%s v%s%s — GooseRelayVPN client\n' "$BOLD" "$XRV_APP" "$XRV_VERSION" "$RESET"
  printf '%sLinux amd64 · Linux arm64 · Android Termux arm64%s\n' "$DIM" "$RESET"
  printf '%sby %s%s\n' "$DIM" "$XRV_AUTHOR" "$RESET"
}

pause() {
  [[ -t 0 ]] || return 0
  printf '\n%sPress Enter to continue...%s ' "$DIM" "$RESET"
  IFS= read -r _ || true
}

# =====================================================================
# INPUT
# =====================================================================
ask() {
  local __var="$1" __prompt="$2" __default="${3-}" __line=""
  if [[ "$NONINTERACTIVE" == "1" ]]; then
    printf -v "$__var" '%s' "$__default"
    return 0
  fi
  printf '%s' "$__prompt" >&2
  if ! IFS= read -r __line; then
    printf '\n' >&2
    die "Input ended unexpectedly. Run the installer inside a real terminal."
  fi
  [[ -z "$__line" && -n "$__default" ]] && __line="$__default"
  printf -v "$__var" '%s' "$__line"
}

ask_secret() {
  local __var="$1" __prompt="$2" __line=""
  if [[ ! -t 0 ]]; then
    die "A secret must be typed in a terminal, or supplied with --tunnel-key / --tunnel-key-file."
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
# VALIDATION & SMALL HELPERS
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
valid_tunnel_key() { [[ "$1" =~ ^[0-9a-f]{64}$ ]]; }
valid_deployment_id() { [[ "$1" =~ ^AKfycb[A-Za-z0-9_-]{44,}$ ]]; }
valid_account() { [[ "$1" =~ ^[A-Za-z0-9._-]{1,32}$ ]]; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

is_ipv4() { valid_ipv4 "$1"; }

normalize_deployment_id() {
  local v="$1"
  v="${v//[[:space:]]/}"
  v="${v%/}"
  v="${v%/exec}"
  if [[ "$v" == *"/s/"* ]]; then
    v="${v#*"/s/"}"
    v="${v%%/*}"
  fi
  printf '%s' "$v"
}

json_escape() {
  local s="$1" out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      \\) out+='\\' ;;
      \") out+='\"' ;;
      $'\n') out+='\n' ;;
      $'\r') out+='\r' ;;
      $'\t') out+='\t' ;;
      *) out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

sha256_of() {
  local file="$1"
  if command_exists sha256sum; then
    sha256sum "$file" | awk '{print $1}'
  elif command_exists openssl; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  else
    die "No SHA-256 tool found. Install coreutils, then run the installer again."
  fi
}

download_file() {
  local url="$1" out="$2" expected="${3:-}" label="${4:-file}"
  local -a args=(
    --fail --location --silent --show-error
    --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 300
    --proto '=https' --tlsv1.2
  )
  [[ -n "$DOWNLOAD_PROXY" ]] && args+=(--proxy "$DOWNLOAD_PROXY")
  command_exists curl || die "curl is missing. $INSTALL_HINT"
  curl "${args[@]}" --output "$out" "$url" || {
    error "Could not download $label."
    printf '  What to do:\n' >&2
    printf '   1. Check this device can reach GitHub:  curl -I https://github.com\n' >&2
    printf '   2. If you use a proxy, pass: --proxy http://127.0.0.1:8080\n' >&2
    printf '   3. Try again; the release server may be briefly unavailable.\n' >&2
    die "Download failed. Nothing was installed."
  }
  if [[ -n "$expected" ]]; then
    local actual
    actual="$(sha256_of "$out")"
    if [[ "$actual" != "$expected" ]]; then
      error "The downloaded file is not the exact file we trust."
      printf '  Expected: %s\n  Actual:   %s\n' "$expected" "$actual" >&2
      printf '  This can mean a broken download, a captive portal, or an attack.\n' >&2
      printf '  Nothing was installed. Try again on another network if possible.\n' >&2
      die "Security check failed for $label."
    fi
    ok "SHA-256 verified: $label"
  fi
}

safe_extract_tar() {
  local archive="$1" dest="$2" listing
  listing="$(mktemp)"
  if ! tar -tzf "$archive" >"$listing"; then
    rm -f "$listing"
    die "The archive is damaged or not a gzip file. Nothing was installed."
  fi
  if grep -Eq '(^/|(^|/)\.\.(/|$))' "$listing"; then
    rm -f "$listing"
    die "The archive contains an unsafe path. Refusing to extract it."
  fi
  if tar -tvzf "$archive" >"$listing" 2>/dev/null && grep -Eq '^[lh]' "$listing"; then
    rm -f "$listing"
    die "The archive contains a link. Refusing to extract it."
  fi
  rm -f "$listing"
  tar --no-same-owner --no-same-permissions -xzf "$archive" -C "$dest"
}

check_ipv4_port_open() {
  local host="$1" port="$2"
  timeout 3 bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null
}

port_in_use() {
  local port="$1"
  if command_exists ss; then
    ss -ltnH "sport = :${port}" 2>/dev/null | grep -q .
  elif command_exists netstat; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"
  else
    check_ipv4_port_open 127.0.0.1 "$port" && return 0
    return 1
  fi
}

port_owner_text() {
  local port="$1"
  if command_exists ss; then
    ss -ltnpH "sport = :${port}" 2>/dev/null | sed -n 's/.*users:((\"\([^\"]*\)\".*/\1/p' | sort -u | paste -sd ', ' -
  fi
}

# =====================================================================
# PLATFORM
# =====================================================================
detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  if [[ -n "${TERMUX_VERSION:-}" || "${PREFIX:-}" == *"com.termux"* ]]; then
    IS_TERMUX=1
    case "$arch" in
      aarch64 | arm64) PLATFORM="android-arm64" ;;
      *) die "Termux on '$arch' is not supported. This installer supports Termux arm64 only." ;;
    esac
  elif [[ "$os" == "Linux" ]]; then
    IS_LINUX=1
    case "$arch" in
      x86_64 | amd64) PLATFORM="linux-amd64" ;;
      aarch64 | arm64) PLATFORM="linux-arm64" ;;
      *) die "Unsupported Linux CPU: $arch. Supported: x86_64 and aarch64." ;;
    esac
  else
    die "This client installer supports Linux and Android Termux only (found $os)."
  fi

  if [[ -n "${XRV_PLATFORM:-}" ]]; then
    PLATFORM="$XRV_PLATFORM"
  fi

  case "$PLATFORM" in
    android-arm64)
      PLATFORM_URL="${RELAY_BASE}/GooseRelayVPN-client-${RELAY_RELEASE}-android-arm64.tar.gz"
      PLATFORM_SHA="$CLIENT_SHA_ANDROID_ARM64"
      ;;
    linux-amd64)
      PLATFORM_URL="${RELAY_BASE}/GooseRelayVPN-client-${RELAY_RELEASE}-linux-amd64.tar.gz"
      PLATFORM_SHA="$CLIENT_SHA_LINUX_AMD64"
      ;;
    linux-arm64)
      PLATFORM_URL="${RELAY_BASE}/GooseRelayVPN-client-${RELAY_RELEASE}-linux-arm64.tar.gz"
      PLATFORM_SHA="$CLIENT_SHA_LINUX_ARM64"
      ;;
    *) die "Unknown platform '$PLATFORM'. Use android-arm64, linux-amd64 or linux-arm64." ;;
  esac
  ok "Platform: $PLATFORM"
}

ensure_download_tools() {
  local missing=() need_core=0
  command_exists curl || missing+=(curl)
  command_exists tar || missing+=(tar)
  if ! command_exists sha256sum && ! command_exists openssl; then need_core=1; fi
  if ! command_exists install || ! command_exists stat; then need_core=1; fi
  if ((need_core == 1)); then missing+=(coreutils); fi
  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi
  warn "Missing tools: ${missing[*]}"
  if ((IS_TERMUX == 1)); then
    printf '  Termux can install them for you now (about 10 MB).\n' >&2
    if confirm "Install ${missing[*]} in Termux?" yes; then
      pkg install -y "${missing[@]}" || die "Termux could not install the tools. Run: pkg install -y curl tar coreutils"
    else
      die "Install them first: pkg install -y curl tar coreutils"
    fi
  else
    printf '  On Ubuntu/Debian run:\n' >&2
    printf '    sudo apt update && sudo apt install -y curl tar coreutils openssl\n' >&2
    die "Install the missing tools, then run the installer again."
  fi
}

# =====================================================================
# RELAY / HEALTH
# =====================================================================
parse_relay_value() {
  local v="$1" rest hostport
  v="${v//[[:space:]]/}"
  [[ -n "$v" ]] || return 0
  if [[ "$v" =~ ^https?:// ]]; then
    RELAY_SCHEME="${v%%://*}"
    rest="${v#*://}"
    rest="${rest%%/*}"
    if [[ "$rest" == \[* ]]; then
      hostport="${rest#\[}"
      RELAY_HOST="${hostport%%\]*}"
      if [[ "$hostport" == *"]:"* ]]; then
        RELAY_PORT="${hostport##*]:}"
      fi
    else
      RELAY_HOST="${rest%%:*}"
      if [[ "$rest" == *:* ]]; then
        RELAY_PORT="${rest##*:}"
      fi
    fi
  else
    if [[ "$v" == \[* ]]; then
      RELAY_HOST="${v#\[}"
      RELAY_HOST="${RELAY_HOST%%\]*}"
    else
      RELAY_HOST="$v"
    fi
  fi
}

collect_relay() {
  if [[ -n "$RELAY_INPUT" ]]; then
    parse_relay_value "$RELAY_INPUT"
  fi

  if [[ -z "$RELAY_HOST" ]]; then
    printf '\n%sWhere does the tunnel meet the internet?%s\n' "$BOLD" "$RESET"
    printf 'Type the domain name (recommended) or the numeric IP address of your VPS.\n'
    printf 'Example: vpn.example.com\n'
    while true; do
      ask RELAY_HOST "Relay domain or IP: " ""
      RELAY_HOST="${RELAY_HOST//[[:space:]]/}"
      if valid_host "$RELAY_HOST"; then break; fi
      warn "That is not a domain name or IPv4 address. Example: vpn.example.com or 203.0.113.10"
    done
  fi
  valid_host "$RELAY_HOST" || die "The relay host '$RELAY_HOST' is not a domain name or IPv4 address."

  # The URL in Code.gs already carries a scheme; otherwise choose a safe one.
  if [[ -z "$RELAY_SCHEME" ]]; then
    if is_ipv4 "$RELAY_HOST"; then
      RELAY_SCHEME="http"
      info "Using HTTP for a numeric IP. A domain + certificate is more private."
    else
      RELAY_SCHEME="https"
    fi
  fi
  case "$RELAY_SCHEME" in
    http | https) ;;
    *) die "Relay scheme must be http or https (got '$RELAY_SCHEME')." ;;
  esac

  if is_ipv4 "$RELAY_HOST" && [[ "$RELAY_SCHEME" == "https" ]]; then
    warn "An IP address rarely has a trusted certificate."
    warn "If the certificate is not valid, Google will refuse to forward traffic."
  fi

  if [[ "$RELAY_SCHEME" == "http" && -n "$RELAY_HOST" ]] && ! is_ipv4 "$RELAY_HOST"; then
    warn "HTTP means the hop from Google to your VPS is not TLS-protected."
    warn "The payload is still AES-256-GCM encrypted. HTTPS is still better."
    if ! confirm "Continue with HTTP for $RELAY_HOST?" no; then
      RELAY_SCHEME="https"
    fi
  fi

  if [[ -z "$RELAY_PORT" ]]; then
    RELAY_PORT="8443"
  fi
  while ! valid_port "$RELAY_PORT"; do
    warn "A port is a number from 1 to 65535 (the usual one is 8443)."
    ask RELAY_PORT "Relay port [8443]: " "8443"
  done

  if [[ "$RELAY_SCHEME" == "https" && "$RELAY_PORT" == "443" ]] ||
    [[ "$RELAY_SCHEME" == "http" && "$RELAY_PORT" == "80" ]]; then
    RELAY_BASE_URL="${RELAY_SCHEME}://${RELAY_HOST}"
  else
    RELAY_BASE_URL="${RELAY_SCHEME}://${RELAY_HOST}:${RELAY_PORT}"
  fi
  RELAY_URL="${RELAY_BASE_URL}/tunnel"
  ok "Relay URL: $RELAY_URL"

  if ((NO_HEALTH == 0)); then
    check_relay_health
  fi
}

check_relay_health() {
  local url="${RELAY_BASE_URL}/healthz" out code
  info "Checking that the relay is awake at $url"
  out="$(mktemp)"
  if code="$(curl -sS --noproxy '*' --max-time 12 -o "$out" -w '%{http_code}' "$url" 2>/dev/null)"; then
    if [[ "$code" == "200" ]]; then
      ok "Relay answered HTTP 200 (the tunnel endpoint is alive)"
      rm -f "$out"
      return 0
    fi
    warn "Relay answered HTTP $code."
    printf '  What this means: something answered, but not the healthy relay.\n' >&2
    printf '  Check the server with: sudo xrv-install.sh --check\n' >&2
  else
    warn "Could not reach $url"
    printf '  Common reasons, easiest first:\n' >&2
    printf '   1. The server is off or the tunnel is not installed yet.\n' >&2
    printf '   2. Your cloud firewall blocks TCP %s.\n' "$RELAY_PORT" >&2
    printf '   3. The domain does not point to the server yet.\n' >&2
    if [[ "$RELAY_SCHEME" == "https" ]]; then
      printf '   4. The certificate is not trusted, or the name does not match.\n' >&2
      printf '      A quick look: curl -v %s/healthz\n' "$RELAY_BASE_URL" >&2
    fi
    if ! confirm "Continue and configure the client anyway?" no; then
      die "Stopped at your request. Fix the relay, then run the installer again."
    fi
  fi
  rm -f "$out"
}

probe_edges() {
  if [[ -n "$EDGE" ]]; then
    valid_ipv4 "$EDGE" || die "The Google edge must be an IPv4 address (got '$EDGE')."
  fi
  if ((NO_PROBE == 1)); then
    EDGE="${EDGE:-$DEFAULT_EDGE}"
    info "Edge test skipped; using $EDGE"
    return 0
  fi
  if [[ -n "$EDGE" ]]; then
    valid_ipv4 "$EDGE" || die "The edge must be an IPv4 address (got '$EDGE')."
    info "Using the edge you chose: $EDGE"
    return 0
  fi
  if ! command_exists curl; then
    warn "curl is not available; using the default Google edge $DEFAULT_EDGE"
    EDGE="$DEFAULT_EDGE"
    return 0
  fi

  printf '\n%sFinding the closest Google door to your network%s\n' "$BOLD" "$RESET"
  printf 'This is not a speed test of your VPN. It only picks the fastest of four\n'
  printf 'well-known Google entry points for this network.\n'

  local ip out code seconds ms best="" best_ms=999999
  for ip in "${GOOGLE_EDGES[@]}"; do
    out="$(curl -sS --noproxy '*' -o /dev/null --max-time 6 \
      --resolve "www.google.com:443:${ip}" \
      -w '%{http_code} %{time_total}' \
      "https://www.google.com/generate_204" 2>/dev/null || true)"
    code="${out%% *}"
    if [[ "$code" == "204" ]]; then
      seconds="${out#* }"
      ms="$(awk -v t="$seconds" 'BEGIN { printf "%d", t * 1000 }')"
      printf '  %-16s %sms\n' "$ip" "$ms"
      if ((ms < best_ms)); then
        best_ms="$ms"
        best="$ip"
      fi
    else
      printf '  %-16s blocked or no answer\n' "$ip"
    fi
  done
  if [[ -n "$best" ]]; then
    EDGE="$best"
    ok "Fastest Google edge here: $EDGE (${best_ms}ms)"
  else
    EDGE="$DEFAULT_EDGE"
    warn "None of the four edges answered. Using $EDGE; the tunnel may still work."
  fi
}

# =====================================================================
# DEPLOYMENTS
# =====================================================================
add_deployment() {
  local raw="$1" account="${2:-}" id
  id="$(normalize_deployment_id "$raw")"
  if ! valid_deployment_id "$id"; then
    warn "This is not a Deployment ID: '$raw'"
    printf '  It must start with AKfycb and be about 70 characters long.\n' >&2
    printf '  In Apps Script: Deploy -> Manage deployments -> copy the Web App URL.\n' >&2
    printf '  You may paste either the long ID or the full /exec link.\n' >&2
    return 1
  fi
  if [[ -z "$account" ]]; then
    account="acct-a"
  fi
  account="${account//[[:space:]]/}"
  if ! valid_account "$account"; then
    warn "Account label must be 1-32 letters, numbers, dots, underscores or dashes."
    return 1
  fi
  local entry
  for entry in "${DEPLOYMENTS[@]}"; do
    if [[ "${entry%%|*}" == "$id" ]]; then
      warn "That Deployment ID is already in the list. Skipping the duplicate."
      return 1
    fi
  done
  DEPLOYMENTS+=("${id}|${account}")
  ok "Deployment added (${#DEPLOYMENTS[@]} total, account: $account)"
}

collect_deployments() {
  if [[ ${#DEPLOYMENTS[@]} -gt 0 ]]; then
    if [[ "$NONINTERACTIVE" == "1" ]]; then
      return 0
    fi
    info "You already gave ${#DEPLOYMENTS[@]} deployment(s). You can add more."
  fi

  printf '\n%sGoogle Apps Script deployment%s\n' "$BOLD" "$RESET"
  printf 'A Deployment ID is the long word that starts with AKfycb. Google gives it\n'
  printf 'to you after you publish the Web App. You need at least one; four across\n'
  printf 'two Google accounts give more speed and more daily quota.\n'
  printf 'Paste the ID or the full /exec link. Press Enter when finished.\n\n'

  local id account
  while true; do
    ask id "Deployment ID #$((${#DEPLOYMENTS[@]} + 1)) (or Enter to finish): " ""
    [[ -z "$id" ]] && break
    account=""
    if [[ "$id" != *"://"* && "$id" == *:* ]]; then
      account="${id##*:}"
      id="${id%:*}"
    fi
    if [[ -z "$account" ]] && [[ "$NONINTERACTIVE" != "1" ]]; then
      printf '  Which Google account is this deployment under?\n'
      printf '  Use the SAME label for deployments in the SAME account (for example acct-a).\n'
      ask account "  Account label [acct-a]: " "acct-a"
    fi
    add_deployment "$id" "$account" || true
  done
  if [[ ${#DEPLOYMENTS[@]} -eq 0 ]]; then
    die "At least one Deployment ID is required. Without it the client has nowhere to send traffic."
  fi
}

# =====================================================================
# TUNNEL KEY
# =====================================================================
collect_key() {
  if [[ -n "$TUNNEL_KEY_FILE_ARG" ]]; then
    [[ -f "$TUNNEL_KEY_FILE_ARG" ]] || die "Tunnel key file not found: $TUNNEL_KEY_FILE_ARG"
    TUNNEL_KEY="$(tr -d '[:space:]' <"$TUNNEL_KEY_FILE_ARG")"
  fi
  if [[ -n "$TUNNEL_KEY" ]]; then
    TUNNEL_KEY="${TUNNEL_KEY//[[:space:]]/}"
    TUNNEL_KEY="${TUNNEL_KEY,,}"
    valid_tunnel_key "$TUNNEL_KEY" || die "The tunnel key must be exactly 64 lowercase hex characters (0-9, a-f)."
    ok "Tunnel key accepted (64 hex characters)"
    return 0
  fi

  if [[ "$NONINTERACTIVE" == "1" ]]; then
    die "Non-interactive mode needs --tunnel-key HEX64 or --tunnel-key-file FILE."
  fi

  printf '\n%sThe tunnel key%s\n' "$BOLD" "$RESET"
  printf 'This is the only key to your tunnel. It is 64 characters: 0-9 and a-f.\n'
  printf 'Get it from the server with:  sudo cat /etc/xrv/tunnel_key\n'
  printf 'It will not be shown while you type, and it is never written to logs.\n\n'

  local key
  while true; do
    ask_secret key "Paste the tunnel key: "
    key="${key//[[:space:]]/}"
    key="${key,,}"
    if valid_tunnel_key "$key"; then
      TUNNEL_KEY="$key"
      ok "Tunnel key accepted"
      return 0
    fi
    warn "That key has ${#key} characters. It must be exactly 64 (0-9 and a-f)."
    printf '  Tip: copy the whole line, including leading and trailing characters.\n' >&2
  done
}

# =====================================================================
# LOCAL SOCKS SETTINGS
# =====================================================================
collect_socks_settings() {
  while ! valid_port "$SOCKS_PORT"; do
    warn "The local port must be a number from 1 to 65535."
    ask SOCKS_PORT "Local SOCKS port [1080]: " "1080"
  done
  if port_in_use "$SOCKS_PORT"; then
    local owners
    owners="$(port_owner_text "$SOCKS_PORT")"
    warn "Port $SOCKS_PORT is already in use${owners:+ by $owners}."
    if [[ -f "$HOME_DIR/client_config.json" ]]; then
      info "If this is your existing XRV client, use --update instead of reinstalling."
    fi
    if [[ "$NONINTERACTIVE" != "1" ]]; then
      while port_in_use "$SOCKS_PORT"; do
        ask SOCKS_PORT "Choose a different local SOCKS port: " "$((SOCKS_PORT + 1))"
        valid_port "$SOCKS_PORT" || warn "That is not a valid port."
      done
    else
      die "Local port ${SOCKS_PORT} is busy. Choose another with --socks-port."
    fi
  fi

  printf '\n%sWho may use this local proxy?%s\n' "$BOLD" "$RESET"
  printf 'Default: only this device (127.0.0.1). That is the safe choice.\n'
  if ((LAN_SHARE == 1)); then
    warn "LAN sharing is ON. Anyone on your network can spend your Google quota."
    warn "Only use this on a network you trust."
  elif [[ "$NONINTERACTIVE" != "1" ]] && confirm "Share the proxy with other devices on your home network?" no; then
    LAN_SHARE=1
    warn "Anyone on your LAN can now spend your Google quota. Only do this on a network you trust."
  fi

  printf '\n%sOptional local password%s\n' "$BOLD" "$RESET"
  printf 'Apps that use the proxy would need this username and password.\n'
  printf 'Skip it if you are the only user of this device.\n'

  if [[ -n "$SOCKS_USER" || -n "$SOCKS_PASS" ]]; then
    if [[ -z "$SOCKS_USER" || -z "$SOCKS_PASS" ]]; then
      die "socks_user and socks_pass must both be set, or both left empty."
    fi
    ok "Local SOCKS authentication enabled"
  elif [[ "$NONINTERACTIVE" != "1" ]] && confirm "Require a username and password for the local proxy?" no; then
    ask SOCKS_USER "SOCKS username [xrv]: " "xrv"
    while [[ -z "$SOCKS_USER" ]]; do
      warn "The username cannot be empty."
      ask SOCKS_USER "SOCKS username [xrv]: " "xrv"
    done
    while true; do
      ask_secret SOCKS_PASS "SOCKS password: "
      [[ -n "$SOCKS_PASS" ]] && break
      warn "The password cannot be empty."
    done
    ok "Local SOCKS authentication enabled"
  else
    SOCKS_USER=""
    SOCKS_PASS=""
  fi
}

# =====================================================================
# CONFIG / SCRIPTS
# =====================================================================
compute_idle_slots() {
  local entry account
  local -A counts=()
  for entry in "${DEPLOYMENTS[@]}"; do
    account="${entry#*|}"
    counts["$account"]=$((${counts["$account"]:-0} + 1))
  done
  local max=1 c
  for c in "${counts[@]}"; do
    if ((c >= 3)); then
      max=3
    elif ((c == 2 && max < 2)); then
      max=2
    fi
  done
  IDLE_SLOTS="$max"
}

write_client_config() {
  install -d -m 700 "$HOME_DIR"
  local tmp entry id account socks_host escaped_user escaped_pass
  tmp="$(mktemp "${HOME_DIR}/.client_config.XXXXXX")"
  if ((LAN_SHARE == 1)); then socks_host="0.0.0.0"; else socks_host="127.0.0.1"; fi
  escaped_user="$(json_escape "$SOCKS_USER")"
  escaped_pass="$(json_escape "$SOCKS_PASS")"

  {
    printf '{\n'
    printf '  "debug_timing": false,\n'
    printf '  "socks_host": "%s",\n' "$socks_host"
    printf '  "socks_port": %s,\n' "$SOCKS_PORT"
    printf '  "google_host": "%s",\n' "${EDGE:-$DEFAULT_EDGE}"
    printf '  "sni": ["www.google.com", "mail.google.com", "accounts.google.com"],\n'
    printf '  "script_keys": [\n'
    local i=0
    for entry in "${DEPLOYMENTS[@]}"; do
      id="${entry%%|*}"
      account="${entry#*|}"
      i=$((i + 1))
      printf '    {"id": "%s", "account": "%s"}%s\n' "$id" "$account" \
        "$([[ $i -lt ${#DEPLOYMENTS[@]} ]] && printf ',')"
    done
    printf '  ],\n'
    printf '  "tunnel_key": "%s",\n' "$TUNNEL_KEY"
    printf '  "socks_user": "%s",\n' "$escaped_user"
    printf '  "socks_pass": "%s",\n' "$escaped_pass"
    printf '  "coalesce_step_ms": %s,\n' "$COALESCE_MS"
    printf '  "idle_slots_per_bucket": %s\n' "$IDLE_SLOTS"
    printf '}\n'
  } >"$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "${HOME_DIR}/client_config.json"
  chmod 600 "${HOME_DIR}/client_config.json"
  ok "Config written: ${HOME_DIR}/client_config.json (mode 600)"
}

validate_written_config() {
  local cfg="${HOME_DIR}/client_config.json"
  [[ -f "$cfg" ]] || die "Config file was not written: $cfg"
  if command_exists python3; then
    python3 - "$cfg" <<'PY' || die "The generated config is not valid JSON. This is an installer bug."
import json, re, sys
with open(sys.argv[1]) as f:
    c = json.load(f)
assert isinstance(c.get("socks_port"), int) and 1 <= c["socks_port"] <= 65535
assert re.fullmatch(r"[0-9a-f]{64}", c.get("tunnel_key", ""))
assert isinstance(c.get("script_keys"), list) and c["script_keys"]
for k in c["script_keys"]:
    assert re.fullmatch(r"AKfycb[A-Za-z0-9_-]{44,}", k.get("id", "")), "bad deployment id"
    assert isinstance(k.get("account"), str)
assert c.get("coalesce_step_ms", 0) >= 0
assert 0 <= c.get("idle_slots_per_bucket", 0) <= 3
PY
    ok "Config JSON and values validated"
    return 0
  fi
  grep -q '"tunnel_key": "[0-9a-f]\{64\}"' "$cfg" || die "Tunnel key missing from the generated config."
  grep -q '"id": "AKfycb' "$cfg" || die "Deployment ID missing from the generated config."
  ok "Config basic checks passed (install python3 for deeper validation)"
}

write_code_gs() {
  local dest="${HOME_DIR}/Code.gs"
  cat >"$dest" <<'CODE_EOF'
// XRV GooseRelay forwarder — paste this into https://script.google.com
// Deploy as: Execute as Me  |  Who has access: Anyone
// This file is generated by the XRV client installer. Keep it private.

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
  sed -i "s|RELAY_URL_PLACEHOLDER|${RELAY_URL}|" "$dest"
  chmod 644 "$dest"
  ok "Apps Script file written: $dest"
}

write_start_script() {
  cat >"${HOME_DIR}/start-xrv.sh" <<'START_EOF'
#!/usr/bin/env bash
# XRV client start script. Finds its own folder, so it works from anywhere.
set -Eeuo pipefail
cd -- "$(dirname -- "$0")" || exit 1
umask 077

LOG="xrv-client.log"
PIDFILE="xrv-client.pid"
PORT="$(sed -n 's/.*"socks_port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' client_config.json 2>/dev/null | head -n1)"
PORT="${PORT:-1080}"

if [[ -f "$PIDFILE" ]]; then
  oldpid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
    echo "XRV is already running (PID $oldpid). Use ./stop-xrv.sh first to restart."
    exit 0
  fi
  rm -f "$PIDFILE"
fi

if [[ ! -x ./goose-client ]]; then
  echo "The program ./goose-client is missing or not executable."
  echo "Fix: run the installer again (xrv-client.sh)."
  exit 1
fi

# Another full-device VPN must not capture the traffic first. This check is
# skipped on Termux where the 'ip' tool usually does not exist.
if [[ -z "${TERMUX_VERSION:-}" ]] && command -v ip >/dev/null 2>&1 &&
   ip link show singbox_tun >/dev/null 2>&1; then
  echo ""
  echo "Another VPN (v2rayN / sing-box TUN mode) is capturing ALL traffic."
  echo "Two tunnels at once cause connection resets. Turn that VPN off first."
  echo ""
  while true; do
    read -r -p "Turn it off, then press Enter to check again: " _ || exit 1
    if ! ip link show singbox_tun >/dev/null 2>&1; then break; fi
    echo "Still on. Turn it off, then press Enter."
  done
fi

if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":${PORT} "; then
  echo ""
  echo "Local port ${PORT} is already busy, so XRV cannot start."
  echo "Run ./stop-xrv.sh first, or change socks_port in client_config.json."
  ss -ltnp 2>/dev/null | grep ":${PORT} " || true
  exit 1
fi

command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true
ulimit -n 65536 2>/dev/null || true

echo "=== started $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" >>"$LOG"
echo "Starting XRV..."
echo "  Local SOCKS5: socks5://127.0.0.1:${PORT}  (127.0.0.1 is replaced by 0.0.0.0 if LAN sharing is on)"
echo "  Wait for: pre-flight OK, then: ready: local SOCKS5 is listening"
echo "  Log file: $PWD/$LOG"
echo "  Stop with Ctrl+C or ./stop-xrv.sh"
echo ""

./goose-client -config client_config.json > >(tee -a "$LOG") 2>&1 &
pid=$!
echo "$pid" >"$PIDFILE"
cleanup() {
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$PIDFILE"
  command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock || true
  exit 130
}
trap cleanup INT TERM

rc=0
wait "$pid" || rc=$?
rm -f "$PIDFILE"
command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock || true
echo "XRV stopped (exit $rc)."
exit "$rc"
START_EOF
  chmod 755 "${HOME_DIR}/start-xrv.sh"
}

write_stop_script() {
  cat >"${HOME_DIR}/stop-xrv.sh" <<'STOP_EOF'
#!/usr/bin/env bash
# Stop the XRV client safely. It only kills the process it started.
set -u
cd -- "$(dirname -- "$0")" || exit 1
PIDFILE="xrv-client.pid"

if [[ ! -f "$PIDFILE" ]]; then
  echo "XRV is not running (no PID file)."
  exit 0
fi
pid="$(cat "$PIDFILE" 2>/dev/null || true)"
if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
  rm -f "$PIDFILE"
  echo "XRV is not running (stale PID file removed)."
  exit 0
fi
cmd="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
case "$cmd" in
  *goose-client*) ;;
  *)
    echo "PID $pid is not goose-client. Refusing to kill it."
    exit 1
    ;;
esac
kill -TERM "$pid" 2>/dev/null || true
for _ in {1..50}; do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.2
done
if kill -0 "$pid" 2>/dev/null; then
  echo "The client did not stop in time; forcing it."
  kill -KILL "$pid" 2>/dev/null || true
fi
rm -f "$PIDFILE"
command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock || true
echo "XRV stopped."
STOP_EOF
  chmod 755 "${HOME_DIR}/stop-xrv.sh"
}

write_status_script() {
  cat >"${HOME_DIR}/status-xrv.sh" <<'STATUS_EOF'
#!/usr/bin/env bash
# Show whether the XRV client is running and what the log says.
set -u
cd -- "$(dirname -- "$0")" || exit 1
port="$(sed -n 's/.*"socks_port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' client_config.json 2>/dev/null | head -n1)"
port="${port:-1080}"
if [[ -f xrv-client.pid ]]; then
  pid="$(cat xrv-client.pid 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "XRV is running (PID $pid), local SOCKS5 port ${port}."
  else
    echo "XRV is not running (stale PID file)."
  fi
else
  echo "XRV is not running."
fi
if command -v ss >/dev/null 2>&1; then
  ss -ltn 2>/dev/null | grep ":${port} " || true
fi
echo ""
echo "Last 15 log lines:"
tail -n 15 xrv-client.log 2>/dev/null || echo "  (no log yet)"
STATUS_EOF
  chmod 755 "${HOME_DIR}/status-xrv.sh"
}

write_guide() {
  local platform_note
  if ((IS_TERMUX == 1)); then
    platform_note="Android / Termux"
  else
    platform_note="Linux"
  fi
  cat >"${HOME_DIR}/GUIDE.txt" <<GUIDE_EOF
XRV — QUICK GUIDE (keep this file)
==================================
Platform: ${platform_note}
Relay:    ${RELAY_URL}
Proxy:    socks5://127.0.0.1:${SOCKS_PORT}

WHAT THIS IS
------------
A private tunnel that carries your traffic inside ordinary Google HTTPS.
Apps on this device talk to 127.0.0.1:${SOCKS_PORT}. The client encrypts the
traffic and sends it through Google to your own VPS. Your tunnel key never
goes to Google.

DAILY USE
---------
START:  ./start-xrv.sh
STOP:   ./stop-xrv.sh   (or Ctrl+C in the start window)
STATUS: ./status-xrv.sh
CHECK:  ./xrv-client.sh --check   (or re-run the installer with --check)

BROWSER / APPS
--------------
Firefox:
  Settings -> Network Settings -> Settings...
  Manual proxy -> SOCKS Host: 127.0.0.1   Port: ${SOCKS_PORT}
  SOCKS v5 + "Proxy DNS when using SOCKS v5" -> OK

Android (NekoBox / v2rayNG):
  Add a SOCKS5 server: 127.0.0.1 : ${SOCKS_PORT}
  EXCLUDE Termux from the proxy, otherwise Termux cannot keep the tunnel up.

TEST IT
-------
  curl --socks5-hostname 127.0.0.1:${SOCKS_PORT} https://api.ipify.org
The answer must be your VPS IP, not your real IP.

LOGS
----
  ${HOME_DIR}/xrv-client.log
  ${LOG_FILE}

SECURITY
--------
  • client_config.json contains the tunnel key. Never share it.
  • If the key leaks, rotate it on the server and update every client.
  • Deployment IDs are masked in logs.
  • One VPN at a time: turn off other TUN/TAP VPNs before starting XRV.

IF SOMETHING FAILS
------------------
  ./status-xrv.sh
  tail -n 50 xrv-client.log
  Then run: ./xrv-client.sh --check
Every error line in this project says what failed and what to do next.
GUIDE_EOF
  chmod 644 "${HOME_DIR}/GUIDE.txt"
}

write_state() {
  local tmp
  tmp="$(mktemp "${HOME_DIR}/.state.XXXXXX")"
  {
    printf 'RELAY_URL=%q\n' "$RELAY_URL"
    printf 'PLATFORM=%q\n' "$PLATFORM"
    printf 'SOCKS_PORT=%q\n' "$SOCKS_PORT"
    printf 'INSTALLED_AT=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "${HOME_DIR}/.xrv-state"
}

# =====================================================================
# BINARY INSTALL
# =====================================================================
verify_binary_arch() {
  local file="$1" expected="$2"
  ((SKIP_ARCH == 1)) && return 0
  command_exists file || {
    info "The 'file' tool is absent; skipping architecture display."
    return 0
  }
  local out
  out="$(file -b "$file" 2>/dev/null || true)"
  case "$expected" in
    linux-amd64) [[ "$out" == *"x86-64"* ]] || {
      error "Expected an x86-64 binary, found: $out"
      return 1
    } ;;
    linux-arm64 | android-arm64) [[ "$out" == *"aarch64"* || "$out" == *"ARM aarch64"* ]] || {
      error "Expected an arm64 binary, found: $out"
      return 1
    } ;;
  esac
  ok "Binary architecture verified: $expected"
}

install_binary() {
  local workdir tarball binary version
  install -d -m 700 "$HOME_DIR"

  if [[ -n "$OFFLINE_BINARY" ]]; then
    [[ -f "$OFFLINE_BINARY" ]] || die "Offline binary not found: $OFFLINE_BINARY"
    binary="$OFFLINE_BINARY"
    info "Using the local binary you supplied: $binary"
  else
    ensure_download_tools
    workdir="$(mktemp -d "${TMPDIR:-/tmp}/xrv.XXXXXX")"
    tarball="${workdir}/client.tar.gz"
    info "Downloading the official client for $PLATFORM"
    download_file "$PLATFORM_URL" "$tarball" "$PLATFORM_SHA" "GooseRelayVPN client"
    safe_extract_tar "$tarball" "$workdir"
    binary="$(find "$workdir" -maxdepth 3 -type f -name 'goose-client' -print -quit)"
    [[ -n "$binary" ]] || die "The release archive does not contain goose-client. Nothing was installed."
  fi

  verify_binary_arch "$binary" "$PLATFORM" || die "Wrong architecture. Nothing was installed."

  if command_exists timeout; then
    if ! version="$(timeout 5 "$binary" -version 2>/dev/null | head -n1)"; then
      error "The downloaded program cannot run on this device."
      printf '  This usually means the archive is for a different CPU or OS.\n' >&2
      printf '  Platform chosen: %s\n' "$PLATFORM" >&2
      if ((SKIP_ARCH == 1)); then
        warn "Architecture check was skipped, so the copy will continue."
      else
        die "Refusing to install a program that cannot start."
      fi
    fi
  fi

  if [[ -f "${HOME_DIR}/goose-client" ]]; then
    cp -a "${HOME_DIR}/goose-client" "${HOME_DIR}/goose-client.bak.$(date +%Y%m%d-%H%M%S)" || true
  fi
  install -m 755 "$binary" "${HOME_DIR}/goose-client"
  [[ -n "${workdir:-}" ]] && rm -rf "$workdir"
  ok "Installed client binary${version:+ ($version)}"
}

# =====================================================================
# SYSTEMD USER SERVICE (optional, Linux)
# =====================================================================
install_user_service() {
  ((IS_LINUX == 1)) || {
    warn "Automatic start is available on Linux only; skipping on Termux."
    return 0
  }
  command_exists systemctl || {
    warn "systemd is not available; skipping the automatic-start service."
    return 0
  }

  local unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  local unit="${unit_dir}/xrv-client.service"
  install -d -m 700 "$unit_dir"
  cat >"$unit" <<EOF
[Unit]
Description=XRV GooseRelayVPN SOCKS5 client
Documentation=${XRV_PROJECT}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${HOME_DIR}
ExecStart=${HOME_DIR}/goose-client -config ${HOME_DIR}/client_config.json
Restart=on-failure
RestartSec=3s
UMask=0077
LimitNOFILE=65536
StandardOutput=append:${HOME_DIR}/xrv-client.log
StandardError=append:${HOME_DIR}/xrv-client.log

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${HOME_DIR}
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
CapabilityBoundingSet=

[Install]
WantedBy=default.target
EOF
  chmod 600 "$unit"
  if systemctl --user daemon-reload 2>/dev/null && systemctl --user enable --now xrv-client 2>/dev/null; then
    ok "Automatic start enabled (systemd user service)"
    if command_exists loginctl; then
      info "To keep it running after logout, run once: loginctl enable-linger $USER"
    fi
  else
    warn "Could not enable the user service (no user systemd session?)."
    printf '  The client still works; start it with: %s/start-xrv.sh\n' "$HOME_DIR" >&2
    printf '  To enable it later: systemctl --user enable --now xrv-client\n' >&2
  fi
}

remove_user_service() {
  local unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/xrv-client.service"
  if command_exists systemctl; then
    systemctl --user disable --now xrv-client 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
  fi
  rm -f "$unit"
}

# =====================================================================
# START / STOP
# =====================================================================
start_now() {
  if ((NO_START == 1)); then
    return 0
  fi
  local do_start=1
  if [[ "$NONINTERACTIVE" != "1" ]]; then
    confirm "Start the tunnel now?" yes || do_start=0
  fi
  ((do_start == 1)) || return 0

  info "Starting the client in the background"
  nohup bash "${HOME_DIR}/start-xrv.sh" >/dev/null 2>&1 &
  local i ready=0
  for i in {1..25}; do
    if port_in_use "$SOCKS_PORT"; then
      ready=1
      break
    fi
    sleep 1
  done
  if ((ready == 1)); then
    ok "The local proxy is listening on port $SOCKS_PORT"
    printf '  Try: curl --socks5-hostname 127.0.0.1:%s https://api.ipify.org\n' "$SOCKS_PORT"
    printf '  It should print your VPS IP.\n'
  else
    warn "The proxy did not open within 25 seconds."
    printf '  Last log lines:\n' >&2
    tail -n 25 "${HOME_DIR}/xrv-client.log" 2>/dev/null | sed 's/^/    /' >&2 || true
    printf '  Start it yourself to watch the live messages: %s/start-xrv.sh\n' "$HOME_DIR" >&2
  fi
}

stop_client_if_running() {
  if [[ -x "${HOME_DIR}/stop-xrv.sh" ]]; then
    bash "${HOME_DIR}/stop-xrv.sh" >/dev/null 2>&1 || true
  fi
}

# =====================================================================
# DOCTOR
# =====================================================================
DOCTOR_FAILS=0
DOCTOR_WARNS=0
d_pass() { printf '%s %s[OK]%s %s %s\n' "$CHECK" "$GREEN" "$RESET" "$1" "${2:-}"; }
d_warn() {
  printf '%s %s[WARN]%s %s %s\n' "$WARN" "$YELLOW" "$RESET" "$1" "${2:-}"
  DOCTOR_WARNS=$((DOCTOR_WARNS + 1))
}
d_fail() {
  printf '%s %s[FAIL]%s %s %s\n' "$CROSS" "$RED" "$RESET" "$1" "${2:-}"
  DOCTOR_FAILS=$((DOCTOR_FAILS + 1))
}

doctor_flow() {
  banner
  printf '\n%sXRV client doctor%s\n' "$BOLD" "$RESET"
  printf 'Each line is one check and what we found.\n'

  local cfg="${HOME_DIR}/client_config.json"
  if [[ ! -f "$cfg" ]]; then
    d_fail "Config" "missing at $cfg"
    error "No client is installed here. Run: bash xrv-client.sh"
    return 1
  fi
  d_pass "Config" "$cfg"

  local mode
  mode="$(file_mode "$cfg")"
  if [[ "$mode" == "600" ]]; then
    d_pass "Config permissions" "600 (only you can read it)"
  else
    d_fail "Config permissions" "$mode; run: chmod 600 $cfg"
  fi

  if grep -q '"tunnel_key": "[0-9a-f]\{64\}"' "$cfg"; then
    d_pass "Tunnel key" "64 lowercase hex characters"
  else
    d_fail "Tunnel key" "missing or not 64 lowercase hex characters"
  fi

  local dep_count
  dep_count="$(grep -c '"id": "AKfycb' "$cfg" 2>/dev/null || true)"
  if [[ "$dep_count" =~ ^[0-9]+$ ]] && ((dep_count >= 1)); then
    d_pass "Deployments" "$dep_count configured"
  else
    d_fail "Deployments" "no valid AKfycb deployment ID found"
  fi

  if [[ -x "${HOME_DIR}/goose-client" ]]; then
    local ver
    ver="$(timeout 5 "${HOME_DIR}/goose-client" -version 2>/dev/null | head -n1 || true)"
    d_pass "Client binary" "${ver:-present}"
  else
    d_fail "Client binary" "missing or not executable at ${HOME_DIR}/goose-client"
  fi

  local port
  port="$(sed -n 's/.*"socks_port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$cfg" | head -n1)"
  port="${port:-1080}"
  if command_exists ss; then
    if ss -ltn 2>/dev/null | grep -q ":${port} "; then
      d_pass "Local proxy" "port $port is listening"
    else
      d_warn "Local proxy" "port $port is not listening; start with ${HOME_DIR}/start-xrv.sh"
    fi
  fi

  if [[ -f "${HOME_DIR}/xrv-client.pid" ]] && kill -0 "$(cat "${HOME_DIR}/xrv-client.pid" 2>/dev/null)" 2>/dev/null; then
    d_pass "Process" "running (PID $(cat "${HOME_DIR}/xrv-client.pid"))"
  else
    d_warn "Process" "not running"
  fi

  if [[ -f "${HOME_DIR}/.xrv-state" ]]; then
    # shellcheck disable=SC1091
    source "${HOME_DIR}/.xrv-state"
  fi
  if [[ -n "${RELAY_URL:-}" ]]; then
    local base="${RELAY_URL%/tunnel}"
    if curl -fsS --noproxy '*' --max-time 12 "${base}/healthz" >/dev/null 2>&1; then
      d_pass "Relay health" "${base}/healthz"
    else
      d_fail "Relay health" "${base}/healthz did not answer (server off, firewall, DNS, or certificate)"
    fi
    if [[ "$base" == https://* ]]; then
      local hostport host
      hostport="${base#https://}"
      host="${hostport%%:*}"
      if command_exists openssl; then
        local out rport
        rport="${hostport##*:}"
        [[ "$hostport" == *:* && "$rport" =~ ^[0-9]+$ ]] || rport=443
        out="$(echo | timeout 10 openssl s_client -connect "${host}:${rport}" \
          -servername "$host" -verify_return_error -CAfile /etc/ssl/certs/ca-certificates.crt 2>&1 || true)"
        if grep -q "Verify return code: 0 (ok)" <<<"$out"; then
          d_pass "Relay certificate" "trusted and matches $host"
        else
          d_fail "Relay certificate" "not trusted or name mismatch; fix it on the server"
        fi
        if grep -q "TLSv1.3" <<<"$out"; then
          d_pass "Relay TLS version" "TLS 1.3"
        else
          d_warn "Relay TLS version" "TLS 1.3 was not visible"
        fi
      fi
    fi
  else
    d_warn "Relay state" "no saved relay URL; run the installer again to record it"
  fi

  if command_exists curl && port_in_use "$port"; then
    local exit_ip real_ip socks_user socks_pass
    socks_user="$(sed -n 's/.*"socks_user"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" | head -n1)"
    socks_pass="$(sed -n 's/.*"socks_pass"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cfg" | head -n1)"
    local -a curl_socks=(--socks5-hostname "127.0.0.1:${port}")
    if [[ -n "$socks_user" ]]; then
      curl_socks+=(--proxy-user "${socks_user}:${socks_pass}")
    fi
    exit_ip="$(curl -s --noproxy '*' --max-time 15 "${curl_socks[@]}" https://api.ipify.org 2>/dev/null || true)"
    if [[ -n "$exit_ip" ]]; then
      d_pass "Live SOCKS test" "exit IP $exit_ip"
      real_ip="$(curl -s --noproxy '*' --max-time 8 https://api.ipify.org 2>/dev/null || true)"
      if [[ -n "$real_ip" && "$exit_ip" == "$real_ip" ]]; then
        d_warn "Exit IP" "same as your real IP; the tunnel may not be carrying traffic"
      elif [[ -n "$real_ip" ]]; then
        d_pass "Traffic path" "real IP $real_ip -> tunnel IP $exit_ip"
      fi
    else
      d_fail "Live SOCKS test" "the port is open but the tunnel did not answer"
    fi
  fi

  if [[ -f "${HOME_DIR}/xrv-client.log" ]] && grep -qiE 'error|failed|fatal' "${HOME_DIR}/xrv-client.log"; then
    d_warn "Log" "contains error/failed lines; tail -n 50 ${HOME_DIR}/xrv-client.log"
  else
    d_pass "Log" "no obvious errors in ${HOME_DIR}/xrv-client.log"
  fi

  printf '\n%sVerdict%s\n' "$BOLD" "$RESET"
  if ((DOCTOR_FAILS == 0)); then
    if ((DOCTOR_WARNS > 0)); then
      ok "Everything critical passed ($DOCTOR_WARNS warning(s) to review)."
    else
      ok "Everything critical passed."
    fi
    return 0
  fi
  error "$DOCTOR_FAILS critical check(s) failed. Fix the FAIL lines first."
  return 1
}

file_mode() { stat -c '%a' "$1" 2>/dev/null || printf 'unknown'; }

# =====================================================================
# UPDATE / UNINSTALL
# =====================================================================
update_flow() {
  banner
  printf '\n%sUpdate the XRV client binary%s\n' "$BOLD" "$RESET"
  [[ -f "${HOME_DIR}/client_config.json" ]] || die "No client found at $HOME_DIR. Run the installer first."
  if [[ -f "${HOME_DIR}/.xrv-state" ]]; then
    # shellcheck disable=SC1091
    source "${HOME_DIR}/.xrv-state"
  fi
  local stored_port
  stored_port="$(sed -n 's/.*"socks_port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "${HOME_DIR}/client_config.json" | head -n1)"
  [[ -n "$stored_port" ]] && SOCKS_PORT="$stored_port"
  detect_platform
  install_binary
  write_state
  if [[ -x "${HOME_DIR}/stop-xrv.sh" ]]; then
    info "Restart the client to use the new binary: ${HOME_DIR}/stop-xrv.sh && ${HOME_DIR}/start-xrv.sh"
  fi
  ok "Update finished. Your config and tunnel key were not changed."
}

uninstall_flow() {
  banner
  printf '\n%sRemove XRV from this device%s\n' "$BOLD" "$RESET"
  if [[ ! -f "$HOME_DIR/client_config.json" && ! -f "$HOME_DIR/.xrv-state" ]]; then
    die "Refusing to remove '$HOME_DIR': it does not look like an XRV install folder."
  fi
  confirm "Stop the client and remove the program files?" || return 0
  stop_client_if_running
  remove_user_service
  rm -f "${HOME_DIR}/goose-client" "${HOME_DIR}"/goose-client.bak.* \
    "${HOME_DIR}/start-xrv.sh" "${HOME_DIR}/stop-xrv.sh" \
    "${HOME_DIR}/status-xrv.sh" "${HOME_DIR}/GUIDE.txt" "${HOME_DIR}/Code.gs" \
    "${HOME_DIR}/xrv-client.log" "${HOME_DIR}/xrv-client.pid"
  if ((PURGE == 1)) || confirm "Delete client_config.json and the tunnel key too?" no; then
    rm -f "${HOME_DIR}/client_config.json" "${HOME_DIR}/.xrv-state"
    rm -rf "${HOME_DIR}"
    rm -rf "${HOME}/.xrv"
    ok "Everything was removed, including the tunnel key."
  else
    ok "Program removed. Config and key were kept in $HOME_DIR."
  fi
}

# =====================================================================
# MAIN
# =====================================================================
usage() {
  cat <<'HELP_EOF'
XRV v1.1.0 — standalone GooseRelayVPN client installer
Linux amd64 · Linux arm64 · Android Termux arm64

USAGE
  bash xrv-client.sh                  interactive installation
  bash xrv-client.sh --check          full health check
  bash xrv-client.sh --update         replace the binary, keep the config
  bash xrv-client.sh --uninstall      remove the client

OPTIONS
  --relay HOST|URL       relay domain, IP, or full https://host:port/tunnel URL
  --relay-host HOST      relay domain or IP
  --relay-port PORT      relay port (default 8443)
  --relay-scheme http|https
  --deployment ID[:ACCT] one deployment ID (repeat for more)
  --deployments LIST     comma-separated IDs (ID:ACCT, ID:ACCT)
  --tunnel-key HEX64     the 64-character server key
  --tunnel-key-file FILE read the key from a file
  --socks-port PORT      local SOCKS5 port (default 1080)
  --socks-user USER      optional local SOCKS username
  --socks-pass PASS      optional local SOCKS password
  --lan                  allow other devices on the LAN (danger: shares quota)
  --coalesce-ms MS       uplink batching delay, 0-1000 (default 25)
  --edge IP              force a Google edge IPv4
  --home DIR             install directory (default ~/xrv)
  --proxy URL            proxy used only for downloads
  --platform NAME        android-arm64, linux-amd64 or linux-arm64
  --offline-binary FILE  use a local goose-client (air-gapped/testing)
  --no-probe             skip the Google edge test
  --no-health            skip the relay health check
  --no-start             do not start the client at the end
  --service              install a systemd user service (Linux)
  --skip-arch-check      skip the CPU architecture check (testing only)
  --yes                  answer yes to confirmations
  --non-interactive      never prompt; required values must be supplied
  --purge                with --uninstall, delete the config and key too
  --help                 show this help
  --version              show the version

SAFETY
  • The client archive is checked against a pinned SHA-256 before running.
  • The tunnel key is hidden while typing and never written to logs.
  • The config is written with mode 600, readable only by you.
  • Re-running an update keeps your existing config and key.

GET THE TUNNEL KEY FROM THE SERVER
  sudo cat /etc/xrv/tunnel_key

PROJECT
  https://github.com/Kianmhz/GooseRelayVPN
HELP_EOF
}

main() {
  local p entry acct SELF_CMD="xrv-client.sh"
  while (($# > 0)); do
    case "$1" in
      --help | -h)
        usage
        return 0
        ;;
      --version | -V)
        printf 'XRV client %s\n' "$XRV_VERSION"
        return 0
        ;;
      --relay)
        shift || die "--relay needs a value"
        RELAY_INPUT="$1"
        ;;
      --relay-host)
        shift || die "--relay-host needs a value"
        RELAY_HOST="$1"
        ;;
      --relay-port)
        shift || die "--relay-port needs a value"
        RELAY_PORT="$1"
        ;;
      --relay-scheme)
        shift || die "--relay-scheme needs a value"
        RELAY_SCHEME="$1"
        ;;
      --deployment | --deployment-id)
        shift || die "--deployment needs a value"
        DEPLOYMENTS+=("$1")
        ;;
      --deployments)
        shift || die "--deployments needs a value"
        IFS=',' read -r -a parts <<<"$1"
        for p in "${parts[@]}"; do [[ -n "$p" ]] && DEPLOYMENTS+=("$p"); done
        ;;
      --tunnel-key)
        shift || die "--tunnel-key needs a value"
        TUNNEL_KEY="$1"
        ;;
      --tunnel-key-file)
        shift || die "--tunnel-key-file needs a value"
        TUNNEL_KEY_FILE_ARG="$1"
        ;;
      --socks-port)
        shift || die "--socks-port needs a value"
        SOCKS_PORT="$1"
        ;;
      --socks-user)
        shift || die "--socks-user needs a value"
        SOCKS_USER="$1"
        ;;
      --socks-pass)
        shift || die "--socks-pass needs a value"
        SOCKS_PASS="$1"
        ;;
      --lan) LAN_SHARE=1 ;;
      --coalesce-ms)
        shift || die "--coalesce-ms needs a value"
        COALESCE_MS="$1"
        ;;
      --edge)
        shift || die "--edge needs a value"
        EDGE="$1"
        ;;
      --home)
        shift || die "--home needs a value"
        HOME_DIR="$1"
        ;;
      --proxy)
        shift || die "--proxy needs a value"
        DOWNLOAD_PROXY="$1"
        ;;
      --platform)
        shift || die "--platform needs a value"
        XRV_PLATFORM="$1"
        ;;
      --offline-binary)
        shift || die "--offline-binary needs a value"
        OFFLINE_BINARY="$1"
        ;;
      --no-probe) NO_PROBE=1 ;;
      --no-health) NO_HEALTH=1 ;;
      --no-start) NO_START=1 ;;
      --service)
        INSTALL_SERVICE=1
        SERVICE_EXPLICIT=1
        ;;
      --no-service)
        INSTALL_SERVICE=0
        SERVICE_EXPLICIT=1
        ;;
      --skip-arch-check) SKIP_ARCH=1 ;;
      --yes | -y) ASSUME_YES=1 ;;
      --non-interactive) NONINTERACTIVE=1 ;;
      --check | --doctor) DO_CHECK=1 ;;
      --update) DO_UPDATE=1 ;;
      --uninstall) DO_UNINSTALL=1 ;;
      --purge) PURGE=1 ;;
      --)
        shift
        break
        ;;
      -*) die "Unknown option: $1 (try --help)" ;;
      *) die "Unexpected argument: $1 (try --help)" ;;
    esac
    shift
  done

  init_log

  if [[ "$EUID" -eq 0 ]]; then
    warn "You are running the client as root. It works, but a normal user account is safer."
  fi
  if [[ "$HOME_DIR" == "~"* ]]; then
    HOME_DIR="${HOME}${HOME_DIR#\~}"
  fi
  if [[ -z "$HOME_DIR" ]]; then
    die "HOME is not set. Set it, or pass --home DIR."
  fi
  HOME_DIR="${HOME_DIR%/}"
  case "$HOME_DIR" in
    "" | "/" | "$HOME")
      die "Refusing to use '$HOME_DIR' as the install folder. Pass --home DIR."
      ;;
  esac
  [[ "$HOME_DIR" == /* ]] || die "The install folder must be an absolute path (got '$HOME_DIR')."
  [[ "${HOME_DIR#/}" == */* ]] || die "Refusing a top-level install folder ('$HOME_DIR'). Use something like ~/xrv."

  if ((DO_CHECK == 1)); then
    if doctor_flow; then
      return 0
    fi
    return 1
  fi
  if ((DO_UNINSTALL == 1)); then
    uninstall_flow
    return 0
  fi
  if ((DO_UPDATE == 1)); then
    update_flow
    return 0
  fi

  banner
  detect_platform
  ensure_download_tools

  if [[ -f "${BASH_SOURCE[0]}" && "${BASH_SOURCE[0]}" != /dev/fd/* ]]; then
    SELF_CMD="${BASH_SOURCE[0]}"
  else
    SELF_CMD="xrv-client.sh"
  fi

  step "Relay"
  collect_relay

  step "Deployments"
  # Convert CLI entries into the validated list.
  if [[ ${#DEPLOYMENTS[@]} -gt 0 ]]; then
    local -a raw=("${DEPLOYMENTS[@]}")
    DEPLOYMENTS=()
    for entry in "${raw[@]}"; do
      acct=""
      if [[ "$entry" != *"://"* && "$entry" == *:* ]]; then
        acct="${entry##*:}"
        entry="${entry%:*}"
      fi
      add_deployment "$entry" "$acct" || die "Fix the deployment ID above, then run the installer again."
    done
  fi
  collect_deployments

  step "Tunnel key"
  collect_key

  step "Local proxy settings"
  # Validate coalescing before using it.
  [[ "$COALESCE_MS" =~ ^[0-9]+$ ]] && ((COALESCE_MS <= 1000)) || die "--coalesce-ms must be a number from 0 to 1000."
  collect_socks_settings
  compute_idle_slots

  step "Finding the fastest Google edge"
  probe_edges

  step "Installing the client binary"
  install_binary

  step "Writing configuration"
  write_client_config
  validate_written_config
  write_code_gs
  write_start_script
  write_stop_script
  write_status_script
  write_guide
  write_state

  if ((INSTALL_SERVICE == 1)); then
    step "Enabling automatic start"
    install_user_service
  elif ((SERVICE_EXPLICIT == 0)) && ((IS_LINUX == 1)) && [[ "$NONINTERACTIVE" != "1" ]]; then
    if confirm "Start the tunnel automatically when you log in?" no; then
      install_user_service
    fi
  fi

  step "Starting"
  start_now

  # Keep the key out of the summary on purpose.
  printf '\n%s%sClient installation complete%s\n' "$BOLD" "$GREEN" "$RESET"
  printf '  Folder      : %s\n' "$HOME_DIR"
  printf '  Config      : %s (mode 600)\n' "${HOME_DIR}/client_config.json"
  printf '  Apps Script : %s\n' "${HOME_DIR}/Code.gs"
  printf '  Guide       : %s\n' "${HOME_DIR}/GUIDE.txt"
  printf '  Log         : %s\n' "${HOME_DIR}/xrv-client.log"
  printf '  Proxy       : socks5://127.0.0.1:%s\n' "$SOCKS_PORT"
  printf '  Installer   : https://github.com/%s\n' "$XRV_REPO"
  printf '\n%sUseful commands%s\n' "$BOLD" "$RESET"
  printf '  %s/start-xrv.sh\n' "$HOME_DIR"
  printf '  %s/stop-xrv.sh\n' "$HOME_DIR"
  printf '  %s/status-xrv.sh\n' "$HOME_DIR"
  printf '  bash %s --check\n' "$SELF_CMD"
  printf '\n%sNext%s\n' "$BOLD" "$RESET"
  printf '  Open %s, paste it into a new Apps Script project, deploy it as\n' "${HOME_DIR}/Code.gs"
  printf '  a Web App (Execute as Me, access Anyone), then take the Deployment ID\n'
  printf '  and add it with: bash %s --deployment AKfycb...\n' "$SELF_CMD"
  printf '  Never share client_config.json: it contains the only tunnel key.\n'
}

if [[ "${XRV_LIB_ONLY:-0}" == "1" ]]; then
  return 0
fi

main "$@"
