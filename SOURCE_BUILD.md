# Build ROS 2 from source

`setup-source.sh` prepares the tools needed to build ROS 2 from source on Ubuntu. Use it when you want to modify ROS 2 itself. For a ready-to-use binary installation, use [install.sh](README.md).

**This is an UNOFFICIAL setup script, not an official ROS 2 installer.**

**Provided AS IS, WITHOUT WARRANTY OF ANY KIND.**

## Supported environments

| Ubuntu | ROS 2 | Architecture |
| --- | --- | --- |
| 22.04 LTS | Humble | amd64 / arm64 |
| 24.04 LTS | Jazzy | amd64 / arm64 |
| 26.04 LTS | Lyrical | amd64 / arm64 |

Only these matching pairs are supported, including Ubuntu on WSL 2. Other operating systems, Ubuntu derivatives, and 32-bit systems are rejected before changes are made.

The development packages follow the official source-build guides for [Humble](https://github.com/ros2/ros2_documentation/blob/humble/source/Installation/Alternatives/Ubuntu-Development-Setup.rst), [Jazzy](https://github.com/ros2/ros2_documentation/blob/jazzy/source/Installation/Alternatives/Ubuntu-Development-Setup.rst), and [Lyrical](https://github.com/ros2/ros2_documentation/blob/lyrical/source/Get-Started/Installation/Alternatives/Ubuntu-Development-Setup.rst).

Requirements: a working Ubuntu APT configuration, internet access to Ubuntu/ROS repositories and GitHub, a writable home directory, and root or sudo privileges. Keep Ubuntu packages up to date before building. A full source checkout and build require considerably more disk space and memory than the setup script itself; requirements depend on the packages and build parallelism. On memory-limited machines, reduce build parallelism as shown below.

## Prepare the environment

Review [setup-source.sh](setup-source.sh) before running it. Run this as your normal development user:

```sh
curl -fsSL https://get-ros2.com/setup-source.sh | sh
```

The script displays the UNOFFICIAL / WITHOUT WARRANTY notice and asks for confirmation before modifying the system. Without a controlling terminal it stops, unless you explicitly acknowledge the notice with `--yes`.

| Option | Behavior |
| --- | --- |
| `--distro humble\|jazzy\|lyrical` | Validate the selected distribution against Ubuntu; select automatically when omitted |
| `--dry-run` | Display planned commands and follow-up instructions without installing packages, using the network, or creating files |
| `--yes`, `-y` | Explicitly accept the notice and skip confirmation |
| `--help`, `-h` | Show usage |

```sh
sh setup-source.sh --dry-run
sh setup-source.sh --distro jazzy
```

Setup installs build tools and the distribution-specific development/test packages, configures the ROS APT repository and UTF-8 locale, initializes rosdep when needed, and updates your rosdep cache. Python packages required by ROS tooling are installed through APT; the script does not run `sudo pip` or bypass Ubuntu's Python package protection.

It does not install the ROS desktop/ros-base metapackage, clone ROS repositories, create a workspace, resolve workspace-specific dependencies, or build ROS 2. Those steps follow below. `install.sh --with-dev-tools` installs binary ROS 2 alongside development tools; it does not replace this source-build setup procedure.

## Verify the setup script

### Website version

Both the script and its SHA-256 checksum are published together. This command executes the setup script only when every download and the checksum verification succeed:

<!-- BEGIN verify-pages -->
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
<!-- END verify-pages -->

### Specific release

Replace `vX.Y.Z` with a release tag whose Assets include the source setup script. Older releases may provide only the binary installer.

<!-- BEGIN verify-release -->
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
<!-- END verify-release -->

Success prints `setup-source.sh: OK`. A failed check stops setup; obtain a matching pair from the same release before retrying. The website can serve an older release than GitHub's latest release. A checksum is not a digital signature and cannot independently authenticate the publisher if both files are replaced.

## Get the sources and build

Use a **fresh shell without any ROS installation sourced**, including automatic sourcing in `.bashrc`. Existing binary installations can stay installed, but must not be loaded into the build environment. The setup script prints commands for your detected distribution.

The example below uses Jazzy on Ubuntu 24.04. Change `distro` to `humble` on Ubuntu 22.04 or `lyrical` on Ubuntu 26.04. Run as your normal user in a **new workspace**; existing checkouts are not automatically replaced or repaired. Setup generates `en_US.UTF-8` but keeps its own diagnostics in English and does not change your login locale. The exports below activate UTF-8 for the build shell, including systems whose default locale is `C`. Repeat them in each new build shell.

```sh
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
distro=jazzy
case "$distro" in
  humble|jazzy) skip_keys='fastcdr rti-connext-dds-6.0.1 urdfdom_headers' ;;
  lyrical) skip_keys='fastcdr rti-connext-dds-7.7.0 urdfdom_headers' ;;
esac
mkdir -p "$HOME/ros2_$distro/src" &&
cd "$HOME/ros2_$distro" &&
curl -fL --proto '=https' --proto-redir '=https' \
  "https://raw.githubusercontent.com/ros2/ros2/$distro/ros2.repos" -o ros2.repos &&
vcs import --input ros2.repos src &&
rosdep install --from-paths src --ignore-src --rosdistro "$distro" -y --skip-keys "$skip_keys" &&
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release
```

`rosdep install` needs the checked-out sources to determine additional system dependencies and may request sudo authentication. The skip keys follow the distribution's official instructions. The explicit CMake Release build type avoids changing existing colcon mixin configuration.

On machines with limited memory, replace the final build command with:

```sh
MAKEFLAGS=-j2 CMAKE_BUILD_PARALLEL_LEVEL=2 \
  colcon build --symlink-install --executor sequential --cmake-args -DCMAKE_BUILD_TYPE=Release
```

Upstream manifests track branches that can change independently of this setup script's release. After a successful checkout, save the exact revisions with `vcs export --exact src > ros2-exact.repos` and keep that manifest with your build records. A pinned installer version alone does not pin the ROS sources or APT packages.

After the build succeeds, source the workspace in each terminal. For example, with Jazzy:

```sh
. "$HOME/ros2_jazzy/install/local_setup.sh"
ros2 run demo_nodes_cpp talker
```

In a second terminal:

```sh
. "$HOME/ros2_jazzy/install/local_setup.sh"
ros2 run demo_nodes_py listener
```

The talker should print `Publishing:` and the listener should print `I heard:`. Use the matching workspace path for Humble or Lyrical.

## Existing environments and repeat runs

- Installed development packages and the ROS APT configuration are reused. APT may upgrade requested packages but is not allowed to remove packages automatically.
- Existing rosdep source configuration is preserved; failures are not treated as successful initialization.
- rosdep cache updates run as the development user. If invoked through sudo, setup uses the verified sudo user and their home directory. Direct root execution prepares root's cache, which is appropriate for a root-only container; other developers must run `rosdep update --rosdistro DISTRO` themselves.
- The script does not edit shell startup files, delete existing ROS installations, or change workspace contents.
- Rerunning setup does not reset a failed or modified checkout. Inspect the original checkout/build error before retrying those separate steps.

## Errors and logs

Output and diagnostics are in English. Failed external commands stop setup and preserve a private log at `/tmp/get-ros2-source.XXXXXXXX/install.log`. Files already installed remain installed.

The [binary installer's error categories and exit codes](README.md#errors-and-logs) also apply. Source setup additionally reports `E_USER` (exit 4) for an invalid user/home configuration, `E_ROSDEP` (exit 1) for rosdep initialization/update errors, and `E_TOOLS` (exit 1) when a required development tool fails verification. Known network, certificate, permissions, APT, and disk errors take precedence over these tool-specific categories.

For cache permission errors, check ownership of your `~/.ros/rosdep` directory. Run `rosdep update` as your normal user; running it with sudo can create root-owned cache files. Build failures occur after setup and have their own `colcon` logs in the workspace.
