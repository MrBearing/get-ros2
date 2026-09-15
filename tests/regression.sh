#!/usr/bin/env bash
# Isolated platform, command-flow and terminal tests using Bash and Expect.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
installer=$(realpath "${1:-install.sh}")
root=$(mktemp -d /tmp/get-ros2-regression.XXXXXXXX)
trap 'rm -rf -- "$root"' EXIT
mkdir "$root/bin"
cp "$directory/mock-command.sh" "$root/bin/mock"
chmod +x "$root/bin/mock"
for name in uname id sudo dpkg dpkg-query curl apt-get locale-gen add-apt-repository ros2; do
    ln -s mock "$root/bin/$name"
done
export PATH="$root/bin:$PATH" ROS_DISTRO=other
sha=$(printf 'test repository package\n' | sha256sum)
sha=${sha%% *}
sed -E -e "s|/etc/os-release|$root/os-release|g" \
    -e "s|/opt/ros/|$root/opt/ros/|g" -e "s|/tmp/get-ros2\.|$root/run.|g" \
    -e "s/BOOTSTRAP_SHA256=[a-f0-9]{64}/BOOTSTRAP_SHA256=$sha/g" \
    "$installer" > "$root/install.sh"
for distro in humble jazzy lyrical; do
    mkdir -p "$root/opt/ros/$distro"
    # PATH is expanded later when the child shell sources this setup file.
    # shellcheck disable=SC2016
    printf 'export PATH="%s/bin:$PATH"\n' "$root" > "$root/opt/ros/$distro/setup.sh"
done
count=0
pass() { count=$((count + 1)); printf 'ok %s - %s\n' "$count" "$*"; }
fail() { cat "$root/stdout" "$root/stderr" >&2; echo "FAIL: $*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$root/$1" || fail "Missing $2 in $1"; }
absent() { if grep -Fq -- "$2" "$root/$1"; then fail "Unexpected $2 in $1"; fi; }
set_os() {
    printf 'ID=%s\nVERSION_ID=%s\nVERSION_CODENAME=%s\n' "${3:-ubuntu}" "$1" "$2" > "$root/os-release"
}
reset() {
    cat > "$root/config" <<'CONFIG'
MOCK_KERNEL=Linux
MOCK_ARCH=amd64
MOCK_UID=0
MOCK_SUDO_DENIED=0
MOCK_EXISTING_SOURCE=0
MOCK_BAD_CHECKSUM=0
MOCK_FAIL=''
MOCK_CONTAINS=''
CONFIG
    printf '%s\n' "$@" >> "$root/config"
    rm -rf -- "$root"/run.*
    : > "$root/calls"
    set_os 24.04 noble
}
run() {
    local expected=$1 status=0
    shift
    : > "$root/calls"
    timeout 20s setsid --wait "$@" </dev/null > "$root/stdout" 2> "$root/stderr" || status=$?
    [[ "$status" == "$expected" ]] || fail "Expected exit $expected, got $status"
}
run_pipe() {
    local expected=$1 shell=$2 status=0
    shift 2
    : > "$root/calls"
    # A pipe is part of the behavior being tested.
    # shellcheck disable=SC2002
    cat "$root/install.sh" | timeout 20s setsid --wait "$shell" -s -- "$@" \
        > "$root/stdout" 2> "$root/stderr" || status=$?
    [[ "$status" == "$expected" ]] || fail "Expected exit $expected, got $status"
}
read_only() {
    if grep -Ev '^(uname|dpkg) ' "$root/calls"; then fail 'Unexpected command before consent'; fi
    [[ -z $(find "$root" -maxdepth 1 -name 'run.*' -print) ]] || fail 'Unexpected files'
}

for shell in /bin/dash /bin/bash; do
    for spec in '22.04 jammy humble' '24.04 noble jazzy' '26.04 resolute lyrical'; do
        read -r version codename distro <<< "$spec"
        for arch in amd64 arm64; do
            reset "MOCK_ARCH=$arch"
            set_os "$version" "$codename"
            run_pipe 0 "$shell" --yes
            contains stdout 'installation completed.'
            contains calls "ros-$distro-desktop"
            contains calls 'ros2 --help'
            if [[ "$distro" == humble ]]; then contains calls --only-upgrade; else absent calls --only-upgrade; fi
            pass "pipe installation: $shell / $version / $arch"
        done
    done
done

reset MOCK_UID=1000
run_pipe 0 /bin/sh --yes --distro jazzy --variant ros-base --with-dev-tools
contains calls 'ros-jazzy-ros-base ros-dev-tools'
contains calls 'sudo -n'
pass 'variant, development tools and sudo'

