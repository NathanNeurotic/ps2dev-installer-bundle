#!/usr/bin/env bash
set -Eeuo pipefail

PS2DEV_DIR="${PS2DEV:-/usr/local/ps2dev}"
PS2SDK_DIR="${PS2SDK:-$PS2DEV_DIR/ps2sdk}"
export PS2DEV="$PS2DEV_DIR"
export PS2SDK="$PS2SDK_DIR"
export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

PASS_COUNT=0
FAIL_COUNT=0

pass() { printf '[PASS] %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail_item() { printf '[FAIL] %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "Command available: $cmd"
  else
    fail_item "Command missing: $cmd"
  fi
}

check_file_glob() {
  local label="$1"
  shift
  local found=0
  local pattern
  shopt -s nullglob
  for pattern in "$@"; do
    local matches=( $pattern )
    if (( ${#matches[@]} > 0 )); then
      printf '%s\n' "${matches[@]}" >/dev/null
      found=1
      break
    fi
  done
  shopt -u nullglob

  if [[ "$found" -eq 1 ]]; then
    pass "$label"
  else
    fail_item "$label"
  fi
}

build_sample() {
  local label="$1"
  local dir="$2"
  if [[ ! -d "$dir" ]]; then
    fail_item "$label (missing directory: $dir)"
    return
  fi
  if make -C "$dir" clean >/dev/null 2>&1 && make -C "$dir" >/tmp/ps2dev-verify.out 2>/tmp/ps2dev-verify.err; then
    pass "$label"
  else
    fail_item "$label"
    sed 's/^/  /' /tmp/ps2dev-verify.err || true
  fi
}

section "Environment"
check_cmd ee-gcc
check_cmd ps2sdk-config
check_file_glob "PS2DEV root exists" "$PS2DEV_DIR"
check_file_glob "PS2SDK root exists" "$PS2SDK_DIR"

section "ERL artifacts"
check_file_glob "liberl.erl present" \
  "$PS2SDK_DIR/ee/erl/liberl.erl" \
  "$PS2SDK_DIR/erl/liberl.erl" \
  "$PS2DEV_DIR"/**/liberl.erl
check_file_glob "liberl.a present" \
  "$PS2SDK_DIR/ee/erl/liberl.a" \
  "$PS2SDK_DIR/erl/liberl.a" \
  "$PS2DEV_DIR"/**/liberl.a
check_file_glob "erl-loader.elf present" \
  "$PS2SDK_DIR/samples/erl"/**/erl-loader.elf \
  "$PS2SDK_DIR/ee/erl"/**/erl-loader.elf \
  "$PS2DEV_DIR"/**/erl-loader.elf

section "Sample builds"
base="$PS2SDK_DIR/samples"
build_sample "samples/debug/helloworld" "$base/debug/helloworld"
build_sample "samples/kernel/nanoHelloWorld" "$base/kernel/nanoHelloWorld"
build_sample "samples/graph" "$base/graph"
build_sample "samples/erl/hello" "$base/erl/hello"

printf '\nSummary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
if [[ "$FAIL_COUNT" -ne 0 ]]; then
  exit 1
fi
