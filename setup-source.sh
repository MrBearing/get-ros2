#!/bin/sh
# MIT License
#
# Copyright (c) 2026 MrBearing
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# This is an unofficial installer, not an official ROS 2 installer.
# POSIX sh; keep execution inside this block so an incomplete download cannot
# start installing packages. Official procedure: https://docs.ros.org/
{
set -u

PROGRAM=get-ros2-source
DRY_RUN=0
ASSUME_YES=0
TARGET_USER=
TARGET_HOME=
SWITCH_USER=0
DISTRO=
USE_SUDO=0
WORK_DIR=
LOG_FILE=
BOOTSTRAP_VERSION=1.3.0

say() { printf '[%s] %s\n' "$PROGRAM" "$*"; }

die() {
    printf '[%s] ERROR %s: %s\n' "$PROGRAM" "$1" "$2" >&2
    if [ -n "$LOG_FILE" ]; then
        printf 'Detailed log: %s\n' "$LOG_FILE" >&2
    fi
    exit "${3:-1}"
}

usage() {
    cat <<'USAGE'
ROS 2 source-build environment setup — Ubuntu LTS (amd64 / arm64)
This is an UNOFFICIAL installer, not an official ROS 2 installer.
Provided AS IS, WITHOUT WARRANTY OF ANY KIND.

Usage:
  curl -fsSL https://get-ros2.com/setup-source.sh | sh
  curl -fsSL https://get-ros2.com/setup-source.sh | sh -s -- [options]

Options:
  --distro NAME       humble / jazzy / lyrical (default: the LTS matching your OS)
  --dry-run           Show planned commands without sudo, network access, or file changes
  -y, --yes           Accept the UNOFFICIAL / WITHOUT WARRANTY notice and skip confirmation
  -h, --help          Show this help

Supported: Ubuntu 22.04 → Humble / 24.04 → Jazzy / 26.04 → Lyrical
USAGE
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --distro)
                [ "$#" -ge 2 ] || die E_ARGUMENT "$1 requires a value. See --help." 2
                DISTRO=$2
                shift 2
                ;;
            --dry-run) DRY_RUN=1; shift ;;
            -y|--yes) ASSUME_YES=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die E_ARGUMENT "Unknown argument: $1. See --help." 2 ;;
        esac
    done
    case "$DISTRO" in
        ''|humble|jazzy|lyrical) ;;
        *) die E_ARGUMENT "--distro must be humble, jazzy, or lyrical." 2 ;;
    esac
}

