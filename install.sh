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

PROGRAM=get-ros2
DRY_RUN=0
ASSUME_YES=0
WITH_DEV_TOOLS=0
VARIANT=desktop
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
ROS 2 installer — Ubuntu LTS (amd64 / arm64)
This is an UNOFFICIAL installer, not an official ROS 2 installer.

Usage:
  curl -fsSL https://get-ros2.com/install.sh | sh
  curl -fsSL https://get-ros2.com/install.sh | sh -s -- [options]

Options:
  --distro NAME       humble / jazzy / lyrical (default: the LTS matching your OS)
  --variant NAME      desktop / ros-base (default: desktop)
  --with-dev-tools    Also install ros-dev-tools
  --dry-run           Show planned commands without sudo, network access, or file changes
  -y, --yes           Acknowledge the UNOFFICIAL installer notice and skip confirmation
  -h, --help          Show this help

Supported: Ubuntu 22.04 → Humble / 24.04 → Jazzy / 26.04 → Lyrical
USAGE
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --distro|--variant)
                [ "$#" -ge 2 ] || die E_ARGUMENT "$1 requires a value. See --help." 2
                case "$1" in
                    --distro) DISTRO=$2 ;;
                    --variant) VARIANT=$2 ;;
                esac
                shift 2
                ;;
            --with-dev-tools) WITH_DEV_TOOLS=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            -y|--yes) ASSUME_YES=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die E_ARGUMENT "Unknown argument: $1. See --help." 2 ;;
        esac
    done
    case "$VARIANT" in
        desktop|ros-base) ;;
        *) die E_ARGUMENT "--variant must be desktop or ros-base." 2 ;;
    esac
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
        die E_DISTRO "Use $EXPECTED_DISTRO on Ubuntu $VERSION_ID. The $DISTRO packages are not built for this OS release." 3
    command -v apt-get >/dev/null 2>&1 || die E_PACKAGE_MANAGER 'apt-get was not found. Run this installer in a standard Ubuntu environment.' 3
    command -v dpkg >/dev/null 2>&1 || die E_PACKAGE_MANAGER 'dpkg was not found. Run this installer in a standard Ubuntu environment.' 3
    ARCH=$(dpkg --print-architecture) || die E_DETECTION 'Unable to detect the package architecture.' 3
    case "$ARCH" in
        amd64|arm64) ;;
        *) die E_ARCH "Unsupported CPU architecture: $ARCH. A 64-bit Ubuntu installation (amd64 or arm64) is required." 3 ;;
    esac
    say "Detected: Ubuntu $VERSION_ID ($CODENAME) / $ARCH → ROS 2 $DISTRO ($VARIANT)"
    if [ -n "${ROS_DISTRO:-}" ] && [ "$ROS_DISTRO" != "$DISTRO" ]; then
        say "Note: ROS $ROS_DISTRO is already loaded in this shell. After installation, open a new shell and load $DISTRO."
    fi
}

confirm_installation() {
    say 'This is an UNOFFICIAL installer, not an official ROS 2 installer.'
    [ "$DRY_RUN" -eq 0 ] || return 0
    if [ "$ASSUME_YES" -eq 1 ]; then
        say 'Proceeding with your explicit --yes confirmation.'
        return 0
    fi
    # Read from the controlling terminal, never from the script input stream.
    if ! ( : </dev/tty ) 2>/dev/null; then
        die E_CONFIRMATION 'Confirmation requires an interactive terminal. Rerun from a terminal, or use --yes to explicitly accept the UNOFFICIAL installer notice.' 5
    fi
    printf 'Continue installing ROS 2 %s with this UNOFFICIAL installer? [y/N] ' "$DISTRO" >/dev/tty ||
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
    WORK_DIR=$(mktemp -d /tmp/get-ros2.XXXXXXXX) || die E_LOG 'Unable to create a temporary directory. Check free space and permissions on /tmp.'
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
        FAILURE_HINT='Installation stopped because it would remove existing packages. Preview the changes with sudo apt-get -s install ros-'"$DISTRO"'-'"$VARIANT"' and resolve missing OS updates or dependency problems.'
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
        say 'Using the installed ros2-apt-source package.'
        return 0
    fi
    BOOTSTRAP_URL=https://github.com/ros-infrastructure/ros-apt-source/releases/download/$BOOTSTRAP_VERSION/ros2-apt-source_$BOOTSTRAP_VERSION.${CODENAME}_all.deb
    BOOTSTRAP_FILE=${WORK_DIR:-/tmp/get-ros2.DRY-RUN}/ros2-apt-source.deb
    run 'Download the official repository configuration package' curl --fail --silent --show-error --location \
        --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 3 \
        --connect-timeout 15 --max-time 180 --output "$BOOTSTRAP_FILE" "$BOOTSTRAP_URL"
    if [ "$DRY_RUN" -eq 0 ]; then
        printf '%s  %s\n' "$BOOTSTRAP_SHA256" "$BOOTSTRAP_FILE" > "$WORK_DIR/bootstrap.sha256" || die E_LOG 'Unable to create the checksum file.'
    fi
    run 'Verify the SHA-256 checksum' sha256sum --check "${WORK_DIR:-/tmp/get-ros2.DRY-RUN}/bootstrap.sha256"
    run_root 'Configure the ROS 2 APT repository and signing keys' dpkg --install "$BOOTSTRAP_FILE"
}

install_ros() {
    apt_update 'Update Ubuntu package indexes'
    apt_install 'Install prerequisite packages' ca-certificates curl locales software-properties-common
    run_root 'Generate the UTF-8 locale' locale-gen en_US.UTF-8
    # Only this process uses this locale; preserve the user's system-wide locale.
    LANG=en_US.UTF-8
    export LANG
    run_root 'Enable Ubuntu Universe' add-apt-repository --yes --no-update universe
    setup_repository
    apt_update 'Update package indexes including ROS 2'
    if [ "$DISTRO" = humble ]; then
        # https://github.com/ros2/ros2/issues/1272 (early Ubuntu 22.04 images)
        apt_install 'Upgrade systemd and udev packages on Ubuntu 22.04' \
            --only-upgrade systemd systemd-sysv udev libudev1 libsystemd0
    fi
    set -- "ros-$DISTRO-$VARIANT"
    if [ "$WITH_DEV_TOOLS" -eq 1 ]; then set -- "$@" ros-dev-tools; fi
    apt_install "Install ROS 2 $DISTRO" "$@"
    # The child sh expands $1 after receiving the setup path as an argument.
    # shellcheck disable=SC2016
    run 'Verify the ROS 2 command' env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        HOME="${HOME:-/tmp}" LANG=en_US.UTF-8 sh -c \
        'test -r "$1" || { echo "ROS setup file is missing: $1" >&2; exit 1; }; . "$1"; command -v ros2 && ros2 --help' \
        sh "/opt/ros/$DISTRO/setup.sh"
}

main() {
    parse_args "$@"
    # Stable English diagnostics from external commands, independent of host locale.
    LC_ALL=C
    export LC_ALL
    detect_platform
    confirm_installation
    require_privileges
    init_log
    install_ros
    if [ "$DRY_RUN" -eq 1 ]; then
        say 'Dry run completed. The listed commands were not executed.'
    else
        say "ROS 2 $DISTRO installation completed."
        say "Run the following command in your current terminal: . /opt/ros/$DISTRO/setup.sh"
        say "For bash, you can also use source /opt/ros/$DISTRO/setup.bash; for zsh, use source /opt/ros/$DISTRO/setup.zsh."
        say "Detailed log: $LOG_FILE"
    fi
}

main "$@"
}
