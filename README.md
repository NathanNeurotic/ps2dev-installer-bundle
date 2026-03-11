# PS2DEV Installer Bundle

This bundle installs a full PlayStation 2 homebrew development environment on Ubuntu or WSL, including `ps2toolchain`, `ps2sdk`, environment variable setup, ERL sample repair logic for modern GCC, a modernized ERL hello sample, verification, and uninstall support.

## Files in this bundle

- `ps2dev_aio_installer.sh` — thin entrypoint that calls `install.sh`
- `install.sh` — main automated installer
- `uninstall.sh` — removes the installed environment and shell profile block
- `verify_install.sh` — validates toolchain and sample builds
- `README.md` — usage and troubleshooting

## Supported target

- Ubuntu
- WSL running Ubuntu or a compatible Debian-family base

## What the installer does

1. Installs required Ubuntu packages.
2. Clones `ps2toolchain` from the official `ps2dev` GitHub repository.
3. Builds and installs the PS2 toolchain into `/usr/local/ps2dev` by default.
4. Clones and builds `ps2sdk` from the official `ps2dev` GitHub repository.
5. Writes an idempotent environment block into `~/.bashrc`.
6. Attempts to build and install ERL-related components.
7. Rewrites old ERL build flags where legacy `-mno-crt0` usage is found.
8. Replaces legacy `libc.erl` dependency strings with `liberl.erl libcglue.erl libkernel.erl` where needed.
9. Installs a working sample at `/usr/local/ps2dev/ps2sdk/samples/erl/hello`.
10. Verifies sample compilation for:
   - `samples/debug/helloworld`
   - `samples/kernel/nanoHelloWorld`
   - `samples/graph`
   - `samples/erl/hello`

## Usage

Run the installer:

```bash
chmod +x ps2dev_aio_installer.sh install.sh uninstall.sh verify_install.sh
./ps2dev_aio_installer.sh
```

Or directly:

```bash
./install.sh
```

After the installer finishes:

```bash
source ~/.bashrc
```

Run verification again at any time:

```bash
./verify_install.sh
```

Uninstall:

```bash
./uninstall.sh
```

## Optional overrides

Default install root:

```bash
export PS2DEV=/usr/local/ps2dev
```

Optional work/cache directory:

```bash
export PS2DEV_WORK_ROOT="$HOME/.cache/ps2dev-installer"
```

Then run the installer.

## Troubleshooting

### `toolchain.sh` fails because of permissions

The installer creates and chowns the PS2DEV directory before building. If you changed `PS2DEV`, make sure the path has no spaces and the user has write access.

### GitHub clone or package install fails

Check network access, DNS resolution, WSL proxy settings, and whether GitHub or Ubuntu mirrors are blocked.

### Environment variables do not appear in the current shell

Run:

```bash
source ~/.bashrc
```

or open a new shell.

### ERL verification fails

The installer patches legacy flags and dependency references when they are found, then installs a known-good `samples/erl/hello` sample. Re-run:

```bash
./verify_install.sh
```

If it still fails, inspect installed artifact locations:

```bash
find /usr/local/ps2dev -type f \( -name 'liberl.erl' -o -name 'liberl.a' -o -name 'erl-loader.elf' \)
```

### Re-running the installer

The installer is safe to re-run. It updates existing Git clones, refreshes the environment block, and rebuilds the toolchain and SDK.

## Notes

- The installer logs to `~/.cache/ps2dev-installer/logs/`.
- Any failure aborts immediately with an error message and log path.
- The verification script returns a non-zero exit code if any required check fails.
