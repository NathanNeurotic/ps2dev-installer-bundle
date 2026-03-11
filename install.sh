#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS2DEV_DEFAULT="/usr/local/ps2dev"
PS2DEV_DIR="${PS2DEV:-$PS2DEV_DEFAULT}"
PS2SDK_DIR="$PS2DEV_DIR/ps2sdk"
WORK_ROOT="${PS2DEV_WORK_ROOT:-$HOME/.cache/ps2dev-installer}"
TOOLCHAIN_SRC="$WORK_ROOT/ps2toolchain"
SDK_SRC="$WORK_ROOT/ps2sdk"
PORTS_SRC="$WORK_ROOT/ps2sdk-ports"
GSKIT_SRC="$WORK_ROOT/gsKit"
PACKER_SRC="$WORK_ROOT/ps2-packer"
CLIENT_SRC="$WORK_ROOT/ps2client"
VMC_TOOL_SRC="$WORK_ROOT/ps2vmc-tool"
LOG_DIR="$WORK_ROOT/logs"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
BASHRC_FILE="$HOME/.bashrc"
TOTAL_STEPS=18
CURRENT_STEP=0
START_TS="$(date +%s)"

APT_PACKAGES=(
  autoconf
  automake
  autopoint
  bison
  build-essential
  cmake
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
  python3-venv
  tar
  texinfo
  unzip
  wget
  xz-utils
  zlib1g-dev
)

ENV_BLOCK_START="# >>> ps2dev-installer >>>"
ENV_BLOCK_END="# <<< ps2dev-installer <<<"

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

log() {
  [[ -n "${LOG_FILE:-}" ]] || return 0
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"
}

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

status_line() {
  local color="$1"
  local tag="$2"
  local message="$3"

  printf '%b[%s]%b %s\n' "$color" "$tag" "$COLOR_RESET" "$message"
  log "$tag: $message"
}

info() { status_line "$COLOR_CYAN" 'INFO' "$1"; }
success() { status_line "$COLOR_GREEN" ' OK ' "$1"; }
warn() { status_line "$COLOR_YELLOW" 'WARN' "$1"; }

step() {
  local message="$1"
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf '\n%b[%02d/%02d]%b %s\n' "$COLOR_BOLD$COLOR_BLUE" "$CURRENT_STEP" "$TOTAL_STEPS" "$COLOR_RESET" "$message"
  log "STEP $CURRENT_STEP/$TOTAL_STEPS: $message"
}

