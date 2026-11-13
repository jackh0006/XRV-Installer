#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Run every check locally or in CI.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

failed=0

section() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

section "Bash syntax"
for file in xrv-install.sh xrv-client.sh tests/*.sh; do
  if bash -n "$file"; then
    printf '  ok   %s\n' "$file"
  else
    printf '  FAIL %s\n' "$file" >&2
    failed=1
  fi
done

section "ShellCheck"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning -x xrv-install.sh xrv-client.sh tests/*.sh; then
    printf '  ok   shellcheck\n'
  else
    printf '  FAIL shellcheck\n' >&2
    failed=1
  fi
else
  printf '  skip shellcheck is not installed\n'
fi

section "shfmt (informational)"
if command -v shfmt >/dev/null 2>&1; then
  if shfmt -d -i 2 -ci xrv-install.sh xrv-client.sh tests/*.sh >/tmp/xrv-shfmt.diff 2>&1; then
    printf '  ok   shfmt\n'
  else
    printf '  note shfmt would reformat files (not a failure); see /tmp/xrv-shfmt.diff\n'
  fi
else
  printf '  skip shfmt is not installed\n'
fi

section "Unit and integration tests"
for test in tests/test-client-lib.sh tests/test-server-lib.sh tests/test-client-install.sh tests/test-release.sh; do
  printf '\n-- %s\n' "$test"
  if bash "$test"; then
    printf '  ok   %s\n' "$test"
  else
    printf '  FAIL %s\n' "$test" >&2
    failed=1
  fi
done

printf '\n'
if ((failed == 0)); then
  printf '\033[32mAll checks passed.\033[0m\n'
else
  printf '\033[31mSome checks failed.\033[0m\n' >&2
fi
exit "$failed"