detect_platform() {
    KERNEL=$(uname -s) || die E_DETECTION 'Unable to detect the operating system.' 3
    case "$KERNEL" in
        Linux) ;;
        Darwin)
            die E_OS 'Automatic installation on macOS is not supported. Follow the official source build instructions: https://docs.ros.org/en/rolling/Installation/Alternatives/macOS-Development-Setup.html' 3 ;;
        MINGW*|MSYS*|CYGWIN*|Windows*)
            die E_OS 'On Windows, install Ubuntu 22.04, 24.04, or 26.04 on WSL 2 and run this script inside Ubuntu. For native Windows installation, see: https://docs.ros.org/en/rolling/Installation.html' 3 ;;
        *) die E_OS "Unsupported operating system: $KERNEL. See https://docs.ros.org/en/rolling/Installation.html" 3 ;;
    esac
    [ -r /etc/os-release ] || die E_OS 'Cannot detect the Linux distribution because /etc/os-release is missing or unreadable.' 3
    # os-release is a system-owned shell-compatible file, not a remote input.
    ID='' VERSION_ID='' VERSION_CODENAME='' UBUNTU_CODENAME='' PRETTY_NAME=''
    # shellcheck disable=SC1091
    . /etc/os-release
    [ "$ID" = ubuntu ] || die E_OS "Unsupported distribution: ${PRETTY_NAME:-$ID}. This installer uses official Ubuntu LTS deb packages and does not support Debian, RHEL-based distributions, or Ubuntu derivatives. Official instructions: https://docs.ros.org/en/rolling/Installation.html" 3
    case "$VERSION_ID" in
        22.04)
            EXPECTED_DISTRO=humble; CODENAME=jammy
            BOOTSTRAP_SHA256=110b9a462d55252decb8b7c816f61c2ba0d9890ce5fb93ac504e97cae5860d76 ;;
        24.04)
            EXPECTED_DISTRO=jazzy; CODENAME=noble
            BOOTSTRAP_SHA256=f31d84adf5054c7d60ded0e82c0f776a77ea33af53d08f40b9ad7c94cca55296 ;;
        26.04)
            EXPECTED_DISTRO=lyrical; CODENAME=resolute
            BOOTSTRAP_SHA256=e70bc980395f4a3b366b9c5e7f8f9b4d63a4064fb115f6ff3bc52f7faa02ef69 ;;
        20.04) die E_OS 'ROS 2 Foxy for Ubuntu 20.04 has reached end of life. Upgrade to a supported Ubuntu LTS release before running this installer.' 3 ;;
        *) die E_OS "Ubuntu $VERSION_ID is not supported. Use Ubuntu 22.04, 24.04, or 26.04." 3 ;;
    esac
    RELEASE_CODENAME=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
    [ -z "$RELEASE_CODENAME" ] || [ "$RELEASE_CODENAME" = "$CODENAME" ] ||
        die E_OS "The OS version and codename do not match: $VERSION_ID / $RELEASE_CODENAME. Check the state of your OS upgrade." 3
    if [ -z "$DISTRO" ]; then DISTRO=$EXPECTED_DISTRO; fi
    [ "$DISTRO" = "$EXPECTED_DISTRO" ] ||
        die E_DISTRO "Use $EXPECTED_DISTRO on Ubuntu $VERSION_ID. This setup script supports only the matching Ubuntu LTS/source distribution pair." 3
    command -v apt-get >/dev/null 2>&1 || die E_PACKAGE_MANAGER 'apt-get was not found. Run this installer in a standard Ubuntu environment.' 3
    command -v dpkg >/dev/null 2>&1 || die E_PACKAGE_MANAGER 'dpkg was not found. Run this installer in a standard Ubuntu environment.' 3
    ARCH=$(dpkg --print-architecture) || die E_DETECTION 'Unable to detect the package architecture.' 3
    case "$ARCH" in
        amd64|arm64) ;;
        *) die E_ARCH "Unsupported CPU architecture: $ARCH. A 64-bit Ubuntu installation (amd64 or arm64) is required." 3 ;;
    esac
    say "Detected: Ubuntu $VERSION_ID ($CODENAME) / $ARCH → ROS 2 $DISTRO source-build environment"
    if [ -n "${ROS_DISTRO:-}${AMENT_PREFIX_PATH:-}${CMAKE_PREFIX_PATH:-}" ]; then
        say 'Note: an existing build environment is loaded. Use a fresh shell without any ROS installation sourced when building ROS 2.'
    fi
}

confirm_installation() {
    say 'This is an UNOFFICIAL installer, not an official ROS 2 installer.'
    say 'Provided AS IS, WITHOUT WARRANTY OF ANY KIND.'
    [ "$DRY_RUN" -eq 0 ] || return 0
    if [ "$ASSUME_YES" -eq 1 ]; then
        say 'Proceeding with your explicit --yes confirmation.'
        return 0
    fi
    # Read from the controlling terminal, never from the script input stream.
    if ! ( : </dev/tty ) 2>/dev/null; then
        die E_CONFIRMATION 'Confirmation requires an interactive terminal. Rerun from a terminal, or use --yes to explicitly accept the UNOFFICIAL / WITHOUT WARRANTY notice.' 5
    fi
    printf 'Continue preparing the ROS 2 %s source-build environment with this UNOFFICIAL installer, provided WITHOUT WARRANTY? [y/N] ' "$DISTRO" >/dev/tty ||
        die E_CONFIRMATION 'Unable to display the confirmation prompt. No changes were made.' 5
    CONFIRMATION=''
    IFS= read -r CONFIRMATION </dev/tty || CONFIRMATION=''
    case "$CONFIRMATION" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) die E_CANCELLED 'Installation cancelled. No changes were made.' 5 ;;
    esac
}