run() {
  log "RUN: $*"
  printf '%b[RUN ]%b %s\n' "$COLOR_DIM" "$COLOR_RESET" "$*"
  "$@" 2>&1 | tee -a "$LOG_FILE"
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

fail() {
  local message="$1"
  printf '\n%b[FAIL]%b %s\n' "$COLOR_RED" "$COLOR_RESET" "$message" >&2
  log "FAIL: $message"
  exit 1
}

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
  need_cmd sed
  if [[ ! -f /etc/os-release ]]; then
    fail "Unsupported system: /etc/os-release not found. Ubuntu/WSL is required."
  fi
  local pretty_name
  pretty_name="$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')"
  if ! grep -qiE '(^ID=ubuntu$|^ID_LIKE=.*ubuntu)' /etc/os-release; then
    fail "This installer targets Ubuntu/WSL. Detected: ${pretty_name:-unknown}"
  fi
  if [[ "$PS2DEV_DIR" != /* ]]; then
    fail "PS2DEV must be an absolute path. Current value: $PS2DEV_DIR"
  fi
  if [[ "$PS2DEV_DIR" == *[[:space:]]* ]]; then
    fail "PS2DEV must not contain spaces. Current value: $PS2DEV_DIR"
  fi
  if ! [[ "$PS2DEV_DIR" =~ ^[A-Za-z0-9_./-]+$ ]]; then
    fail "PS2DEV may only contain letters, numbers, '/', '.', '_' and '-'. Current value: $PS2DEV_DIR"
  fi
  info "Target OS: ${pretty_name:-unknown}"
  info "PS2DEV path: $PS2DEV_DIR"
  if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
    info "WSL environment detected"
  fi
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  info "Installing required Ubuntu packages"
  run sudo apt-get update
  run sudo apt-get install -y "${APT_PACKAGES[@]}"
}

prepare_ps2dev_dir() {
  info "Preparing PS2DEV directory: $PS2DEV_DIR"
  run sudo mkdir -p "$PS2DEV_DIR"
  run sudo chown -R "$USER":"$(id -gn)" "$PS2DEV_DIR"
}

sync_repo() {
  local repo_url="$1"
  local target_dir="$2"
  local branch="${3:-master}"

  if [[ -d "$target_dir/.git" ]]; then
    if ! git -C "$target_dir" diff --quiet --ignore-submodules -- || ! git -C "$target_dir" diff --cached --quiet --ignore-submodules --; then
      warn "Cached repo has local tracked changes; recreating $target_dir"
      rm -rf "$target_dir"
    fi
  fi

  if [[ -d "$target_dir/.git" ]]; then
    info "Updating existing repo: $target_dir"
    run git -C "$target_dir" fetch --all --tags --prune
    run git -C "$target_dir" checkout "$branch"
    run git -C "$target_dir" pull --ff-only origin "$branch"
  else
    info "Cloning $repo_url -> $target_dir"
    rm -rf "$target_dir"
    run git clone "$repo_url" "$target_dir"
    run git -C "$target_dir" checkout "$branch"
  fi
}

install_toolchain() {
  info "Cloning and building ps2toolchain"
  sync_repo "https://github.com/ps2dev/ps2toolchain" "$TOOLCHAIN_SRC" master

  export PS2DEV="$PS2DEV_DIR"
  export PS2SDK="$PS2SDK_DIR"
  export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

  if [[ -d "$TOOLCHAIN_SRC/build" ]]; then
    info "Removing previous ps2toolchain build directory before rebuild"
    run rm -rf "$TOOLCHAIN_SRC/build"
  fi

  if [[ -f "$TOOLCHAIN_SRC/toolchain.sh" ]]; then
    run bash "$TOOLCHAIN_SRC/toolchain.sh"
  else
    fail "ps2toolchain/toolchain.sh was not found"
  fi
}

install_ps2sdk() {
  info "Cloning and building ps2sdk"
  sync_repo "https://github.com/ps2dev/ps2sdk" "$SDK_SRC" master

  export PS2DEV="$PS2DEV_DIR"
  export PS2SDK="$PS2SDK_DIR"
  export PS2SDKSRC="$SDK_SRC"
  export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

  run make -C "$SDK_SRC" clean
  run make -C "$SDK_SRC"
  run make -C "$SDK_SRC" install
}

install_ps2sdk_ports() {
  info "Cloning and building ps2sdk-ports"
  sync_repo "https://github.com/ps2dev/ps2sdk-ports" "$PORTS_SRC" master

  export PS2DEV="$PS2DEV_DIR"
  export PS2SDK="$PS2SDK_DIR"
  export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

  if [[ -d "$PORTS_SRC/build" ]]; then
    info "Removing previous ps2sdk-ports build directory before rebuild"
    run rm -rf "$PORTS_SRC/build"
  fi

  run make -C "$PORTS_SRC" clean || true
  run make -C "$PORTS_SRC"
}

install_gskit() {
  info "Cloning and building gsKit"
  sync_repo "https://github.com/ps2dev/gsKit" "$GSKIT_SRC" master

  export PS2DEV="$PS2DEV_DIR"
  export PS2SDK="$PS2SDK_DIR"
  export GSKIT="$PS2DEV_DIR/gsKit"
  export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

  run make -C "$GSKIT_SRC" clean || true
  run make -C "$GSKIT_SRC"
  run make -C "$GSKIT_SRC" install
}

install_ps2_packer() {
  info "Cloning and building ps2-packer"
  sync_repo "https://github.com/ps2dev/ps2-packer" "$PACKER_SRC" master

  export PS2DEV="$PS2DEV_DIR"
  export PS2SDK="$PS2SDK_DIR"
  export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

  run make -C "$PACKER_SRC" clean
  run make -C "$PACKER_SRC"
  run make -C "$PACKER_SRC" install
}

install_ps2client() {
  info "Cloning and building ps2client"
  sync_repo "https://github.com/ps2dev/ps2client" "$CLIENT_SRC" master

  export PS2DEV="$PS2DEV_DIR"
  export PS2SDK="$PS2SDK_DIR"
  export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

  run make -C "$CLIENT_SRC" clean || true
  run make -C "$CLIENT_SRC"
  run make -C "$CLIENT_SRC" install
}

install_mymcplusplus() {
  info "Installing mymc++ memory card utility"
  local venv_dir="$PS2DEV_DIR/python-tools/mymcplusplus"
  local bin_dir="$PS2DEV_DIR/bin"

  run python3 -m venv "$venv_dir"
  run "$venv_dir/bin/python" -m pip install --upgrade pip
  run "$venv_dir/bin/python" -m pip install --upgrade mymcplusplus

  mkdir -p "$bin_dir"

  cat > "$bin_dir/mymcplusplus" <<EOF
#!/usr/bin/env bash
exec "$venv_dir/bin/mymcplusplus" "\$@"
EOF
  chmod +x "$bin_dir/mymcplusplus"

  cat > "$bin_dir/mymc" <<EOF
#!/usr/bin/env bash
exec "$bin_dir/mymcplusplus" "\$@"
EOF
  chmod +x "$bin_dir/mymc"
}

install_ps2vmc_tool() {
  info "Cloning and building ps2vmc-tool"
  sync_repo "https://github.com/bucanero/ps2vmc-tool" "$VMC_TOOL_SRC" main

  run make -C "$VMC_TOOL_SRC" clean || true
  run make -C "$VMC_TOOL_SRC"
  mkdir -p "$PS2DEV_DIR/bin"
  run install -m 0755 "$VMC_TOOL_SRC/ps2vmc-tool" "$PS2DEV_DIR/bin/ps2vmc-tool"
  run install -m 0755 "$VMC_TOOL_SRC/ps1vmc-tool" "$PS2DEV_DIR/bin/ps1vmc-tool"
}

patch_env_block() {
  info "Configuring shell environment in $BASHRC_FILE"
  local tmp
  tmp="$(mktemp)"
  touch "$BASHRC_FILE"
  awk -v s="$ENV_BLOCK_START" -v e="$ENV_BLOCK_END" -v ps2dev_path="$PS2DEV_DIR" -v ps2sdk_path="$PS2SDK_DIR" '
    $0==s {skip=1; next}
    $0==e {skip=0; next}
    /^export PS2DEV=/ {next}
    /^export PS2SDK=/ {next}
    /^export GSKIT=/ {next}
    /^export PS2SDKSRC=/ {next}
    /^PS2DEV=/ {next}
    /^PS2SDK=/ {next}
    /^GSKIT=/ {next}
    /^PS2SDKSRC=/ {next}
    (/^export PATH=/ || /^PATH=/) && (
      index($0, "PS2DEV") ||
      index($0, "PS2SDK") ||
      index($0, ps2dev_path) ||
      index($0, ps2sdk_path)
    ) {next}
    /^alias (ee-|iop-)/ {next}
    !skip {print}
  ' "$BASHRC_FILE" > "$tmp"

  cat >> "$tmp" <<ENVEOF
$ENV_BLOCK_START
# Clear stale manual aliases from older shell setups before PATH lookup.
for _ps2_alias in ee-gcc ee-g++ ee-ar ee-as ee-ld ee-strip ee-objcopy ee-objdump iop-gcc iop-g++ iop-ar iop-as iop-ld iop-strip iop-objcopy iop-objdump; do
  unalias "$_ps2_alias" 2>/dev/null || true
done
unset _ps2_alias
hash -r 2>/dev/null || true

export PS2DEV="$PS2DEV_DIR"
export PS2SDK="\$PS2DEV/ps2sdk"
export GSKIT="\$PS2DEV/gsKit"
case ":\$PATH:" in
  *":\$PS2DEV/bin:\$PS2DEV/ee/bin:\$PS2DEV/iop/bin:\$PS2DEV/dvp/bin:\$PS2SDK/bin:"*) ;;
  *) export PATH="\$PATH:\$PS2DEV/bin:\$PS2DEV/ee/bin:\$PS2DEV/iop/bin:\$PS2DEV/dvp/bin:\$PS2SDK/bin" ;;
esac
$ENV_BLOCK_END
ENVEOF
  mv "$tmp" "$BASHRC_FILE"
}

install_wrapper_script() {
  local wrapper_name="$1"
  local target_name="$2"

  cat > "$PS2DEV_DIR/bin/$wrapper_name" <<EOF
#!/usr/bin/env bash
exec $target_name "\$@"
EOF
  chmod +x "$PS2DEV_DIR/bin/$wrapper_name"
}

install_wrapper_commands() {
  info "Installing ee-* and iop-* wrapper commands"
  mkdir -p "$PS2DEV_DIR/bin"

  install_wrapper_script ee-gcc mips64r5900el-ps2-elf-gcc
  install_wrapper_script ee-g++ mips64r5900el-ps2-elf-g++
  install_wrapper_script ee-ar mips64r5900el-ps2-elf-ar
  install_wrapper_script ee-as mips64r5900el-ps2-elf-as
  install_wrapper_script ee-ld mips64r5900el-ps2-elf-ld
  install_wrapper_script ee-strip mips64r5900el-ps2-elf-strip
  install_wrapper_script ee-objcopy mips64r5900el-ps2-elf-objcopy
  install_wrapper_script ee-objdump mips64r5900el-ps2-elf-objdump

  install_wrapper_script iop-gcc mipsel-ps2-elf-gcc
  install_wrapper_script iop-g++ mipsel-ps2-elf-g++
  install_wrapper_script iop-ar mipsel-ps2-elf-ar
  install_wrapper_script iop-as mipsel-ps2-elf-as
  install_wrapper_script iop-ld mipsel-ps2-elf-ld
  install_wrapper_script iop-strip mipsel-ps2-elf-strip
  install_wrapper_script iop-objcopy mipsel-ps2-elf-objcopy
  install_wrapper_script iop-objdump mipsel-ps2-elf-objdump
}

write_fixed_erl_sample_makefile() {
  local target_file="$1"

  cat > "$target_file" <<'MAKEEOF'
# _____     ___ ____     ___ ____
#  ____|   |    ____|   |        | |____|
# |     ___|   |____ ___|    ____| |    \    PS2DEV Open Source Project.
#-----------------------------------------------------------------------
# Copyright 2001-2004, ps2dev - http://www.ps2dev.org
# Licenced under Academic Free License version 2.0
# Review ps2sdk README & LICENSE files for further details.

EE_ERL = hello.erl
EE_OBJS = hello.o

all: $(EE_ERL) erl-loader.elf liberl.erl libcglue.erl libkernel.erl

clean:
	rm -f $(EE_ERL) $(EE_OBJS) erl-loader.elf liberl.erl libcglue.erl libkernel.erl

erl-loader.elf:
	cp $(PS2SDK)/ee/bin/erl-loader.elf $@

liberl.erl:
	cp $(PS2SDK)/ee/lib/liberl.erl $@

libcglue.erl:
	cp $(PS2SDK)/ee/lib/libcglue.erl $@

libkernel.erl:
	cp $(PS2SDK)/ee/lib/libkernel.erl $@

run: $(EE_ERL) erl-loader.elf liberl.erl libcglue.erl libkernel.erl
	ps2client execee host:erl-loader.elf $(EE_ERL)

reset:
	ps2client reset

include $(PS2SDK)/samples/Makefile.pref
include $(PS2SDK)/samples/Makefile.eeglobal
MAKEEOF
}

write_erl_hello_sample() {
  info "Installing modernized ERL hello sample"
  local sample_dir="$PS2SDK_DIR/samples/hello"
  mkdir -p "$sample_dir"
  rm -f "$sample_dir/host.c" "$sample_dir/host.o" "$sample_dir/host.elf"
  write_fixed_erl_sample_makefile "$sample_dir/Makefile"

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

  mkdir -p "$PS2SDK_DIR/samples/erl"
  ln -sfn ../hello "$PS2SDK_DIR/samples/erl/hello"
}

patch_existing_erl_makefiles() {
  info "Patching PS2SDK ERL rules for current GCC and installed sample layout"
  local eglobal_files=(
    "$SDK_SRC/samples/Makefile.eeglobal_sample"
    "$SDK_SRC/samples/Makefile.eeglobal_cpp_sample"
    "$PS2SDK_DIR/samples/Makefile.eeglobal"
    "$PS2SDK_DIR/samples/Makefile.eeglobal_cpp"
  )
  local file

  for file in "${eglobal_files[@]}"; do
    if [[ -f "$file" ]]; then
      sed -i 's/-mno-crt0/-nostartfiles/g' "$file"
    fi
  done

  if [[ -f "$SDK_SRC/ee/erl/samples/hello/Makefile.sample" ]]; then
    write_fixed_erl_sample_makefile "$SDK_SRC/ee/erl/samples/hello/Makefile.sample"
  fi

  local erl_loader_makefile="$SDK_SRC/ee/erl-loader/Makefile"
  if [[ -f "$erl_loader_makefile" ]]; then
    if ! grep -Fq -- '-L$(PS2SDK)/ee/lib' "$erl_loader_makefile"; then
      sed -i 's|-L$(PS2SDKSRC)/ee/kernel/lib|-L$(PS2SDKSRC)/ee/kernel/lib -L$(PS2SDK)/ee/lib|' "$erl_loader_makefile"
    fi

    if ! grep -Fq -- '-Wno-error=builtin-declaration-mismatch' "$erl_loader_makefile"; then
      sed -i 's|EE_CFLAGS += |EE_CFLAGS += -Wno-error=builtin-declaration-mismatch |' "$erl_loader_makefile"
    fi

    if ! grep -Fq '$(EE_OBJS_DIR):' "$erl_loader_makefile"; then
      cat >> "$erl_loader_makefile" <<'MAKEEOF'

$(EE_OBJS_DIR):
	$(MKDIR) -p $(EE_OBJS_DIR)

$(EE_BIN_DIR):
	$(MKDIR) -p $(EE_BIN_DIR)
MAKEEOF
    fi
  fi
}

build_erl_components() {
  info "Building and installing liberl and erl-loader components"
  export PS2DEV="$PS2DEV_DIR"
  export PS2SDK="$PS2SDK_DIR"
  export PS2SDKSRC="$SDK_SRC"
  export PATH="$PATH:$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin"

  local built_any=0
  local erl_runtime_dir="$SDK_SRC/ee/erl"
  local erl_loader_dir="$SDK_SRC/ee/erl-loader"

  if [[ -f "$erl_runtime_dir/Makefile" ]]; then
    built_any=1
    mkdir -p "$erl_runtime_dir/obj" "$erl_runtime_dir/lib" "$PS2SDK_DIR/ee/lib"
    run make -C "$erl_runtime_dir" clean || true
    mkdir -p "$erl_runtime_dir/obj" "$erl_runtime_dir/lib"
    run make -C "$erl_runtime_dir"
    run install -m 0644 "$erl_runtime_dir/lib/liberl.a" "$PS2SDK_DIR/ee/lib/liberl.a"
    run install -m 0644 "$erl_runtime_dir/lib/liberl.erl" "$PS2SDK_DIR/ee/lib/liberl.erl"
  fi

  if [[ -f "$erl_loader_dir/Makefile" ]]; then
    built_any=1
    mkdir -p "$erl_loader_dir/obj" "$erl_loader_dir/bin" "$PS2SDK_DIR/ee/bin"
    run make -C "$erl_loader_dir" clean || true
    mkdir -p "$erl_loader_dir/obj" "$erl_loader_dir/bin"
    run make -C "$erl_loader_dir"
    run install -m 0644 "$erl_loader_dir/bin/erl-loader.elf" "$PS2SDK_DIR/ee/bin/erl-loader.elf"
  fi

  if [[ "$built_any" -eq 0 ]]; then
    warn "No dedicated ERL component directories were found; relying on top-level ps2sdk install artifacts"
  else
    success "ERL runtime artifacts were rebuilt and installed"
  fi
}

verify_artifacts_exist() {
  info "Verifying critical installed artifacts"
  local missing=0
  local -a expected=(
    "$PS2DEV_DIR/ps2sdk/bin/ps2sdk-config"
    "$PS2DEV_DIR/bin/ee-gcc"
    "$PS2DEV_DIR/bin/iop-gcc"
    "$PS2DEV_DIR/ee/bin/mips64r5900el-ps2-elf-gcc"
    "$PS2DEV_DIR/iop/bin/mipsel-ps2-elf-gcc"
    "$PS2DEV_DIR/bin/ps2client"
    "$PS2DEV_DIR/bin/fsclient"
    "$PS2DEV_DIR/bin/ps2-packer"
    "$PS2DEV_DIR/bin/mymc"
    "$PS2DEV_DIR/bin/mymcplusplus"
    "$PS2DEV_DIR/bin/ps2vmc-tool"
    "$PS2DEV_DIR/bin/ps1vmc-tool"
    "$PS2DEV_DIR/gsKit"
    "$PS2DEV_DIR/gsKit/lib"
    "$PS2SDK_DIR/ports"
    "$PS2SDK_DIR/ports/include"
    "$PS2SDK_DIR/ports/lib"
    "$PS2SDK_DIR/ee/include"
    "$PS2SDK_DIR/iop/include"
    "$PS2SDK_DIR/ee/startup/linkfile"
    "$PS2SDK_DIR/ee/lib/libkernel.a"
    "$PS2SDK_DIR/ee/lib/libcglue.a"
    "$PS2SDK_DIR/ee/lib/libpthreadglue.a"
    "$PS2SDK_DIR/ee/lib/liberl.erl"
    "$PS2SDK_DIR/ee/lib/libcglue.erl"
    "$PS2SDK_DIR/ee/lib/libkernel.erl"
    "$PS2SDK_DIR/ee/bin/erl-loader.elf"
  )

  for f in "${expected[@]}"; do
    if [[ ! -e "$f" ]]; then
      warn "Missing artifact: $f"
      missing=1
    fi
  done

  local erl_matches=0
  info "Scanning installed ERL artifacts"
  find "$PS2DEV_DIR" -type f \( -name 'liberl.erl' -o -name 'liberl.a' -o -name 'erl-loader.elf' \) -print | tee -a "$LOG_FILE" || true
  erl_matches=$(find "$PS2DEV_DIR" -type f \( -name 'liberl.erl' -o -name 'liberl.a' -o -name 'erl-loader.elf' \) | wc -l)

  if (( erl_matches < 3 )); then
    warn "One or more ERL artifacts were not found by name after build. verify_install.sh will perform a deeper check."
  fi

  if [[ "$missing" -ne 0 ]]; then
    fail "Critical PS2DEV artifacts are missing after installation"
  fi

  success "Critical PS2DEV artifacts are present"
}

run_verification() {
  info "Running verification script"
  if [[ -f "$SCRIPT_DIR/verify_install.sh" ]]; then
    PS2DEV="$PS2DEV_DIR" PS2SDK="$PS2SDK_DIR" bash "$SCRIPT_DIR/verify_install.sh"
  else
    fail "verify_install.sh is missing"
  fi
}

main() {
  ensure_dirs
  banner "PS2DEV Installer Bundle" "Automated Ubuntu / WSL + Ubuntu setup"
  info "Install root: $PS2DEV_DIR"
  info "Work root: $WORK_ROOT"
  info "Log file: $LOG_FILE"

  step "Validate host platform"
  check_platform

  step "Install required Ubuntu packages"
  install_packages

  step "Prepare the PS2DEV install directory"
  prepare_ps2dev_dir

  step "Clone and build ps2toolchain"
  install_toolchain

  step "Clone and build ps2sdk"
  install_ps2sdk

  step "Clone and build ps2sdk-ports"
  install_ps2sdk_ports

  step "Clone and build gsKit"
  install_gskit

  step "Clone and build ps2-packer"
  install_ps2_packer

  step "Clone and build ps2client"
  install_ps2client

  step "Install mymc++ memory card utility"
  install_mymcplusplus

  step "Clone and build ps2vmc-tool"
  install_ps2vmc_tool

  step "Patch legacy ERL build rules"
  patch_existing_erl_makefiles

  step "Build ERL support components"
  build_erl_components

  step "Write shell environment configuration"
  patch_env_block

  step "Install ee-* and iop-* wrapper commands"
  install_wrapper_commands

  step "Install the ERL hello sample"
  write_erl_hello_sample

  step "Verify critical installed artifacts"
  verify_artifacts_exist

  step "Run bundled verification"
  run_verification

  success "Installation completed successfully"
  info "Open a new shell or run: source ~/.bashrc"
  info "Re-run verification anytime with: ./verify_install.sh"
  info "If you use ps2link, set PS2HOSTNAME or pass -h to ps2client/fsclient for your console IP"
  info "Elapsed time: $(format_duration "$(( $(date +%s) - START_TS ))")"
}

main "$@"
