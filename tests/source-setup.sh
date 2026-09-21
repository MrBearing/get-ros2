#!/usr/bin/env bash
# Isolated source-setup tests; never modify the host's APT or rosdep configuration.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
installer=$(realpath "${1:-$directory/../setup-source.sh}")
root=$(mktemp -d /tmp/get-ros2-source-tests.tlS404.XXXXXXXX)
trap 'rm -r -- "$root"' EXIT
mkdir "$root/bin" "$root/home"
export TEST_SOURCE_ROOT=$root HOME=$root/home
unset SUDO_USER SUDO_UID ROS_DISTRO AMENT_PREFIX_PATH CMAKE_PREFIX_PATH
cat > "$root/bin/mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$TEST_SOURCE_ROOT/config"
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$TEST_SOURCE_ROOT/calls"
if [[ $name == "$FAIL_TOOL" && $* == *"$FAIL_MATCH"* ]]; then
    printf '%s\n' "$FAIL_TEXT" >&2
    exit 28
fi
case "$name" in
    uname) echo "$KERNEL" ;;
    dpkg) if [[ $* == --print-architecture ]]; then echo "$ARCH"; fi ;;
    dpkg-query) [[ $EXISTING_APT == 1 ]] || exit 1; echo installed ;;
    id)
        if [[ $1 == -un ]]; then echo developer
        elif [[ $# == 2 ]]; then echo 1000
        else echo "$USER_ID"; fi ;;
    getent) printf 'developer:x:1000:1000::%s/home:/bin/sh\n' "$TEST_SOURCE_ROOT" ;;
    runuser) [[ $1 == -u && $2 == developer && $3 == -- ]]; shift 3; exec "$@" ;;
    sudo) [[ $* != '-n -v' ]] || exit 0; [[ $1 == -n ]]; shift; exec "$@" ;;
    curl)
        while [[ $1 != --output ]]; do shift; done
        printf 'test repository package\n' > "$2" ;;
    apt-get)
        [[ $LC_ALL == C && $DEBIAN_FRONTEND == noninteractive ]]
        [[ -z $(cat) ]]
        [[ $* != *install* || $* == *--no-remove* ]] ;;
    rosdep)
        case "$1" in
            init) touch "$TEST_SOURCE_ROOT/rosdep-default.list" ;;
            update) [[ $HOME == "$TEST_SOURCE_ROOT/home" ]]; [[ -z ${ROS_HOME:-} ]]; touch "$HOME/cache-updated" ;;
            --version) echo 'rosdep test version' ;;
            *) exit 99 ;;
        esac ;;
    cc|c++|cmake|git|vcs|colcon|locale-gen|add-apt-repository) ;;
    *) exit 99 ;;
esac
MOCK
chmod +x "$root/bin/mock"
for tool in uname dpkg dpkg-query id getent runuser sudo curl apt-get rosdep cc c++ cmake git vcs colcon locale-gen add-apt-repository; do ln -s mock "$root/bin/$tool"; done
export PATH="$root/bin:$PATH"
sha=$(printf 'test repository package\n' | sha256sum); sha=${sha%% *}
sed -E -e "s|/etc/os-release|$root/os-release|g" \
    -e "s|/etc/ros/rosdep/sources.list.d/20-default.list|$root/rosdep-default.list|g" \
    -e "s|/tmp/get-ros2-source\.|$root/run.|g" \
    -e "s/BOOTSTRAP_SHA256=[a-f0-9]{64}/BOOTSTRAP_SHA256=$sha/g" "$installer" > "$root/setup.sh"
reset() {
    cat > "$root/config" <<'CONFIG'
KERNEL=Linux
ARCH=amd64
USER_ID=1000
EXISTING_APT=0
FAIL_TOOL=''
FAIL_MATCH=''
FAIL_TEXT='Connection timed out'
CONFIG
    printf '%s\n' "$@" >> "$root/config"
    printf 'ID=ubuntu\nVERSION_ID=24.04\nVERSION_CODENAME=noble\n' > "$root/os-release"
    find "$root" -maxdepth 1 -name 'run.*' -type d -exec rm -r -- {} +
    rm -f "$root/rosdep-default.list" "$HOME/cache-updated"
    : > "$root/calls"
}
run() {
    local expected=$1 status=0
    shift
    : > "$root/calls"
    timeout 30s setsid --wait "$@" </dev/null > "$root/stdout" 2> "$root/stderr" || status=$?
    [[ $status == "$expected" ]] || { cat "$root/stdout" "$root/stderr" >&2; echo "Expected $expected, got $status" >&2; exit 1; }
}
contains() { grep -Fq -- "$2" "$root/$1" || { cat "$root/$1" >&2; echo "Missing: $2" >&2; exit 1; }; }
absent() { if grep -Fq -- "$2" "$root/$1"; then cat "$root/$1" >&2; exit 1; fi; }
count=0
pass() { count=$((count+1)); printf 'ok %s - %s\n' "$count" "$*"; }
for shell in /bin/dash /bin/bash; do
    for spec in '22.04 jammy humble' '24.04 noble jazzy' '26.04 resolute lyrical'; do
        read -r version codename distro <<< "$spec"
        for arch in amd64 arm64; do
            reset "ARCH=$arch"
            printf 'ID=ubuntu\nVERSION_ID=%s\nVERSION_CODENAME=%s\n' "$version" "$codename" > "$root/os-release"
            run 0 "$shell" "$root/setup.sh" --yes
            contains calls 'ros-dev-tools'
            contains calls "rosdep update --rosdistro $distro"
            contains stdout "ROS 2 $distro source-build environment setup completed."
            contains calls 'locale-gen en_US.UTF-8'
            contains stdout 'export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8'
            absent calls "ros-$distro-desktop"
            absent calls 'vcs import'
            absent calls 'colcon build'
            [[ -f $HOME/cache-updated ]]
            if [[ $distro == humble ]]; then contains calls python3-flake8-quotes; fi
            if [[ $distro == jazzy ]]; then contains calls python3-flake8-deprecated; fi
            if [[ $distro == lyrical ]]; then absent calls python3-flake8; fi
            pass "$shell / $version / $arch"
        done
    done
    for answer in y yes no empty invalid eof; do
        reset
        # Reuse the terminal driver with this script's completion message.
        sed 's/{installation completed\.}/{source-build environment setup completed.}/' "$directory/confirm.exp" > "$root/confirm.exp"
        run 0 expect "$root/confirm.exp" "$root" "$root/setup.sh" "$shell" "$answer"
        pass "consent: $shell / $answer"
    done
