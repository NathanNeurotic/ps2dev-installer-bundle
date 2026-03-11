<img width="1536" height="1024" alt="PS2DEV-INSTALLER-BUNDLE" src="https://github.com/user-attachments/assets/1641fd9b-6466-439e-8614-ebfae5d6566e" />

# PS2DEV Installer Bundle

This bundle installs a fuller PlayStation 2 homebrew development environment on Ubuntu or Ubuntu running inside WSL. It installs `ps2toolchain`, builds `ps2sdk`, installs `ps2sdk-ports`, `gsKit`, `ps2-packer`, `ps2client`, modern memory-card tools (`mymc++`, `ps2vmc-tool`, `ps1vmc-tool`), writes the shell environment block, repairs older ERL build settings where needed, installs a known-good ERL hello sample, and runs verification at the end.

This repository is aimed at two paths:

- Windows users who already have WSL with Ubuntu installed
- Users already running Ubuntu directly

If you do not already have WSL + Ubuntu or Ubuntu set up, use the prerequisite assistant first: [wsl-dev-pack](https://www.github.com/NathanNeurotic/wsl-dev-pack)

## Supported target

- Windows with WSL and an Ubuntu distro
- Ubuntu running directly

On Windows, the launcher accepts Ubuntu distros even if the WSL distro name itself has been renamed, as long as the distro reports Ubuntu in `/etc/os-release`.

The installer checks `/etc/os-release` for Ubuntu identity (`ID=ubuntu` or `ID_LIKE=...ubuntu...`), because this bundle is written and documented for Ubuntu-first usage, especially on WSL.

## Prerequisites

Before running this bundle, already have all of the following:

- One supported host environment:
  - WSL installed with an Ubuntu distro that appears in `wsl.exe -l -q`
  - Ubuntu running directly
- `sudo` access in Ubuntu, because the installer runs `apt-get`, creates the install root, and updates ownership
- Network access to GitHub, Ubuntu package mirrors, and PyPI
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

## Files in this repo

- `ps2dev_aio_installer.bat` - double-clickable Windows launcher for WSL users
- `ps2dev_aio_installer.ps1` - Windows-side WSL handoff into the bundle directory
- `ps2dev_aio_installer.sh` - thin shell entrypoint that calls `install.sh`
- `install.sh` - main automated installer
- `verify_install.sh` - validates toolchain commands, `ps2sdk-ports`, `gsKit`, `ps2client`, `ps2-packer`, memory-card tools, ERL artifacts, and sample builds
- `uninstall.sh` - removes the installed environment, cache, and shell profile block
- `.github/workflows/release.yml` - repo-only maintainer workflow used to publish release ZIPs
- `README.md` - installation, troubleshooting, and maintainer notes

## What the installer does

1. Validates that it is running on Ubuntu or a Debian-family base.
2. Installs the required Ubuntu packages.
3. Clones `ps2toolchain` from the official `ps2dev` GitHub repository.
4. Builds and installs the PS2 toolchain into `/usr/local/ps2dev` by default.
5. Clones `ps2sdk` from the official `ps2dev` GitHub repository.
6. Builds and installs `ps2sdk`.
7. Clones, builds, and installs `ps2sdk-ports`.
8. Clones, builds, and installs `gsKit`.
9. Clones, builds, and installs `ps2-packer`.
10. Clones, builds, and installs `ps2client`.
11. Installs the `mymc++` command-line tool in an isolated Python virtual environment and exposes both `mymcplusplus` and `mymc` commands.
12. Clones, builds, and installs `ps2vmc-tool` and `ps1vmc-tool`.
13. Writes an idempotent environment block into `~/.bashrc`.
14. Patches older ERL build rules where legacy flags or dependency names are found.
15. Builds ERL-related components where dedicated directories are present.
16. Installs a modernized `samples/hello` sample and also exposes `samples/erl/hello` as a compatibility path.
17. Runs bundled verification for:
    - `samples/debug/helloworld`
    - `samples/kernel/nanoHelloWorld`
    - `samples/graph`
    - `samples/hello`
    - installed `ps2sdk-ports` headers and libraries under `$PS2SDK/ports`
    - installed commands such as `ee-gcc`, `iop-gcc`, `ps2client`, `fsclient`, `ps2-packer`, `mymc`, `mymcplusplus`, `ps2vmc-tool`, and `ps1vmc-tool`
    - smoke tests that format and inspect temporary PS1/PS2 memory card images

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

The environment block also removes stale manual `PS2DEV` exports and `ee-*` / `iop-*` aliases from older setups, clears Bash's command hash, and then exports the wrapper command paths.

Run verification again at any time:

```bash
./verify_install.sh
```

## Using ps2link

The host-side tools in this bundle are only half of the normal run/debug loop. On the console side, the usual PS2DEV workflow is:

1. Boot through a homebrew entrypoint such as FreeMCBoot (FMCB), FreeHDBoot (FHDB), OpenTuna, OSDMenu, LOADBOOTER, or PS2BBL.
2. Launch `ps2link` on the console.
3. Use the host-side `ps2client` or `fsclient` commands from Ubuntu.

This bundle does not require one specific loader. Use the one that fits your console and storage setup.

Set the target console IP one of two ways:

```bash
export PS2HOSTNAME=192.168.1.50
```

or pass it per command:

```bash
ps2client -h 192.168.1.50 execee host:myapp.elf
```

Common host-side commands:

```bash
ps2client -h "$PS2HOSTNAME" execee host:myapp.elf
ps2client -h "$PS2HOSTNAME" listen
fsclient -h "$PS2HOSTNAME" ls /
```

If `PS2HOSTNAME` is unset, `ps2client` falls back to its built-in default host address. For most users it is clearer and safer to set the console IP explicitly.

This installer does not write `PS2HOSTNAME` into the managed shell block because that value is network-specific.

Uninstall:

```bash
./uninstall.sh
```

## Optional overrides

Default install root:

```bash
export PS2DEV=/usr/local/ps2dev
```

If you override `PS2DEV`, keep it as an absolute Linux path with no spaces and only simple path characters. Upstream PS2DEV tooling is much less reliable when this path is relative or contains spaces.

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

The installer also depends on the official Ubuntu-side build prerequisites, including `cmake`, `autopoint`, and the GMP/MPFR/MPC development packages. If you customized the script or trimmed packages manually, restore the full package list and rerun it.

`ps2sdk-ports` is also a larger network-dependent step because it fetches and builds a collection of extra libraries during `make`. A temporary GitHub timeout or fetch failure there usually means rerunning the installer is enough.

The `mymc` command installed by this bundle is a compatibility wrapper around modern `mymc++`, not the legacy Python 2 `ps2dev/mymc` script. This bundle installs the CLI form of `mymc++`, not the optional wxPython GUI.

### Environment variables do not appear in the current shell

Run:

```bash
source ~/.bashrc
```

or open a new Ubuntu shell.

### You opened Ubuntu from PowerShell and landed in `/mnt/c/Windows/System32`

That is a normal WSL starting directory when launched from Windows, but it is a bad place for manual clones or builds. If you are running follow-up commands yourself, move to your home or repo first:

```bash
cd ~
```

or:

```bash
cd ~/Github
```

### `ps2client` or `fsclient` cannot connect

Make sure the console is already running `ps2link`, the PS2 and the host are on the same network, and `PS2HOSTNAME` or the `-h` argument points to the actual console IP.

Useful manual checks:

```bash
echo "$PS2HOSTNAME"
ps2client -h "$PS2HOSTNAME" listen
```

### ERL verification fails

The installer patches older ERL flags and dependency references when it finds them, then installs a known-good `samples/hello` sample with a compatibility symlink at `samples/erl/hello`. Re-run:

```bash
./verify_install.sh
```

If it still fails, inspect installed ERL artifacts:

```bash
find /usr/local/ps2dev -type f \( -name 'liberl.erl' -o -name 'liberl.a' -o -name 'erl-loader.elf' \)
```

### Re-running the installer

The installer is designed to be safe to rerun. It refreshes the shell environment block, rebuilds the toolchain and SDK, recreates any cached source repo that has installer-created tracked changes, and reruns verification.

If a previous `ps2toolchain` build was interrupted, the installer now removes its cached `build/` directory before rebuilding.

If you are recovering from a badly broken old install under `/usr/local/ps2dev`, run `./uninstall.sh` first for a true clean slate before reinstalling.

Even with `ps2sdk-ports` included, some repos may still need project-specific third-party code outside the standard PS2DEV stack. If a local project still fails after this installer and `./verify_install.sh` both pass, the next thing to check is that repo's own dependency list.

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