require_privileges() {
    [ "$DRY_RUN" -eq 0 ] || return 0
    CURRENT_UID=$(id -u) || die E_PRIVILEGE 'Unable to determine the invoking user.' 4
    [ "$CURRENT_UID" -ne 0 ] || return 0
    command -v sudo >/dev/null 2>&1 || die E_PRIVILEGE 'sudo was not found. Ask an administrator to configure sudo access, or run this installer as root.' 4
    USE_SUDO=1
    if sudo -n -v 2>/dev/null; then return 0; fi
    # Never read a password from the pipe containing this script.
    if ( : </dev/tty ) 2>/dev/null; then
        say 'Installing packages requires sudo privileges.'
        # The invoking user intentionally opens their own controlling terminal.
        # shellcheck disable=SC2024
        sudo -v </dev/tty || die E_PRIVILEGE 'sudo authentication failed. Check your password and sudo permissions.' 4
    else
        die E_PRIVILEGE 'sudo authentication is required, but no controlling terminal is available. Run sudo -v in an interactive terminal and try again, or run this installer as root.' 4
    fi
}

cleanup() {
    if [ -n "$WORK_DIR" ]; then
        rm -f "$WORK_DIR/ros2-apt-source.deb" "$WORK_DIR/bootstrap.sha256" "$WORK_DIR/status" "$WORK_DIR/step.log"
    fi
}

init_log() {
    [ "$DRY_RUN" -eq 0 ] || return 0
    WORK_DIR=$(mktemp -d /tmp/get-ros2-source.XXXXXXXX) || die E_LOG 'Unable to create a temporary directory. Check free space and permissions on /tmp.'
    LOG_FILE=$WORK_DIR/install.log
    STEP_LOG=$WORK_DIR/step.log
    STATUS_FILE=$WORK_DIR/status
    (umask 077; : > "$LOG_FILE") || die E_LOG 'Unable to create the log file.'
    trap cleanup 0
    trap 'die E_INTERRUPTED "Installation was interrupted. Check the log and, if necessary, repair the package state with sudo dpkg --configure -a." 130' INT
    trap 'die E_INTERRUPTED "Installation was interrupted by a termination signal. Check the log." 143' TERM
    trap 'die E_INTERRUPTED "Installation was interrupted by a terminal hangup. Check the log." 129' HUP
    say "Detailed log: $LOG_FILE"
}

matches() { grep -Eiq -- "$1" "$STEP_LOG"; }