done
reset
run 0 sh "$root/setup.sh" --dry-run
absent calls apt-get
absent calls rosdep
absent calls sudo
[[ ! -f $HOME/cache-updated && -z $(find "$root" -maxdepth 1 -name 'run.*') ]]
pass 'dry run makes no changes'
run 5 sh "$root/setup.sh"
contains stderr 'ERROR E_CONFIRMATION:'
absent calls apt-get
pass 'missing terminal requires explicit consent'
reset USER_ID=0
run 0 env SUDO_USER=developer SUDO_UID=1000 sh "$root/setup.sh" --yes
contains calls 'runuser -u developer -- env'
contains stdout 'cache belongs to developer'
pass 'sudo entry point uses developer cache'
run 4 env SUDO_USER=developer SUDO_UID=999 sh "$root/setup.sh" --yes
contains stderr 'ERROR E_USER:'
absent calls apt-get
pass 'inconsistent sudo identity rejected'
reset EXISTING_APT=1
run 0 sh "$root/setup.sh" --yes
run 0 sh "$root/setup.sh" --yes
absent calls 'rosdep init'
absent calls 'curl --'
contains calls 'rosdep update'
pass 'repeat run preserves existing configuration'
for args in '--distro' '--distro rolling' '--variant desktop'; do
    reset
    read -ra arguments <<< "$args"
    run 2 sh "$root/setup.sh" "${arguments[@]}"
    contains stderr 'ERROR E_ARGUMENT:'
    [[ ! -s $root/calls ]]
    pass "arguments: $args"
done
reset
run 3 sh "$root/setup.sh" --distro humble --yes
contains stderr 'ERROR E_DISTRO:'
absent calls apt-get
pass 'distribution mismatch'
for spec in 'KERNEL=Darwin' 'ARCH=armhf'; do
    reset "$spec"
    run 3 sh "$root/setup.sh" --yes
    absent calls apt-get
    pass "unsupported $spec"
done
reset
sed -i s/ubuntu/debian/ "$root/os-release"
run 3 sh "$root/setup.sh" --yes
contains stderr 'ERROR E_OS:'
pass 'unsupported distribution'
for spec in 'curl --output E_NETWORK' 'rosdep init E_ROSDEP' 'rosdep update E_ROSDEP' 'vcs --version E_TOOLS'; do
    read -r tool match code <<< "$spec"
    reset "FAIL_TOOL=$tool" "FAIL_MATCH=$match" "FAIL_TEXT='test tool failure'"
    if [[ $tool == curl ]]; then printf "FAIL_TEXT='Connection timed out'\n" >> "$root/config"; fi
    run 1 sh "$root/setup.sh" --yes
    contains stderr "ERROR $code:"
    absent stdout 'setup completed.'
    log=$(sed -n 's/^Detailed log: //p' "$root/stderr")
    [[ -f $log && $(stat -c %a "$log") == 600 ]]
    pass "failure: $tool $match"
done
reset
sed '$d' "$root/setup.sh" > "$root/truncated.sh"
run 2 sh "$root/truncated.sh" --yes
[[ ! -s $root/calls ]]
pass 'truncated script cannot execute'
while IFS=$'\t' read -r code raw hint; do
    [[ -n $code && $code != \#* ]] || continue
    reset 'FAIL_TOOL=apt-get' 'FAIL_MATCH=update'
    printf 'FAIL_TEXT=%q\n' "$raw" >> "$root/config"
    if [[ $code == E_REMOVAL_REQUIRED ]]; then
        hint='Setup stopped because it would remove existing packages. Review the APT output, held packages, and Ubuntu updates before retrying.'
    fi
    run 1 sh "$root/setup.sh" --yes
    expected="[get-ros2-source] ERROR $code: Update Ubuntu package indexes failed (exit code: 28). $hint"
    grep -Fxq -- "$expected" "$root/stderr" || { cat "$root/stderr" >&2; exit 1; }
    absent calls 'rosdep update'
    log=$(sed -n 's/^Detailed log: //p' "$root/stderr")
    grep -Fxq -- "$raw" "$log"
    [[ $(stat -c %a "$log") == 600 ]]
    pass "exact diagnostic and preserved log: $code"
done < "$directory/fixtures/errors.tsv"
printf 'Passed %s source setup regression cases\n' "$count"
