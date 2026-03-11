#!/usr/bin/env bash
set -Eeuo pipefail

PS2DEV_DEFAULT="/usr/local/ps2dev"
PS2DEV_DIR="${PS2DEV:-$PS2DEV_DEFAULT}"
PS2SDK_DIR="$PS2DEV_DIR/ps2sdk"
WORK_ROOT="${PS2DEV_WORK_ROOT:-$HOME/.cache/ps2dev-installer}"
TOOLCHAIN_SRC="$WORK_ROOT/ps2toolchain"
SDK_SRC="$WORK_ROOT/ps2sdk"
LOG_DIR="$WORK_ROOT/logs"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
BASHRC_FILE="$HOME/.bashrc"

APT_PACKAGES=(
  autoconf
  automake
  bison
  build-essential
  curl
  flex
  gettext
  git
  gperf
  libgmp-dev
  libgmp3-dev
  libgsl-dev
  libmpc-dev
  libmpfr-dev
  libncurses5-dev
  libreadline-dev
  libssl-dev
  libtool
  make
  patch
  pkg-config
  python3
  python3-pip
  tar
  texinfo
  unzip
  wget
  xz-utils
  zlib1g-dev
)

ENV_BLOCK_START="# >>> ps2dev-installer >>>"
ENV_BLOCK_END="# <<< ps2dev-installer <<<"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }
fail() { printf '\n[ERROR] %s\n' "$*" | tee -a "$LOG_FILE" >&2; exit 1; }
run() { log "RUN: $*"; "$@" 2>&1 | tee -a "$LOG_FILE"; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }

on_error() {
  local exit_code=$?
  local line_no=${1:-unknown}
  fail "Installation aborted at line $line_no with exit code $exit_code. Review $LOG_FILE"
}
trap 'on_error $LINENO' ERR

ensure_dirs() {
  mkdir -p "$WORK_ROOT" "$LOG_DIR"
  touch "$LOG_FILE"
}

check_platform() {
  need_cmd bash
  need_cmd sudo
  need_cmd git
  need_cmd make
  need_cmd sed
  if [[ ! -f /etc/os-release ]]; then
    fail "Unsupported system: /etc/os-release not found. Ubuntu/WSL is required."
  fi
  if ! grep -qiE 'ubuntu|debian' /etc/os-release; then
    fail "This installer targets Ubuntu/WSL. Detected: $(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2-)"
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  log "Installing required Ubuntu packages"
  run sudo apt-get update
  run sudo apt-get install -y "${APT_PACKAGES[@]}"
}

prepare_ps2dev_dir() {
  log "Preparing PS2DEV directory: $PS2DEV_DIR"
  run sudo mkdir -p "$PS2DEV_DIR"
  run sudo chown -R "$USER":"$(id -gn)" "$PS2DEV_DIR"
}

sync_repo() {
  local repo_url="$1"
  local target_dir="$2"
  local branch="${3:-master}"

  if [[ -d "$target_dir/.git" ]]; then
    log "Updating existing repo: $target_dir"
    run git -C "$target_dir" fetch --all --tags --prune
    run git -C "$target_dir" checkout "$branch"
    run git -C "$target_dir" pull --ff-only origin "$branch"
  else
    log "Cloning $repo_url -> $target_dir"
    rm -rf "$target_dir"
    run git clone "$repo_url" "$target_dir"
    run git -C "$target_dir" checkout "$branch"
  fi
}

install_toolchain() {
  log "Cloning and building ps2toolchain"
  sync_repo "https://github.com/ps2dev/ps2toolchain" "$TOOLCHAIN_SRC" master

  export PS2DEV="$PS2DEV_DIR"
  export PS2SDK="$PS2SDK_DIR"
  export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

  if [[ -x "$TOOLCHAIN_SRC/toolchain.sh" ]]; then
    run bash "$TOOLCHAIN_SRC/toolchain.sh"
  else
    fail "ps2toolchain/toolchain.sh not found or not executable"
  fi
}

install_ps2sdk() {
  log "Cloning and building ps2sdk"
  sync_repo "https://github.com/ps2dev/ps2sdk" "$SDK_SRC" master

  export PS2DEV="$PS2DEV_DIR"
  export PS2SDK="$PS2SDK_DIR"
  export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

  run make -C "$SDK_SRC" clean
  run make -C "$SDK_SRC"
  run make -C "$SDK_SRC" install
}

patch_env_block() {
  log "Configuring shell environment in $BASHRC_FILE"
  local tmp
  tmp="$(mktemp)"
  touch "$BASHRC_FILE"
  awk -v s="$ENV_BLOCK_START" -v e="$ENV_BLOCK_END" '
    $0==s {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$BASHRC_FILE" > "$tmp"

  cat >> "$tmp" <<ENVEOF
$ENV_BLOCK_START
export PS2DEV="$PS2DEV_DIR"
export PS2SDK="\$PS2DEV/ps2sdk"
case ":\$PATH:" in
  *":\$PS2DEV/bin:\$PS2DEV/ee/bin:\$PS2DEV/iop/bin:\$PS2DEV/dvp/bin:\$PS2SDK/bin:"*) ;;
  *) export PATH="\$PATH:\$PS2DEV/bin:\$PS2DEV/ee/bin:\$PS2DEV/iop/bin:\$PS2DEV/dvp/bin:\$PS2SDK/bin" ;;
esac
$ENV_BLOCK_END
ENVEOF
  mv "$tmp" "$BASHRC_FILE"
}

