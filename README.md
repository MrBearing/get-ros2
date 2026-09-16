# get-ros2.com

A POSIX `sh` script that detects the operating system, version, and CPU architecture, then installs the corresponding ROS 2 LTS distribution from official APT packages.

**This is an UNOFFICIAl installer, not an official ROS 2 installer.**

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

`curl get-ros2.com/install.sh | sh` does not follow HTTP-to-HTTPS redirects. Use `https://` and `-fsSL`. The `-f` flag prevents HTTP error responses from being passed to the shell, and `-L` follows redirects.

To check the exit status of the download as well as the installer, save the script before running it. A standard POSIX shell pipeline does not propagate a failure from curl on the left side of the pipe.

```sh
curl -fsSL https://get-ros2.com/install.sh -o install.sh && sh install.sh
```

Before making changes, the installer states that it is unofficial and asks whether to continue. Enter `y` or `yes` to proceed. An empty answer, a negative answer, or end of input cancels installation. Confirmation is read from the controlling terminal, so it also works with `curl | sh`. If no terminal is available, installation stops unless you explicitly pass `--yes`. A dry run displays the notice without asking for confirmation.

To run a local copy:

```sh
sh install.sh --dry-run
sh install.sh
```

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
| `-y`, `--yes` | Explicitly acknowledge the unofficial installer notice and skip the confirmation prompt |
| `--help` | Show help |

For unattended use, explicitly acknowledge the unofficial installer notice:

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
