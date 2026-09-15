#!/usr/bin/env bash
# Package-tool replacements for isolated regression tests only.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=/dev/null
source "$root/config"
name=${0##*/}
{
    printf '%s' "$name"
    printf ' %s' "$@"
    printf '\n'
} >> "$root/calls"
if [[ "$name" == "$MOCK_FAIL" && "$*" == *"$MOCK_CONTAINS"* ]]; then
    echo 'Connection timed out' >&2
    exit 28
fi
case "$name" in
    uname) echo "$MOCK_KERNEL" ;;
    id) echo "$MOCK_UID" ;;
    sudo)
        if [[ "$MOCK_SUDO_DENIED" == 1 ]]; then echo 'sudo: a password is required' >&2; exit 1; fi
        if [[ " $* " != *' -v '* ]]; then shift; exec "$@"; fi ;;
    dpkg) if [[ "$*" == --print-architecture ]]; then echo "$MOCK_ARCH"; fi ;;
    dpkg-query)
        [[ "$MOCK_EXISTING_SOURCE" == 1 ]] || exit 1
        echo installed ;;
    curl)
        while [[ "$1" != --output ]]; do shift; done
        if [[ "$MOCK_BAD_CHECKSUM" == 1 ]]; then
            echo corrupt > "$2"
        else
            printf 'test repository package\n' > "$2"
        fi ;;
    apt-get)
        [[ "$LC_ALL" == C && "$DEBIAN_FRONTEND" == noninteractive ]]
        [[ -z $(cat) ]] || { echo 'APT consumed installer input' >&2; exit 97; }
        if [[ " $* " == *' update '* ]]; then [[ "$*" == *APT::Update::Error-Mode=any* ]]; fi
        if [[ " $* " == *' install '* ]]; then [[ " $* " == *' --no-remove '* ]]; fi
        echo 'mock apt completed' ;;
    ros2)
        [[ "$*" == --help && -z "${ROS_DISTRO:-}" ]]
        echo 'usage: ros2' ;;
    locale-gen|add-apt-repository) ;;
    *) echo "Unexpected mock command: $name" >&2; exit 99 ;;
esac