reset MOCK_UID=1000 MOCK_SUDO_DENIED=1
run 0 /bin/sh "$root/install.sh" --dry-run
contains stdout 'not an official ROS 2 installer'
absent stdout '[y/N]'
read_only
pass 'dry run without consent or changes'
run 5 /bin/sh "$root/install.sh"
contains stderr 'ERROR E_CONFIRMATION:'
read_only
pass 'missing terminal stops before changes'
# The inner shell receives the installer path as its first positional argument.
# shellcheck disable=SC2016
run 5 /bin/sh -c 'printf "yes\n" | sh "$1"' sh "$root/install.sh"
contains stderr 'ERROR E_CONFIRMATION:'
read_only
pass 'piped yes is not interactive consent'
run_pipe 4 /bin/sh --yes
contains stderr 'ERROR E_PRIVILEGE:'
absent calls apt-get
pass 'sudo authentication failure'

for args in '--unknown' '--distro' '--variant invalid' '--distro rolling'; do
    reset
    read -ra arguments <<< "$args"
    run 2 /bin/sh "$root/install.sh" "${arguments[@]}"
    contains stderr 'ERROR E_ARGUMENT:'
    [[ ! -s "$root/calls" ]]
    pass "invalid arguments: $args"
done
run 0 /bin/sh "$root/install.sh" --help
contains stdout 'not an official ROS 2 installer'
[[ ! -s "$root/calls" ]]
pass help

for spec in '20.04 focal ubuntu' '25.10 questing ubuntu' '24.04 jammy ubuntu' '12 bookworm debian' '22 noble linuxmint' '9 none rhel'; do
    reset
    read -r version codename os_id <<< "$spec"
    set_os "$version" "$codename" "$os_id"
    run 3 /bin/sh "$root/install.sh" --yes
    contains stderr 'ERROR E_OS:'
    read_only
    pass "unsupported OS: $spec"
done
for kernel in Darwin MINGW64_NT FreeBSD; do
    reset "MOCK_KERNEL=$kernel"
    run 3 /bin/sh "$root/install.sh" --yes
    contains stderr 'ERROR E_OS:'
    read_only
    pass "unsupported kernel: $kernel"
done
for arch in armhf i386; do
    reset "MOCK_ARCH=$arch"
    run 3 /bin/sh "$root/install.sh" --yes
    contains stderr 'ERROR E_ARCH:'
    read_only
    pass "unsupported architecture: $arch"
done
reset
run 3 /bin/sh "$root/install.sh" --distro humble
contains stderr 'ERROR E_DISTRO:'
read_only
pass 'incompatible ROS distribution'
rm "$root/os-release"
run 3 /bin/sh "$root/install.sh"
contains stderr 'ERROR E_OS:'
read_only
pass 'missing OS metadata'

for iteration in 1 2; do
    reset MOCK_EXISTING_SOURCE=1
    run 0 /bin/sh "$root/install.sh" --yes
    absent calls 'curl --'
    absent calls 'dpkg --install'
    pass "reuse existing repository package: $iteration"
done
reset MOCK_BAD_CHECKSUM=1
run 1 /bin/sh "$root/install.sh" --yes
contains stderr 'ERROR E_CHECKSUM:'
contains stderr 'The downloaded file does not match the expected SHA-256 checksum.'
absent calls 'dpkg --install'
pass 'checksum failure stops before repository installation'
for spec in 'curl --output' 'dpkg --install' 'apt-get ros-jazzy-desktop' 'ros2 --help'; do
    reset
    read -r command match <<< "$spec"
    printf 'MOCK_FAIL=%s\nMOCK_CONTAINS=%s\n' "$command" "$match" >> "$root/config"
    run 1 /bin/sh "$root/install.sh" --yes
    contains stderr 'ERROR E_NETWORK:'
    contains stderr 'exit code: 28'
    absent stdout 'installation completed.'
    pass "failure at $command $match"
done

reset
sed '$d' "$root/install.sh" > "$root/truncated.sh"
run 2 /bin/sh "$root/truncated.sh" --yes
[[ ! -s "$root/calls" ]]
pass 'truncated download cannot execute'

for shell in /bin/dash /bin/bash; do
    for answer in y yes no empty invalid eof; do
        reset MOCK_UID=1000
        run 0 expect "$directory/confirm.exp" "$root" "$root/install.sh" "$shell" "$answer"
        if [[ "$answer" == y || "$answer" == yes ]]; then contains calls apt-get; else read_only; fi
        pass "terminal confirmation: $shell / $answer"
    done
done
for flag in --yes -y; do
    reset
    run_pipe 0 /bin/sh "$flag"
    contains stdout 'explicit --yes confirmation'
    pass "explicit consent: $flag"
done
printf 'Passed %s shell regression cases\n' "$count"