diagnose_failure() {
    FAILURE_CODE=E_COMMAND
    FAILURE_HINT='Review the original error at the end of the log. Packages installed so far remain installed.'
    if matches 'No space left on device|not enough free space|write error.*(space|disk)'; then
        FAILURE_CODE=E_DISK
        FAILURE_HINT='There is insufficient disk space or too few free inodes. Check df -h and df -i, free up space, and try again.'
    elif matches 'Read-only file system'; then
        FAILURE_CODE=E_READ_ONLY
        FAILURE_HINT='The filesystem is read-only. Check its mount state and investigate possible disk errors.'
    elif matches 'Could not resolve|Temporary failure resolving|Name or service not known|Could not resolve proxy'; then
        FAILURE_CODE=E_DNS
        FAILURE_HINT='Unable to resolve a hostname. Check DNS, network connectivity, and proxy settings.'
    elif matches 'certificate verification failed|certificate verify failed|certificate[[:space:]:].*(not trusted|issuer|expired|not yet valid|problem)|SSL (certificate|peer)|(^|[[:space:]:])TLS([[:space:]:]|v[0-9]).*(error|failed|handshake)|Could not handshake|curl: \((35|60|77)\)'; then
        FAILURE_CODE=E_TLS
        FAILURE_HINT='Unable to verify a TLS certificate. Check the system clock, ca-certificates, and any corporate proxy CA configuration. Do not disable certificate verification.'
    elif matches 'NO_PUBKEY|EXPKEYSIG|BADSIG|signatures couldn.t be verified|not signed|OpenPGP signature verification failed'; then
        FAILURE_CODE=E_SIGNATURE
        FAILURE_HINT='Unable to verify an APT repository signature. Check the repository named in the error and the signing key expiration date. For legacy ROS configuration, see the official migration instructions: https://github.com/ros-infrastructure/ros-apt-source'
    elif matches 'Conflicting values set for option Signed-By'; then
        FAILURE_CODE=E_REPOSITORY_CONFLICT
        FAILURE_HINT='The same APT repository has conflicting signing key settings. Check /etc/apt/sources.list and /etc/apt/sources.list.d/ for legacy or duplicate ROS entries. This installer does not automatically delete existing configuration.'
    elif matches 'Could not get lock|Unable to acquire.*lock|is another process using it|Waiting for cache lock'; then
        FAILURE_CODE=E_APT_LOCK
        FAILURE_HINT='Another APT, dpkg, or automatic update process is running. Wait for it to finish and try again. Do not delete lock files.'
    elif matches 'dpkg was interrupted'; then
        FAILURE_CODE=E_DPKG_INTERRUPTED
        FAILURE_HINT='A previous package operation was interrupted. Run sudo dpkg --configure -a and retry after it completes.'
    elif matches 'unmet dependencies|held broken packages|pkgProblemResolver|Unable to correct problems|Broken packages'; then
        FAILURE_CODE=E_DEPENDENCY
        FAILURE_HINT='Unable to resolve package dependencies. Check apt-mark showhold and the APT updates/security suites. On Ubuntu 24.04, also check noble-updates and noble-backports. Preview a repair with sudo apt-get -s --fix-broken install.'
    elif matches 'Packages need to be removed but remove is disabled'; then
        FAILURE_CODE=E_REMOVAL_REQUIRED
        FAILURE_HINT='Setup stopped because it would remove existing packages. Review the APT output, held packages, and Ubuntu updates before retrying.'
    elif matches 'Unable to locate package|has no installation candidate|does not have a Release file|no longer has a Release file|(^|[[:space:]])404([[:space:]]|$)|curl: \(22\)'; then
        FAILURE_CODE=E_REPOSITORY
        FAILURE_HINT='A package or repository is unavailable. Check the OS/ROS combination, APT sources, and HTTP status. For HTTP 403 or 429, also check proxy or server access limits.'
    elif matches 'Connection failed|Failed to fetch|Failed to connect|Could not connect|Connection timed out|Connection refused|Network is unreachable|curl: \((5|7|18|28|52|55|56)\)'; then
        FAILURE_CODE=E_NETWORK
        FAILURE_HINT='The download failed. Check your internet connection, firewall, and proxy settings, then try again.'
    elif matches 'Permission denied|are you root|a password is required|not in the sudoers|not allowed to execute|no tty present'; then
        FAILURE_CODE=E_PRIVILEGE
        FAILURE_HINT='Administrator privileges are missing or sudo authentication has expired. Run sudo -v, check your sudo permissions, and try again.'
    elif matches 'ros2-apt-source[.]deb: FAILED|checksum.*(mismatch|did NOT match)|no properly formatted checksum'; then
        FAILURE_CODE=E_CHECKSUM
        FAILURE_HINT='The downloaded file does not match the expected SHA-256 checksum. It may be corrupted or changed upstream. Installation has stopped. Check the official release and installer updates.'
    elif [ "$STEP_NAME" = 'Initialize rosdep system sources' ] || [ "$STEP_NAME" = 'Update the developer rosdep cache' ]; then
        FAILURE_CODE=E_ROSDEP
        FAILURE_HINT='Unable to prepare rosdep. Check the source URL and original error in the log, /etc/ros/rosdep/sources.list.d/, and permissions on your ~/.ros/rosdep cache. Rerun setup after correcting the problem.'
    elif [ "$STEP_NAME" = 'Verify the source-build tools' ]; then
        FAILURE_CODE=E_TOOLS
        FAILURE_HINT='A required development tool is missing or failed to start. Check the preceding package installation, PATH, and any custom Python environment, then rerun setup.'
    fi
    die "$FAILURE_CODE" "$STEP_NAME failed (exit code: $STEP_STATUS). $FAILURE_HINT"
}

