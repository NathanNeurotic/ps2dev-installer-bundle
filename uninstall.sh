#!/usr/bin/env bash
set -Eeuo pipefail

PS2DEV_DIR="${PS2DEV:-/usr/local/ps2dev}"
WORK_ROOT="${PS2DEV_WORK_ROOT:-$HOME/.cache/ps2dev-installer}"
BASHRC_FILE="$HOME/.bashrc"
ENV_BLOCK_START="# >>> ps2dev-installer >>>"
ENV_BLOCK_END="# <<< ps2dev-installer <<<"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
trap 'fail "Uninstall aborted at line $LINENO"' ERR

log "Removing PS2DEV install at $PS2DEV_DIR"
sudo rm -rf "$PS2DEV_DIR"
rm -rf "$WORK_ROOT"

if [[ -f "$BASHRC_FILE" ]]; then
  tmp="$(mktemp)"
  awk -v s="$ENV_BLOCK_START" -v e="$ENV_BLOCK_END" '
    $0==s {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$BASHRC_FILE" > "$tmp"
  mv "$tmp" "$BASHRC_FILE"
fi

log "PS2DEV uninstall complete"
log "Open a new shell or run: source ~/.bashrc"
