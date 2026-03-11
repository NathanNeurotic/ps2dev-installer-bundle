#!/usr/bin/env bash
set -Eeuo pipefail

PS2DEV_DIR="${PS2DEV:-/usr/local/ps2dev}"
PS2SDK_DIR="${PS2SDK:-$PS2DEV_DIR/ps2sdk}"
export PS2DEV="$PS2DEV_DIR"
export PS2SDK="$PS2SDK_DIR"
export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

TOTAL_SECTIONS=5
CURRENT_SECTION=0
START_TS="$(date +%s)"
PASS_COUNT=0
FAIL_COUNT=0
TEMP_FILES=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_RESET=$'\033[0m'
  COLOR_BOLD=$'\033[1m'
  COLOR_DIM=$'\033[2m'
  COLOR_BLUE=$'\033[38;5;39m'
  COLOR_CYAN=$'\033[36m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_RED=$'\033[31m'
else
  COLOR_RESET=''
  COLOR_BOLD=''
  COLOR_DIM=''
  COLOR_BLUE=''
  COLOR_CYAN=''
  COLOR_GREEN=''
  COLOR_YELLOW=''
  COLOR_RED=''
fi

rule() {
  printf '%b%s%b\n' "$COLOR_DIM" '----------------------------------------------------------------------' "$COLOR_RESET"
}

banner() {
  local title="$1"
  local subtitle="${2:-}"

  rule
  printf '%b%s%b\n' "$COLOR_BOLD$COLOR_BLUE" "$title" "$COLOR_RESET"
  if [[ -n "$subtitle" ]]; then
    printf '%b%s%b\n' "$COLOR_DIM" "$subtitle" "$COLOR_RESET"
  fi
  rule
}

info() { printf '%b[INFO]%b %s\n' "$COLOR_CYAN" "$COLOR_RESET" "$1"; }
success() { printf '%b[ OK ]%b %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$1"; }
warn() { printf '%b[WARN]%b %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$1"; }
pass() { printf '%b[PASS]%b %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail_item() { printf '%b[FAIL]%b %s\n' "$COLOR_RED" "$COLOR_RESET" "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

format_duration() {
  local total_seconds="$1"
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  if (( hours > 0 )); then
    printf '%02dh %02dm %02ds' "$hours" "$minutes" "$seconds"
  else
    printf '%02dm %02ds' "$minutes" "$seconds"
  fi
}

section() {
  local title="$1"
  CURRENT_SECTION=$((CURRENT_SECTION + 1))
  printf '\n%b[%02d/%02d]%b %s\n' "$COLOR_BOLD$COLOR_BLUE" "$CURRENT_SECTION" "$TOTAL_SECTIONS" "$COLOR_RESET" "$title"
}

cleanup() {
  if (( ${#TEMP_FILES[@]} > 0 )); then
    rm -f "${TEMP_FILES[@]}"
  fi
}

on_error() {
  local exit_code=$?
  local line_no=${1:-unknown}
  printf '\n%b[FAIL]%b Verification aborted at line %s with exit code %s\n' \
    "$COLOR_RED" "$COLOR_RESET" "$line_no" "$exit_code" >&2
  exit "$exit_code"
}

trap cleanup EXIT
trap 'on_error $LINENO' ERR

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
  shopt -s nullglob globstar
  for pattern in "$@"; do
    if compgen -G "$pattern" >/dev/null; then
      found=1
      break
    fi
  done
  shopt -u nullglob globstar

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
  local stdout_file
  local stderr_file
  stdout_file="$(mktemp "${TMPDIR:-/tmp}/ps2dev-verify.out.XXXXXX")"
  stderr_file="$(mktemp "${TMPDIR:-/tmp}/ps2dev-verify.err.XXXXXX")"
  TEMP_FILES+=("$stdout_file" "$stderr_file")

  info "Building $label"
  if make -C "$dir" clean >/dev/null 2>&1 && make -C "$dir" >"$stdout_file" 2>"$stderr_file"; then
    pass "$label"
  else
    fail_item "$label"
    if [[ -s "$stderr_file" ]]; then
      sed 's/^/  /' "$stderr_file" || true
    elif [[ -s "$stdout_file" ]]; then
      sed 's/^/  /' "$stdout_file" || true
    fi
  fi
}

run_cmd_check() {
  local label="$1"
  shift
  local stdout_file
  local stderr_file
  stdout_file="$(mktemp "${TMPDIR:-/tmp}/ps2dev-verify.out.XXXXXX")"
  stderr_file="$(mktemp "${TMPDIR:-/tmp}/ps2dev-verify.err.XXXXXX")"
  TEMP_FILES+=("$stdout_file" "$stderr_file")

  if "$@" >"$stdout_file" 2>"$stderr_file"; then
    pass "$label"
  else
    fail_item "$label"
    if [[ -s "$stderr_file" ]]; then
      sed 's/^/  /' "$stderr_file" || true
    elif [[ -s "$stdout_file" ]]; then
      sed 's/^/  /' "$stdout_file" || true
    fi
  fi
}

verify_memory_card_tools() {
  local tmp_ps2
  local tmp_ps1
  tmp_ps2="$(mktemp "${TMPDIR:-/tmp}/ps2dev-vmc.XXXXXX.ps2")"
  tmp_ps1="$(mktemp "${TMPDIR:-/tmp}/ps2dev-vmc.XXXXXX.mcr")"
  TEMP_FILES+=("$tmp_ps2")
  TEMP_FILES+=("$tmp_ps1")
  rm -f "$tmp_ps2"
  rm -f "$tmp_ps1"

  run_cmd_check "mymc++ can format a PS2 memory card image" \
    mymc -i "$tmp_ps2" format

  if [[ -f "$tmp_ps2" ]]; then
    run_cmd_check "mymc++ can inspect a formatted PS2 memory card image" \
      mymc -i "$tmp_ps2" df
  fi

  run_cmd_check "ps2vmc-tool can format a PS2 virtual memory card" \
    ps2vmc-tool "$tmp_ps2" --mc-format
  run_cmd_check "ps2vmc-tool can inspect a PS2 virtual memory card" \
    ps2vmc-tool "$tmp_ps2" --mc-info

  run_cmd_check "ps1vmc-tool can format a PS1 virtual memory card" \
    ps1vmc-tool "$tmp_ps1" --mc-format
  run_cmd_check "ps1vmc-tool can inspect a PS1 virtual memory card" \
    ps1vmc-tool "$tmp_ps1" --mc-info
}

runtime_workflow_guidance() {
  if [[ -n "${PS2HOSTNAME:-}" ]]; then
    info "PS2HOSTNAME is set to: $PS2HOSTNAME"
    info "Remote run example: ps2client -h \"$PS2HOSTNAME\" execee host:your.elf"
    info "Remote log example: ps2client -h \"$PS2HOSTNAME\" listen"
  else
    warn "PS2HOSTNAME is not set. For ps2link workflows, export PS2HOSTNAME=<your-ps2-ip> or pass -h to ps2client/fsclient."
    info "Example: ps2client -h 192.168.1.50 execee host:your.elf"
  fi
}

main() {
  banner "PS2DEV Verification" "Checks toolchain commands, ERL artifacts, and sample builds"
  info "PS2DEV root: $PS2DEV_DIR"
  info "PS2SDK root: $PS2SDK_DIR"

  section "Environment"
  check_cmd ee-gcc
  check_cmd iop-gcc
  check_cmd ps2sdk-config
  check_cmd ps2client
  check_cmd fsclient
  check_cmd ps2-packer
  check_cmd mymc
  check_cmd mymcplusplus
  check_cmd ps2vmc-tool
  check_cmd ps1vmc-tool
  check_file_glob "PS2DEV root exists" "$PS2DEV_DIR"
  check_file_glob "PS2SDK root exists" "$PS2SDK_DIR"
  check_file_glob "gsKit root exists" "$PS2DEV_DIR/gsKit" "$PS2DEV_DIR/gsKit/lib"
  check_file_glob "ps2-packer modules installed" "$PS2DEV_DIR/share/ps2-packer/module"

  section "Ports"
  check_file_glob "PS2SDK ports root exists" "$PS2SDK_DIR/ports"
  check_file_glob "PS2SDK ports headers installed" \
    "$PS2SDK_DIR/ports/include/*.h" \
    "$PS2SDK_DIR/ports/include"/**/*.h
  check_file_glob "PS2SDK ports libraries installed" "$PS2SDK_DIR/ports/lib/*.a"

  section "Runtime workflow"
  runtime_workflow_guidance

  section "Host tools and ERL artifacts"
  verify_memory_card_tools
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
  check_file_glob "ERL hello sample path exists" \
    "$PS2SDK_DIR/samples/hello" \
    "$PS2SDK_DIR/samples/erl/hello"

  section "Sample builds"
  local base="$PS2SDK_DIR/samples"
  build_sample "samples/debug/helloworld" "$base/debug/helloworld"
  build_sample "samples/kernel/nanoHelloWorld" "$base/kernel/nanoHelloWorld"
  build_sample "samples/graph" "$base/graph"
  build_sample "samples/hello" "$base/hello"

  printf '\n'
  rule
  printf '%bSummary%b %d passed, %d failed\n' "$COLOR_BOLD" "$COLOR_RESET" "$PASS_COUNT" "$FAIL_COUNT"
  printf '%bElapsed%b %s\n' "$COLOR_BOLD" "$COLOR_RESET" "$(format_duration "$(( $(date +%s) - START_TS ))")"
  rule

  if [[ "$FAIL_COUNT" -ne 0 ]]; then
    warn "Verification completed with failures"
    exit 1
  fi

  success "Verification completed successfully"
}

main "$@"