run() {
    STEP_NAME=$1
    shift
    say "$STEP_NAME"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  +'
        printf ' %s' "$@"
        printf '\n'
        return 0
    fi
    printf '\n### %s\n' "$STEP_NAME" >> "$LOG_FILE" || die E_LOG 'Unable to write to the log file.'
    : > "$STEP_LOG" || die E_LOG 'Unable to write to the step log.'
    : > "$STATUS_FILE" || die E_LOG 'Unable to save the command exit status.'
    # POSIX sh has no pipefail. Persist the command's status separately from tee.
    # stdin is /dev/null so child programs cannot consume the curl | sh stream.
    (
        "$@" </dev/null
        COMMAND_STATUS=$?
        printf '%s\n' "$COMMAND_STATUS" > "$STATUS_FILE"
        exit "$COMMAND_STATUS"
    ) 2>&1 | tee -a "$LOG_FILE" "$STEP_LOG"
    TEE_STATUS=$?
    [ "$TEE_STATUS" -eq 0 ] || die E_LOG 'Unable to write log output. Check available disk space and the output destination.'
    STEP_STATUS=$(cat "$STATUS_FILE")
    case "$STEP_STATUS" in
        ''|*[!0-9]*) die E_LOG 'Unable to retrieve the command exit status.' ;;
        0) return 0 ;;
        *) diagnose_failure ;;
    esac
}

run_root() {
    ROOT_STEP=$1
    shift
    if [ "$USE_SUDO" -eq 1 ]; then
        run "$ROOT_STEP" sudo -n env LC_ALL=C DEBIAN_FRONTEND=noninteractive "$@"
    else
        run "$ROOT_STEP" env LC_ALL=C DEBIAN_FRONTEND=noninteractive "$@"
    fi
}

apt_update() {
    run_root "$1" apt-get -o APT::Update::Error-Mode=any -o Acquire::Retries=3 \
        -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update
}

apt_install() {
    INSTALL_STEP=$1
    shift
    run_root "$INSTALL_STEP" apt-get -y --no-remove -o DPkg::Lock::Timeout=60 \
        -o Dpkg::Use-Pty=0 -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold -o Acquire::Retries=3 \
        -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 install "$@"
}

