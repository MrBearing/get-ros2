#!/usr/bin/env bash
# Exercise repository scripts through a pipe without running package tools or sudo.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(mktemp -d /tmp/get-ros2-environment.XXXXXXXX)
trap 'rm -r -- "$root"' EXIT
mkdir "$root/bin"
export TEST_ENV_ROOT=$root TEST_ENV_ARCH=amd64
unset GET_ROS2_DISTRO GET_ROS2_VARIANT ROS_DISTRO
cat > "$root/bin/mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$TEST_ENV_ROOT/calls"
case "$name:$*" in
    uname:-s) echo Linux ;;
    dpkg:--print-architecture) echo "$TEST_ENV_ARCH" ;;
    *) echo 'Unexpected command: environment tests must not modify the system.' >&2; exit 99 ;;
esac
MOCK
chmod +x "$root/bin/mock"
for tool in uname dpkg apt-get sudo id curl dpkg-query locale-gen add-apt-repository rosdep runuser; do
    ln -s mock "$root/bin/$tool"
done
export PATH="$root/bin:$PATH"
for script in install.sh setup-source.sh; do
    sed "s|/etc/os-release|$root/os-release|g" "$directory/../$script" > "$root/$script"
done
count=0
pass() { count=$((count + 1)); printf 'ok %s - %s\n' "$count" "$*"; }
fail() { cat "$root/stdout" "$root/stderr" >&2; echo "FAIL: $*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$root/$1" || fail "Missing $2 in $1"; }
set_os() { printf 'ID=ubuntu\nVERSION_ID=%s\nVERSION_CODENAME=%s\n' "$1" "$2" > "$root/os-release"; }
run() {
    local expected=$1 script=$2 status=0
    shift 2
    local environment=()
    while [[ $1 != -- ]]; do environment+=("$1"); shift; done
    shift
    : > "$root/calls"
    # Assign configuration to the consuming shell, exactly as in curl | VAR=value sh.
    # shellcheck disable=SC2002
    cat "$root/$script" | env "${environment[@]}" timeout 20s setsid --wait "$shell" -s -- "$@" \
        > "$root/stdout" 2> "$root/stderr" || status=$?
    [[ $status == "$expected" ]] || fail "Expected exit $expected, got $status: $script / $shell"
    if grep -Ev '^(uname|dpkg) ' "$root/calls"; then fail 'A modifying command was executed'; fi
}
selected() {
    local script=$1 distro=$2 variant=${3:-desktop}
    if [[ $script == install.sh ]]; then
        contains stdout "ROS 2 $distro ($variant)"
        contains stdout "ros-$distro-$variant"
    else
        contains stdout "ROS 2 $distro source-build environment"
        contains stdout "rosdep update --rosdistro $distro"
    fi
}
for shell in /bin/dash /bin/bash; do
    for script in install.sh setup-source.sh; do
        set_os 26.04 resolute
        TEST_ENV_ARCH=amd64
        default=lyrical
        [[ $script != setup-source.sh ]] || default=rolling
        run 0 "$script" -- --dry-run
        selected "$script" "$default"
        pass "unset environment uses defaults: $shell / $script"
        run 0 "$script" GET_ROS2_DISTRO= GET_ROS2_VARIANT= -- --dry-run
        selected "$script" "$default"
        pass "empty environment uses defaults: $shell / $script"
        run 0 "$script" ROS_DISTRO=humble -- --dry-run
        selected "$script" "$default"
        pass "inherited ROS_DISTRO does not configure installation: $shell / $script"

        specs=('22.04 jammy humble' '24.04 noble jazzy' '26.04 resolute lyrical')
        [[ $script != setup-source.sh ]] || specs+=('26.04 resolute rolling')
        for spec in "${specs[@]}"; do
            read -r version codename distro <<< "$spec"
            set_os "$version" "$codename"
            for TEST_ENV_ARCH in amd64 arm64; do
                run 0 "$script" "GET_ROS2_DISTRO=$distro" GET_ROS2_VARIANT=ros-base -- --dry-run
                selected "$script" "$distro" ros-base
                pass "environment selection: $shell / $script / $version / $TEST_ENV_ARCH / $distro"
            done
        done
        set_os 26.04 resolute
        TEST_ENV_ARCH=amd64
        arguments=(--dry-run --distro "$default")
        [[ $script != install.sh ]] || arguments+=(--variant ros-base)
        run 0 "$script" GET_ROS2_DISTRO=invalid GET_ROS2_VARIANT=invalid -- "${arguments[@]}"
        selected "$script" "$default" ros-base
        pass "CLI overrides invalid environment before validation: $shell / $script"
        run 0 "$script" GET_ROS2_DISTRO=jazzy -- --dry-run --distro "$default"
        selected "$script" "$default"
        pass "CLI overrides a valid but OS-incompatible environment value: $shell / $script"

        for value in invalid 'lyrical '; do
            run 2 "$script" "GET_ROS2_DISTRO=$value" -- --dry-run
            contains stderr 'ERROR E_ARGUMENT:'
            contains stderr 'GET_ROS2_DISTRO'
            [[ ! -s $root/calls ]] || fail 'Invalid environment reached platform detection'
            pass "invalid distro rejected before commands: $shell / $script / [$value]"
        done
        run 3 "$script" GET_ROS2_DISTRO=humble -- --dry-run
        contains stderr 'ERROR E_DISTRO:'
        pass "OS-incompatible environment distro rejected: $shell / $script"
        status=0
        [[ $script != setup-source.sh ]] || status=2
        run "$status" "$script" "GET_ROS2_DISTRO=$default" -- --dry-run --distro ''
        if [[ $script == install.sh ]]; then selected "$script" lyrical; else contains stderr 'ERROR E_ARGUMENT:'; fi
        pass "explicit empty CLI distro retains existing behavior: $shell / $script"

        run 0 "$script" GET_ROS2_DISTRO=invalid GET_ROS2_VARIANT=invalid -- --help
        contains stdout GET_ROS2_DISTRO
        [[ ! -s $root/calls ]] || fail 'Help executed commands'
        pass "help remains available with invalid environment: $shell / $script"
        run 5 "$script" GET_ROS2_YES=1 GET_ROS2_DRY_RUN=1 --
        contains stderr 'ERROR E_CONFIRMATION:'
        pass "environment cannot bypass consent or enable dry run: $shell / $script"

        if [[ $script == install.sh ]]; then
            for variant in desktop ros-base; do
                run 0 "$script" "GET_ROS2_VARIANT=$variant" -- --dry-run
                selected "$script" lyrical "$variant"
                pass "variant environment: $shell / $variant"
            done
            run 2 "$script" GET_ROS2_VARIANT=invalid -- --dry-run
            contains stderr 'ERROR E_ARGUMENT:'
            contains stderr GET_ROS2_VARIANT
            [[ ! -s $root/calls ]] || fail 'Invalid variant reached platform detection'
            pass "invalid variant rejected before commands: $shell"
            run 2 "$script" GET_ROS2_VARIANT=ros-base -- --dry-run --variant ''
            contains stderr 'ERROR E_ARGUMENT:'
            pass "explicit empty CLI variant overrides environment and fails: $shell"
        else
            run 0 "$script" GET_ROS2_VARIANT=invalid -- --dry-run
            selected "$script" rolling
            pass "source setup ignores binary variant configuration: $shell"
            for spec in '22.04 jammy' '24.04 noble'; do
                read -r version codename <<< "$spec"
                set_os "$version" "$codename"
                run 3 "$script" GET_ROS2_DISTRO= -- --dry-run
                contains stderr 'ERROR E_DISTRO:'
                pass "empty source environment still requires explicit stable selection: $shell / $version"
            done
        fi
    done
done
printf 'Passed %s environment configuration cases\n' "$count"
