#!/usr/bin/env bash
set -Eeuo pipefail

PS2DEV_DIR="${PS2DEV:-/usr/local/ps2dev}"
WORK_ROOT="${PS2DEV_WORK_ROOT:-$HOME/.cache/ps2dev-installer}"
BASHRC_FILE="$HOME/.bashrc"
ENV_BLOCK_START="# >>> ps2dev-installer >>>"
ENV_BLOCK_END="# <<< ps2dev-installer <<<"
TOTAL_STEPS=3
CURRENT_STEP=0
START_TS="$(date +%s)"

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

step() {
  local message="$1"
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf '\n%b[%02d/%02d]%b %s\n' "$COLOR_BOLD$COLOR_BLUE" "$CURRENT_STEP" "$TOTAL_STEPS" "$COLOR_RESET" "$message"
}

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

need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }
fail() { printf '\n%b[FAIL]%b %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2; exit 1; }
trap 'fail "Uninstall aborted at line $LINENO"' ERR

main() {
  banner "PS2DEV Uninstall" "Removes the installed toolchain, cache, and shell profile block"
  info "Install root: $PS2DEV_DIR"
  info "Work root: $WORK_ROOT"

  need_cmd sudo
  need_cmd awk

  step "Remove the installed PS2DEV directory"
  if [[ -e "$PS2DEV_DIR" ]]; then
    info "Removing $PS2DEV_DIR"
    sudo rm -rf "$PS2DEV_DIR"
    success "Removed $PS2DEV_DIR"
  else
    warn "Nothing to remove at $PS2DEV_DIR"
  fi

  step "Remove cached build data"
  if [[ -e "$WORK_ROOT" ]]; then
    info "Removing $WORK_ROOT"
    rm -rf "$WORK_ROOT"
    success "Removed $WORK_ROOT"
  else
    warn "Nothing to remove at $WORK_ROOT"
  fi

  step "Remove the shell profile block"
  if [[ -f "$BASHRC_FILE" ]]; then
    local tmp
    tmp="$(mktemp)"
    awk -v s="$ENV_BLOCK_START" -v e="$ENV_BLOCK_END" '
      $0==s {skip=1; next}
      $0==e {skip=0; next}
      !skip {print}
    ' "$BASHRC_FILE" > "$tmp"
    mv "$tmp" "$BASHRC_FILE"
    success "Updated $BASHRC_FILE"
  else
    warn "No $BASHRC_FILE file was found"
  fi

  printf '\n'
  rule
  success "PS2DEV uninstall complete"
  info "Open a new shell or run: source ~/.bashrc"
  info "Elapsed time: $(format_duration "$(( $(date +%s) - START_TS ))")"
  rule
}

main "$@"
