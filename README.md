# get-ros2.com

A POSIX `sh` script that detects the operating system, version, and CPU architecture, then installs the corresponding ROS 2 LTS distribution from official APT packages.

Visit [get-ros2.com](https://get-ros2.com/) for installation commands, supported environments, and checksum verification instructions.

**This is an UNOFFICIAL installer, not an official ROS 2 installer.**

**Provided AS IS, WITHOUT WARRANTY OF ANY KIND.**

| Ubuntu | Repository CI | Published installer |
| --- | --- | --- |
| 22.04 | [![CI Ubuntu 22.04](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-22-04.yml/badge.svg?branch=main&event=push)](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-22-04.yml) | [![Published Ubuntu 22.04](https://github.com/MrBearing/get-ros2/actions/workflows/published-ubuntu-22-04.yml/badge.svg?branch=main)](https://github.com/MrBearing/get-ros2/actions/workflows/published-ubuntu-22-04.yml) |
| 24.04 | [![CI Ubuntu 24.04](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-24-04.yml/badge.svg?branch=main&event=push)](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-24-04.yml) | [![Published Ubuntu 24.04](https://github.com/MrBearing/get-ros2/actions/workflows/published-ubuntu-24-04.yml/badge.svg?branch=main)](https://github.com/MrBearing/get-ros2/actions/workflows/published-ubuntu-24-04.yml) |
| 26.04 | [![CI Ubuntu 26.04](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-26-04.yml/badge.svg?branch=main&event=push)](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-26-04.yml) | [![Published Ubuntu 26.04](https://github.com/MrBearing/get-ros2/actions/workflows/published-ubuntu-26-04.yml/badge.svg?branch=main)](https://github.com/MrBearing/get-ros2/actions/workflows/published-ubuntu-26-04.yml) |

## Usage

Install ROS 2 with:

```sh
curl -fsSL https://get-ros2.com/install.sh | sh
```

To verify the downloaded file before running it, follow [Verify the download](#verify-the-download).

`curl get-ros2.com/install.sh | sh` does not follow HTTP-to-HTTPS redirects. Use `https://` and `-fsSL`. The `-f` flag prevents HTTP error responses from being passed to the shell, and `-L` follows redirects.

To check the exit status of the download as well as the installer, save the script before running it. A standard POSIX shell pipeline does not propagate a failure from curl on the left side of the pipe.

```sh
curl -fsSL https://get-ros2.com/install.sh -o install.sh && sh install.sh
```

Before making changes, the installer states that it is UNOFFICIAL and provided WITHOUT WARRANTY, then asks whether to continue. Enter `y` or `yes` to proceed. An empty answer, a negative answer, or end of input cancels installation. Confirmation is read from the controlling terminal, so it also works with `curl | sh`. If no terminal is available, installation stops unless you explicitly pass `--yes`. A dry run displays the notice without asking for confirmation.

To run a local copy:

```sh
sh install.sh --dry-run
sh install.sh
```

## Verify the download

Each deployed release provides `install.sh` and `install.sh.sha256` on [get-ros2.com](https://get-ros2.com/install.sh.sha256) and in the **Assets** section of its [GitHub Release](https://github.com/MrBearing/get-ros2/releases). The checksum contains the SHA-256 hash of that release's installer.

### Verify the currently deployed installer

Run this on a supported Ubuntu system. It downloads both files into a new temporary directory and runs the downloaded installer only if every download and the checksum check succeed:

<!-- BEGIN verify-pages -->
```sh
(
  download_dir=$(mktemp -d) &&
  cd "$download_dir" &&
  curl -fsSL --proto '=https' --proto-redir '=https' \
    https://get-ros2.com/install.sh -o install.sh &&
  curl -fsSL --proto '=https' --proto-redir '=https' \
    https://get-ros2.com/install.sh.sha256 -o install.sh.sha256 &&
  sha256sum --check --strict install.sh.sha256 &&
  sh ./install.sh
)
```
<!-- END verify-pages -->

### Verify a specific release

Choose a published release and replace `vX.Y.Z` with its tag. Using one release tag for both downloads keeps the pair tied to that version even when the website is updated or rolled back.

<!-- BEGIN verify-release -->
```sh
(
  release_tag='vX.Y.Z'
  release_url="https://github.com/MrBearing/get-ros2/releases/download/$release_tag"
  download_dir=$(mktemp -d) &&
  cd "$download_dir" &&
  curl -fsSL --proto '=https' --proto-redir '=https' \
    "$release_url/install.sh" -o install.sh &&
  curl -fsSL --proto '=https' --proto-redir '=https' \
    "$release_url/install.sh.sha256" -o install.sh.sha256 &&
  sha256sum --check --strict install.sh.sha256 &&
  sh ./install.sh
)
```
<!-- END verify-release -->

A successful check prints `install.sh: OK`. If the check fails, installation stops. Download a matching pair from the same release and verify again; do not bypass the failed check. Append installer options to the final `sh ./install.sh` command if needed.

A checksum verifies that the downloaded file matches the published checksum. It is **not a digital signature** and does not independently authenticate the publisher: someone able to replace both files could publish a matching checksum for an altered script.

## Supported environments

| OS | Codename | Automatically selected ROS 2 distribution | CPU |
| --- | --- | --- | --- |
| Ubuntu 22.04 LTS | jammy | Humble | amd64 / arm64 |
| Ubuntu 24.04 LTS | noble | Jazzy | amd64 / arm64 |
| Ubuntu 26.04 LTS | resolute | Lyrical | amd64 / arm64 |

These mappings follow the [official ROS installation guidance](https://www.ros.org/blog/getting-started/) (checked on 2026-09-15). The default variant is `desktop`, which includes RViz and demos. Use `ros-base` for servers or containers that do not need GUI tools.

On Windows, run the script inside a supported Ubuntu installation on WSL 2. The installer detects and stops on native Windows, macOS, Debian, RHEL-based distributions, Ubuntu derivatives, and 32-bit environments, and points to supported environments or the [official installation instructions](https://docs.ros.org/en/rolling/Installation.html). It does not reuse Ubuntu repositories on unverified operating systems.

Requirements: root or sudo privileges, an internet connection, and an Ubuntu environment with working APT configuration. For Ubuntu on Raspberry Pi or Jetson, make sure the userland is a supported Ubuntu release with the arm64 architecture.

## Options

```sh
# Show the detected environment and planned commands without making changes
curl -fsSL https://get-ros2.com/install.sh | sh -s -- --dry-run

# Install without GUI tools, with development tools
curl -fsSL https://get-ros2.com/install.sh | sh -s -- --variant ros-base --with-dev-tools

# Explicitly select Jazzy on Ubuntu 24.04
curl -fsSL https://get-ros2.com/install.sh | sh -s -- --distro jazzy
```

| Option | Description |
| --- | --- |
| `--distro humble\|jazzy\|lyrical` | Validate the OS/distribution combination; select automatically when omitted |
| `--variant desktop\|ros-base` | Select the metapackage to install; defaults to desktop |
| `--with-dev-tools` | Also install `ros-dev-tools` |
| `--dry-run` | Show planned commands without confirmation, sudo, network access, or file changes |
| `-y`, `--yes` | Explicitly acknowledge the UNOFFICIAL / WITHOUT WARRANTY notice and skip the confirmation prompt |
| `--help` | Show help |

For unattended use, explicitly acknowledge the UNOFFICIAL / WITHOUT WARRANTY notice:

```sh
curl -fsSL https://get-ros2.com/install.sh | sh -s -- --yes
```

## After installation

The installer cannot change the calling shell's environment. Run the setup command printed when installation finishes:

```sh
# Example for Ubuntu 24.04 / Jazzy
. /opt/ros/jazzy/setup.sh
ros2 --help
```

For bash, use `source /opt/ros/jazzy/setup.bash`. For zsh, use `source /opt/ros/jazzy/setup.zsh`. To load ROS automatically, add the appropriate command to your shell's configuration file.

## Build ROS 2 from source

Use [setup-source.sh](setup-source.sh) to prepare a source-build environment instead of installing binary ROS 2 packages. It installs development tools and prepares rosdep, then prints the remaining checkout, dependency-resolution, and build commands. It does not build ROS 2 automatically.

The source setup script supports the same [Ubuntu/ROS 2 pairs and architectures](#supported-environments) listed above. Run it as your normal development user with a writable home directory and sudo access:

```sh
curl -fsSL https://get-ros2.com/setup-source.sh | sh
```

**This is an UNOFFICIAL setup script, provided WITHOUT WARRANTY OF ANY KIND.** It asks for confirmation before modifying the system. The supported options are `--distro humble|jazzy|lyrical`, `--dry-run`, `--yes` / `-y`, and `--help` / `-h`. Without a controlling terminal, explicit acknowledgement with `--yes` is required. A dry run makes no changes.

Setup installs development tools through APT, configures the ROS repository, generates the UTF-8 locale, and initializes/updates rosdep. Source checkout, workspace dependencies, and compilation remain separate steps. `install.sh --with-dev-tools` installs binary ROS 2 with development tools; use `setup-source.sh` when building ROS 2 itself.

The workflows below build the C++ and Python demos and their required dependencies from source on amd64 and arm64, then verify talker/listener communication. Repository CI badges show the overall OS workflow result, including source builds and installer checks. Published source-build badges show results for the script downloaded from get-ros2.com. Click a badge to view runs and build logs.

| Ubuntu / ROS 2 | Repository CI (includes source builds) | Published source builds |
| --- | --- | --- |
| 22.04 / Humble | [![Repository CI including source builds on Ubuntu 22.04](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-22-04.yml/badge.svg?branch=main&event=push)](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-22-04.yml?query=branch%3Amain) | [![Published source builds on Ubuntu 22.04](https://github.com/MrBearing/get-ros2/actions/workflows/published-source-ubuntu-22-04.yml/badge.svg?branch=main)](https://github.com/MrBearing/get-ros2/actions/workflows/published-source-ubuntu-22-04.yml?query=branch%3Amain) |
| 24.04 / Jazzy | [![Repository CI including source builds on Ubuntu 24.04](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-24-04.yml/badge.svg?branch=main&event=push)](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-24-04.yml?query=branch%3Amain) | [![Published source builds on Ubuntu 24.04](https://github.com/MrBearing/get-ros2/actions/workflows/published-source-ubuntu-24-04.yml/badge.svg?branch=main)](https://github.com/MrBearing/get-ros2/actions/workflows/published-source-ubuntu-24-04.yml?query=branch%3Amain) |
| 26.04 / Lyrical | [![Repository CI including source builds on Ubuntu 26.04](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-26-04.yml/badge.svg?branch=main&event=push)](https://github.com/MrBearing/get-ros2/actions/workflows/ci-ubuntu-26-04.yml?query=branch%3Amain) | [![Published source builds on Ubuntu 26.04](https://github.com/MrBearing/get-ros2/actions/workflows/published-source-ubuntu-26-04.yml/badge.svg?branch=main)](https://github.com/MrBearing/get-ros2/actions/workflows/published-source-ubuntu-26-04.yml?query=branch%3Amain) |

### Verify the source setup script

#### Website version

Both the script and its SHA-256 checksum are published together. This command executes the setup script only when every download and the checksum verification succeed:

<!-- BEGIN verify-source-pages -->
```sh
(
  download_dir=$(mktemp -d) &&
  cd "$download_dir" &&
  curl -fsSL --proto '=https' --proto-redir '=https' \
    https://get-ros2.com/setup-source.sh -o setup-source.sh &&
  curl -fsSL --proto '=https' --proto-redir '=https' \
    https://get-ros2.com/setup-source.sh.sha256 -o setup-source.sh.sha256 &&
  sha256sum --check --strict setup-source.sh.sha256 &&
  sh ./setup-source.sh
)
```
<!-- END verify-source-pages -->

#### Specific release

Replace `vX.Y.Z` with a release tag whose Assets include the source setup script. Older releases may provide only the binary installer.

<!-- BEGIN verify-source-release -->
```sh
(
  release_tag='vX.Y.Z'
  release_url="https://github.com/MrBearing/get-ros2/releases/download/$release_tag"
  download_dir=$(mktemp -d) &&
  cd "$download_dir" &&
  curl -fsSL --proto '=https' --proto-redir '=https' \
    "$release_url/setup-source.sh" -o setup-source.sh &&
  curl -fsSL --proto '=https' --proto-redir '=https' \
    "$release_url/setup-source.sh.sha256" -o setup-source.sh.sha256 &&
  sha256sum --check --strict setup-source.sh.sha256 &&
  sh ./setup-source.sh
)
```
<!-- END verify-source-release -->

Success prints `setup-source.sh: OK`. A failed check stops setup; obtain a matching pair from the same release before retrying. The website can serve an older release than GitHub's latest release. A checksum is not a digital signature and cannot independently authenticate the publisher if both files are replaced.

### Build after setup

Follow the distribution-specific commands printed by the script in a **fresh shell without an existing ROS installation sourced**, including automatic sourcing in `.bashrc`. Use a new workspace as your normal user. Setup does not change your login locale, so activate the generated UTF-8 locale in every build shell:

```sh
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
```

The printed steps obtain the official source manifest, import repositories, resolve dependencies with rosdep, and build with colcon. Keep Ubuntu packages up to date and allow sufficient disk space and memory. For limited-memory machines, use `MAKEFLAGS=-j2 CMAKE_BUILD_PARALLEL_LEVEL=2 colcon build --symlink-install --executor sequential --cmake-args -DCMAKE_BUILD_TYPE=Release` for the build step.

See the official source-build instructions for [Humble](https://github.com/ros2/ros2_documentation/blob/humble/source/Installation/Alternatives/Ubuntu-Development-Setup.rst), [Jazzy](https://github.com/ros2/ros2_documentation/blob/jazzy/source/Installation/Alternatives/Ubuntu-Development-Setup.rst), and [Lyrical](https://github.com/ros2/ros2_documentation/blob/lyrical/source/Get-Started/Installation/Alternatives/Ubuntu-Development-Setup.rst). After building, source your workspace's `install/local_setup.sh` in each terminal and run the printed talker/listener commands to check communication.

Upstream manifests track changing branches. Save exact revisions with `vcs export --exact src > ros2-exact.repos`; pinning the setup script alone does not pin ROS sources or APT packages.

### Repeat runs and source setup errors

Existing development packages, matching enabled ROS repository configuration, and rosdep sources are reused. Repository configuration for an older Ubuntu release, or a missing/disabled source file, is refreshed. Setup does not edit shell startup files or workspace contents. It does not repair a failed checkout or build.

The rosdep cache is updated as the development user, including when setup is invoked through sudo. Direct root execution prepares root's cache; other developers must run `rosdep update --rosdistro DISTRO` themselves. For cache permission errors, check ownership of `~/.ros/rosdep` and run rosdep as your normal user.

The [error categories and exit codes](#errors-and-logs) also apply to source setup. Additional errors are `E_USER` (exit 4) for invalid user/home configuration, `E_ROSDEP` (exit 1) for rosdep failures, and `E_TOOLS` (exit 1) for tool verification failures. Known network, APT, permissions, and disk errors take precedence. Setup retains a private log at `/tmp/get-ros2-source.XXXXXXXX/install.log`; already installed files remain installed after failure. Subsequent build failures have their own colcon logs in the workspace.


## Errors and logs

External commands run with `LC_ALL=C`. The installer examines the failed step's exit status and output, then displays guidance in English. Original command output is streamed to the terminal and saved in `/tmp/get-ros2.XXXXXXXX/install.log`. The log is readable and writable only by the invoking user and is retained after failures. Classification uses known output patterns; unrecognized failures are reported as `E_COMMAND` with a pointer to the original log.

| Error | Common cause or suggested action |
| --- | --- |
| `E_ARGUMENT` | Unknown arguments or missing values |
| `E_CONFIRMATION` / `E_CANCELLED` | No interactive terminal, failed confirmation prompt, or declined confirmation; no changes are made |
| `E_OS` / `E_ARCH` / `E_DISTRO` | Unsupported environment or incompatible OS/ROS combination |
| `E_PACKAGE_MANAGER` / `E_DETECTION` | Missing APT/dpkg or failed environment detection |
| `E_PRIVILEGE` | Missing sudo, authentication failure, or insufficient privileges |
| `E_DNS` / `E_NETWORK` | DNS failure, interrupted connection, or timeout |
| `E_TLS` | Certificate, system clock, or proxy CA issue |
| `E_SIGNATURE` | Missing or expired APT signing keys |
| `E_REPOSITORY_CONFLICT` | Duplicate legacy ROS repositories or conflicting Signed-By settings |
| `E_APT_LOCK` | Another APT/dpkg process is running; wait for it to finish |
| `E_DPKG_INTERRUPTED` | Resolve an interrupted operation with `sudo dpkg --configure -a` |
| `E_DEPENDENCY` / `E_REMOVAL_REQUIRED` | Dependency conflicts, held packages, missing updates, or required removals |
| `E_REPOSITORY` | Missing packages, HTTP errors, or missing Release files |
| `E_DISK` / `E_READ_ONLY` | Insufficient disk space or inodes, or a read-only filesystem |
| `E_CHECKSUM` | SHA-256 mismatch for the repository configuration package |
| `E_LOG` / `E_COMMAND` / `E_INTERRUPTED` | Log failure, unclassified command failure, or interruption |

Exit codes: `0` for success, `1` for an operation failure, `2` for invalid arguments, `3` for an unsupported environment, `4` for a failed privilege precheck, `5` for missing or declined confirmation, and `129/130/143` for HUP/INT/TERM interruptions. APT updates stop even if only some repositories fail. A command failure is preserved even when `tee` succeeds in the output pipeline.

## License

This project is licensed under the [MIT License](LICENSE).
Copyright (c) 2026 MrBearing.

ROS 2 and the third-party packages installed by this script retain their respective licenses.