write_erl_hello_sample() {
  log "Installing modernized ERL hello sample"
  local sample_dir="$PS2SDK_DIR/samples/erl/hello"
  mkdir -p "$sample_dir"

  cat > "$sample_dir/Makefile" <<'MAKEEOF'
EE_BIN = host.elf
EE_OBJS = host.o
EE_LIBS = -ldebug -lpatches -lc -lkernel

ERL_BIN = hello.erl
ERL_OBJS = hello.o
ERL_LIBS = -lerl -lcglue -lkernel

all: $(EE_BIN) $(ERL_BIN)

host.elf: $(EE_OBJS)
	$(EE_CC) $(EE_CFLAGS) -o $@ $^ $(EE_LIBS)

hello.erl: $(ERL_OBJS)
	$(EE_CC) $(EE_CFLAGS) -Wl,-r -G0 -nostartfiles -o $@ $^ $(ERL_LIBS)
	$(EE_STRIP) --strip-unneeded -R .mdebug.eabi64 -R .reginfo -R .comment $@

clean:
	rm -f $(EE_BIN) $(ERL_BIN) $(EE_OBJS) $(ERL_OBJS)

include $(PS2SDK)/samples/Makefile.pref
include $(PS2SDK)/samples/Makefile.eeglobal
MAKEEOF

  cat > "$sample_dir/host.c" <<'CEOF'
#include <debug.h>
#include <erl.h>
#include <kernel.h>
#include <loadfile.h>
#include <sifrpc.h>
#include <stdio.h>

extern int SifLoadFileInit(void);

int main(int argc, char *argv[])
{
    init_scr();
    SifInitRpc(0);
    SifLoadFileInit();

    scr_printf("PS2SDK ERL host sample\n");

    _init_erl_prefix = "host:";

    if (_init_load_erl("hello") < 0) {
        scr_printf("Failed to load hello.erl\n");
        SleepThread();
    }

    scr_printf("hello.erl loaded successfully\n");
    SleepThread();
    return 0;
}
CEOF

  cat > "$sample_dir/hello.c" <<'CEOF'
#include <debug.h>
#include <erl.h>
#include <stdio.h>

char *erl_id = "hello";
char *erl_dependancies[] = {
    "liberl",
    "libcglue",
    "libkernel",
    NULL
};

int _init(void)
{
    scr_printf("hello.erl says hello from ERL.\n");
    return 0;
}

int _fini(void)
{
    scr_printf("hello.erl shutting down.\n");
    return 0;
}
CEOF
}

patch_existing_erl_makefiles() {
  log "Patching ERL sample/build rules for modern GCC compatibility where needed"
  local root="$SDK_SRC"
  [[ -d "$root" ]] || return 0

  while IFS= read -r -d '' file; do
    sed -i 's/-mno-crt0/-nostartfiles/g' "$file"
    sed -i 's/libc\.erl/liberl.erl libcglue.erl libkernel.erl/g' "$file"
  done < <(find "$root" -type f \( -name 'Makefile' -o -name '*.mk' -o -name '*.sh' \) -print0)
}

build_erl_components() {
  log "Building liberl and erl-loader components"
  export PS2DEV="$PS2DEV_DIR"
  export PS2SDK="$PS2SDK_DIR"
  export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

  local built_any=0
  local -a candidates=(
    "$SDK_SRC/ee/erl"
    "$SDK_SRC/ee/erl/liberl"
    "$SDK_SRC/ee/erl/loader"
    "$SDK_SRC/ee/erl/samples"
  )

  for dir in "${candidates[@]}"; do
    if [[ -f "$dir/Makefile" ]]; then
      built_any=1
      run make -C "$dir" clean || true
      run make -C "$dir"
      run make -C "$dir" install || true
    fi
  done

  if [[ "$built_any" -eq 0 ]]; then
    log "No dedicated ERL component directories were found; relying on top-level ps2sdk install artifacts"
  fi
}

verify_artifacts_exist() {
  log "Verifying critical installed artifacts"
  local missing=0
  local -a expected=(
    "$PS2DEV_DIR/ps2sdk/bin/ps2sdk-config"
    "$PS2DEV_DIR/ee/bin/ee-gcc"
  )

  for f in "${expected[@]}"; do
    if [[ ! -e "$f" ]]; then
      printf '[MISSING] %s\n' "$f" | tee -a "$LOG_FILE"
      missing=1
    fi
  done

  local erl_matches=0
  find "$PS2DEV_DIR" -type f \( -name 'liberl.erl' -o -name 'liberl.a' -o -name 'erl-loader.elf' \) -print | tee -a "$LOG_FILE" || true
  erl_matches=$(find "$PS2DEV_DIR" -type f \( -name 'liberl.erl' -o -name 'liberl.a' -o -name 'erl-loader.elf' \) | wc -l)

  if (( erl_matches < 3 )); then
    log "One or more ERL artifacts were not found by name after build. verify_install.sh will perform a deeper check."
  fi

  if [[ "$missing" -ne 0 ]]; then
    fail "Critical PS2DEV artifacts are missing after installation"
  fi
}

run_verification() {
  log "Running verification script"
  if [[ -x "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify_install.sh" ]]; then
    PS2DEV="$PS2DEV_DIR" PS2SDK="$PS2SDK_DIR" "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify_install.sh"
  else
    fail "verify_install.sh is missing or not executable"
  fi
}

main() {
  ensure_dirs
  log "PS2DEV all-in-one installer starting"
  check_platform
  install_packages
  prepare_ps2dev_dir
  install_toolchain
  install_ps2sdk
  patch_existing_erl_makefiles
  build_erl_components
  patch_env_block
  write_erl_hello_sample
  verify_artifacts_exist
  run_verification
  log "Installation completed successfully"
  log "Open a new shell or run: source ~/.bashrc"
}

main "$@"