setup_repository() {
    if [ "$DRY_RUN" -eq 0 ] &&
        [ "$(dpkg-query -W -f='${db:Status-Status}' ros2-apt-source 2>/dev/null)" = installed ]; then
        REPOSITORY_VERSION=$(dpkg-query -W -f='${Version}' ros2-apt-source 2>/dev/null)
        case "$REPOSITORY_VERSION" in
            *"~$CODENAME")
                if [ -r /etc/apt/sources.list.d/ros2.sources ] &&
                    grep -Eq "^Suites:[[:space:]]+${CODENAME}[[:space:]]*$" /etc/apt/sources.list.d/ros2.sources &&
                    ! grep -Eiq '^Enabled:[[:space:]]+no[[:space:]]*$' /etc/apt/sources.list.d/ros2.sources; then
                    say 'Using the installed ros2-apt-source package for this Ubuntu release.'
                    return 0
                fi ;;
        esac
        say 'Refreshing the ROS 2 repository configuration for this Ubuntu release.'
    fi
    BOOTSTRAP_URL=https://github.com/ros-infrastructure/ros-apt-source/releases/download/$BOOTSTRAP_VERSION/ros2-apt-source_$BOOTSTRAP_VERSION.${CODENAME}_all.deb
    BOOTSTRAP_FILE=${WORK_DIR:-/tmp/get-ros2-source.DRY-RUN}/ros2-apt-source.deb
    run 'Download the official repository configuration package' curl --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 3 \
        --connect-timeout 15 --max-time 180 --output "$BOOTSTRAP_FILE" "$BOOTSTRAP_URL"
    if [ "$DRY_RUN" -eq 0 ]; then
        printf '%s  %s\n' "$BOOTSTRAP_SHA256" "$BOOTSTRAP_FILE" > "$WORK_DIR/bootstrap.sha256" || die E_LOG 'Unable to create the checksum file.'
    fi
    run 'Verify the SHA-256 checksum' sha256sum --check "${WORK_DIR:-/tmp/get-ros2-source.DRY-RUN}/bootstrap.sha256"
    run_root 'Configure the ROS 2 APT repository and signing keys' dpkg --install "$BOOTSTRAP_FILE"
}

