#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Shared test helpers. Sourced, not executed.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
PASS=0
FAIL=0

t_ok() {
  printf '  ok   %s\n' "$*"
  PASS=$((PASS + 1))
}
t_not_ok() {
  printf '  FAIL %s\n' "$*" >&2
  FAIL=$((FAIL + 1))
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    t_ok "$label"
  else
    t_not_ok "$label (expected '$expected', got '$actual')"
  fi
}

assert_true() {
  local label="$1"
  shift
  if "$@"; then t_ok "$label"; else t_not_ok "$label"; fi
}

assert_false() {
  local label="$1"
  shift
  if "$@"; then t_not_ok "$label"; else t_ok "$label"; fi
}

assert_file() {
  local label="$1" file="$2"
  if [[ -f "$file" ]]; then t_ok "$label"; else t_not_ok "$label (missing $file)"; fi
}

assert_mode() {
  local label="$1" file="$2" mode="$3" actual
  actual="$(stat -c '%a' "$file" 2>/dev/null || true)"
  assert_eq "$mode" "$actual" "$label"
}

finish() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  ((FAIL == 0))
}
