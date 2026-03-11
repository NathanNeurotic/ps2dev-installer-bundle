# PS2DEV Installer Bundle

This bundle installs a full PlayStation 2 homebrew development environment on Ubuntu or Ubuntu running inside WSL. It installs `ps2toolchain`, builds `ps2sdk`, writes the shell environment block, repairs older ERL build settings where needed, installs a known-good ERL hello sample, and runs verification at the end.

This repository is aimed at two paths:

- Windows users who already have WSL with Ubuntu installed
- Users already running Ubuntu directly

If you do not already have WSL + Ubuntu or Ubuntu set up, use the prerequisite assistant first: [wsl-dev-pack](https://www.github.com/NathanNeurotic/wsl-dev-pack)

## Supported target

- Windows with WSL and an Ubuntu distro
- Ubuntu running directly

The installer currently checks `/etc/os-release` for `ubuntu|debian`, but this bundle is written and documented for Ubuntu-first usage, especially on WSL.

## Prerequisites

Before running this bundle, already have all of the following:

- One supported host environment:
  - WSL installed with an Ubuntu distro that appears in `wsl.exe -l -q`
  - Ubuntu running directly
- `sudo` access in Ubuntu, because the installer runs `apt-get`, creates the install root, and updates ownership
- Network access to GitHub and Ubuntu package mirrors
- Enough free disk space for package downloads, cloned source trees, build artifacts, and the final install under `/usr/local/ps2dev` by default
- The bundle stored in a location your Ubuntu environment can access

If you are on Windows and do not yet have WSL + Ubuntu ready, stop here and use [wsl-dev-pack](https://www.github.com/NathanNeurotic/wsl-dev-pack) first.

## Knowledge Check

Minimum knowledge expected before you run this:

- You know whether you are launching from Windows into WSL or from an Ubuntu shell directly.
- You can enter your Ubuntu `sudo` password when prompted.
- You know how to open a new Ubuntu shell, or run `source ~/.bashrc`, after installation finishes.
- You know how to rerun `./verify_install.sh` if you want to validate the install again later.
- You are comfortable reading the installer log at `~/.cache/ps2dev-installer/logs/` if a build step fails.

Nothing deeper than that should be required, but those basics are necessary.

## Files in this bundle

- `ps2dev_aio_installer.bat` - double-clickable Windows launcher for WSL users
- `ps2dev_aio_installer.ps1` - Windows-side WSL handoff into the bundle directory
- `ps2dev_aio_installer.sh` - thin shell entrypoint that calls `install.sh`
- `install.sh` - main automated installer
- `verify_install.sh` - validates toolchain commands, ERL artifacts, and sample builds
- `uninstall.sh` - removes the installed environment, cache, and shell profile block
- `.github/workflows/release.yml` - manually triggered GitHub release workflow
- `README.md` - installation, troubleshooting, and maintainer notes

## What the installer does

1. Validates that it is running on Ubuntu or a Debian-family base.
2. Installs the required Ubuntu packages.
3. Clones `ps2toolchain` from the official `ps2dev` GitHub repository.
4. Builds and installs the PS2 toolchain into `/usr/local/ps2dev` by default.
5. Clones `ps2sdk` from the official `ps2dev` GitHub repository.
6. Builds and installs `ps2sdk`.
7. Writes an idempotent environment block into `~/.bashrc`.
8. Patches older ERL build rules where legacy flags or dependency names are found.
9. Builds ERL-related components where dedicated directories are present.
10. Installs a modernized `samples/erl/hello` sample.
11. Runs bundled verification for:
    - `samples/debug/helloworld`
    - `samples/kernel/nanoHelloWorld`
    - `samples/graph`
    - `samples/erl/hello`

## Quick Start

### Windows + WSL (recommended for this bundle)

1. Confirm that WSL is installed and that an Ubuntu distro exists.
2. If not, use [wsl-dev-pack](https://www.github.com/NathanNeurotic/wsl-dev-pack) first.
3. Double-click `ps2dev_aio_installer.bat` from Windows Explorer.
4. The launcher will:
   - start PowerShell
   - detect an Ubuntu WSL distro
   - translate the bundle path into a WSL path
   - run `bash ./ps2dev_aio_installer.sh` inside that Ubuntu distro
5. When the run finishes, the batch launcher pauses so you can read the final summary.

You do not need to open Ubuntu manually first for this path.

### Ubuntu directly

Run the installer from an Ubuntu shell:

```bash
chmod +x ps2dev_aio_installer.sh install.sh uninstall.sh verify_install.sh
./ps2dev_aio_installer.sh
```

Or call the main installer directly:

```bash
./install.sh
```

## After Installation

If you want the environment available in the current shell session immediately, run:

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

Set any overrides before launching the installer.

## Terminal experience

The scripts now provide:

- step counters for the major install and uninstall stages
- colored status lines when running in a color-capable terminal
- a persistent log file for installer runs
- clearer verification summaries with pass/fail counts
- Windows launcher status messages before the handoff into WSL

Set `NO_COLOR=1` if you want plain output.

## Troubleshooting

### You do not have WSL + Ubuntu or Ubuntu ready yet

Use the prerequisite assistant first: [wsl-dev-pack](https://www.github.com/NathanNeurotic/wsl-dev-pack)

### The Windows launcher says no Ubuntu WSL distro was found

Install Ubuntu in WSL, then confirm it appears in:

```powershell
wsl.exe -l -q
```

Then run `ps2dev_aio_installer.bat` again.

### The Windows launcher cannot access the bundle path

Make sure the bundle is extracted somewhere that WSL can read, or opened from a matching `\\wsl$\<distro>\...` path. The launcher checks that `./ps2dev_aio_installer.sh` is reachable inside the selected distro before starting the installer.

### `toolchain.sh` fails because of permissions

The installer creates and `chown`s the PS2DEV directory before building. If you override `PS2DEV`, keep the path writable and avoid spaces.

### Package install or GitHub clone fails

Check network access, DNS resolution, WSL proxy settings, and whether GitHub or Ubuntu mirrors are blocked.

### Environment variables do not appear in the current shell

Run:

```bash
source ~/.bashrc
```

or open a new Ubuntu shell.

### ERL verification fails

The installer patches older ERL flags and dependency references when it finds them, then installs a known-good `samples/erl/hello` sample. Re-run:

```bash
./verify_install.sh
```

If it still fails, inspect installed ERL artifacts:

```bash
find /usr/local/ps2dev -type f \( -name 'liberl.erl' -o -name 'liberl.a' -o -name 'erl-loader.elf' \)
```

### Re-running the installer

The installer is designed to be safe to rerun. It updates existing Git clones, refreshes the shell environment block, rebuilds the toolchain and SDK, and reruns verification.

## Logs

- Installer logs are written to `~/.cache/ps2dev-installer/logs/`
- Any installer failure aborts immediately and reports the log path
- `verify_install.sh` returns a non-zero exit code if any required check fails

## Maintainer release workflow

The repository includes a manual GitHub Actions release workflow:

1. Push the commit you want to release.
2. Open `Actions`.
3. Run `Release Bundle`.
4. Provide a version tag such as `v1.0.0`.
5. Optionally set a release title or mark it as a prerelease.

The workflow creates a GitHub Release and uploads a ZIP containing the bundle scripts and README.