# A standalone download must include these helpers; no remote shell library is sourced.
select_user() {
    [ "$DRY_RUN" -eq 0 ] || return 0
    TARGET_USER=$(id -un) || die E_USER 'Unable to determine the invoking user.' 4
    TARGET_HOME=${HOME:-}
    if [ "$CURRENT_UID" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
        TARGET_UID=$(id -u "$SUDO_USER") || die E_USER 'The sudo invoking user no longer exists. Run this script directly as your normal user.' 4
        [ "$TARGET_UID" = "${SUDO_UID:-}" ] || die E_USER 'The sudo user identity is inconsistent. Run this script directly as your normal user.' 4
        TARGET_USER=$SUDO_USER
        TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
        command -v runuser >/dev/null 2>&1 || die E_USER 'runuser is required when invoking this script through sudo. Run this script directly as your normal user instead.' 4
        SWITCH_USER=1
    fi
    case "$TARGET_HOME" in
        /*) ;;
        *) die E_USER 'A valid absolute HOME directory is required for the rosdep cache. Run this script from your normal login shell.' 4 ;;
    esac
}

run_user() {
    USER_STEP=$1
    shift
    if [ "$SWITCH_USER" -eq 1 ]; then
        run "$USER_STEP" runuser -u "$TARGET_USER" -- env -u ROS_HOME -u PYTHONPATH -u PYTHONHOME \
            HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" "$@"
    else
        run "$USER_STEP" env -u ROS_HOME -u PYTHONPATH -u PYTHONHOME "$@"
    fi
}

prepare_source_environment() {
    # User caches must be writable by the developer, including when launched via sudo.
    # The child shell checks the selected developer's HOME.
    # shellcheck disable=SC2016
    run_user 'Check the developer home directory' sh -c \
        'test -d "$HOME" && test -w "$HOME" || { echo "Permission denied: HOME must be an existing writable directory" >&2; exit 1; }'
    apt_update 'Update Ubuntu package indexes'
    apt_install 'Install prerequisite packages' ca-certificates curl locales software-properties-common
    run_root 'Generate the UTF-8 locale' locale-gen en_US.UTF-8
    # Keep setup diagnostics in C; the printed build steps activate the generated locale.
    run_root 'Enable Ubuntu Universe' add-apt-repository --yes --no-update universe
    setup_repository
    apt_update 'Update package indexes including ROS 2'
    if [ "$DISTRO" = humble ]; then
        apt_install 'Upgrade systemd and udev packages on Ubuntu 22.04' \
            --only-upgrade systemd systemd-sysv udev libudev1 libsystemd0
    fi
    # Follow each distribution's official Ubuntu source-build prerequisites.
    set -- build-essential cmake git python3-pip python3-pytest-cov ros-dev-tools
    case "$DISTRO" in
        humble)
            set -- "$@" python3-flake8-docstrings python3-flake8-blind-except \
                python3-flake8-builtins python3-flake8-class-newline python3-flake8-comprehensions \
                python3-flake8-deprecated python3-flake8-import-order python3-flake8-quotes \
                python3-pytest-repeat python3-pytest-rerunfailures ;;
        jazzy|lyrical)
            set -- "$@" python3-mypy python3-pytest python3-pytest-mock python3-pytest-repeat \
                python3-pytest-rerunfailures python3-pytest-runner python3-pytest-timeout
            if [ "$DISTRO" = jazzy ]; then
                set -- "$@" python3-flake8-blind-except python3-flake8-class-newline python3-flake8-deprecated
            fi ;;
    esac
    apt_install "Install development tools for ROS 2 $DISTRO source builds" "$@"
    # shellcheck disable=SC2016
    run_user 'Verify the source-build tools' sh -c \
        'for tool in cc c++ cmake git rosdep vcs colcon; do command -v "$tool" || exit 1; done; rosdep --version && vcs --version && colcon --help'
    if [ "$DRY_RUN" -eq 1 ] || [ ! -e /etc/ros/rosdep/sources.list.d/20-default.list ]; then
        run_root 'Initialize rosdep system sources' rosdep init
    else
        say 'Using the existing rosdep sources. Existing configuration will not be overwritten.'
    fi
    run_user 'Update the developer rosdep cache' rosdep update --rosdistro "$DISTRO"
}

next_steps() {
    case "$DISTRO" in
        humble) SKIP_KEYS='fastcdr rti-connext-dds-6.0.1 urdfdom_headers' ;;
        jazzy) SKIP_KEYS='fastcdr rti-connext-dds-6.0.1 urdfdom_headers' ;;
        lyrical) SKIP_KEYS='fastcdr rti-connext-dds-7.7.0 urdfdom_headers' ;;
    esac
    say 'Next steps (not executed): use a fresh shell without any ROS installation sourced.'
    say 'Run as your normal user in a NEW workspace. Keep Ubuntu packages up to date.'
    cat <<STEPS

export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
mkdir -p "\$HOME/ros2_$DISTRO/src" &&
cd "\$HOME/ros2_$DISTRO" &&
curl -fL --proto '=https' --proto-redir '=https' https://raw.githubusercontent.com/ros2/ros2/$DISTRO/ros2.repos -o ros2.repos &&
vcs import --input ros2.repos src &&
rosdep install --from-paths src --ignore-src --rosdistro $DISTRO -y --skip-keys "$SKIP_KEYS" &&
colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release

# After a successful build, in each new terminal:
. "\$HOME/ros2_$DISTRO/install/local_setup.sh"
# Terminal 1:
ros2 run demo_nodes_cpp talker
# Terminal 2:
ros2 run demo_nodes_py listener
STEPS
    say 'The explicit Release build type avoids modifying your colcon mixin configuration.'
    say 'The source manifest tracks upstream branches. Record exact revisions with vcs export --exact src for reproducible builds.'
}

main() {
    parse_args "$@"
    LC_ALL=C
    export LC_ALL
    detect_platform
    confirm_installation
    require_privileges
    select_user
    init_log
    prepare_source_environment
    if [ "$DRY_RUN" -eq 1 ]; then
        say 'Dry run completed. The listed commands were not executed.'
    else
        say "ROS 2 $DISTRO source-build environment setup completed."
        say "The rosdep cache belongs to $TARGET_USER. No ROS 2 workspace was created or built."
        say "Detailed log: $LOG_FILE"
    fi
    next_steps
}

main "$@"
}
