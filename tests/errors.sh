#!/usr/bin/env bash
# Exercise the unmodified installer with controlled package-manager failures.
set -euo pipefail

installer=$(realpath "${1:-install.sh}")
fixtures=$(cd -- "$(dirname -- "$0")" && pwd)/fixtures/errors.tsv
sandbox=$(mktemp -d /tmp/get-ros2-errors.XXXXXXXX)
cleanup() {
    local log directory
    if [[ -f "$sandbox/logs" ]]; then
        while IFS= read -r log; do
            directory=${log%/install.log}
            if [[ "$directory" =~ ^/tmp/get-ros2\.[a-zA-Z0-9]{8}$ ]]; then
                rm -rf -- "$directory"
            fi
        done < "$sandbox/logs"
    fi
    rm -rf -- "$sandbox"
}
trap cleanup EXIT
mkdir "$sandbox/bin"

cat > "$sandbox/bin/apt-get" <<'STUB'
#!/bin/sh
[ "$LC_ALL" = C ] && [ "$DEBIAN_FRONTEND" = noninteractive ] || exit 97
printf '%s\n' "$*" >> "$TEST_CALLS"
printf '%s\n' "$TEST_ERROR" >&2
exit 100
STUB
cat > "$sandbox/bin/id" <<'STUB'
#!/bin/sh
printf '0\n'
STUB
cat > "$sandbox/bin/blocked" <<'STUB'
#!/bin/sh
printf 'UNEXPECTED MUTATION: %s\n' "$0" >> "$TEST_CALLS"
exit 98
STUB
cat > "$sandbox/bin/dpkg" <<'STUB'
#!/bin/sh
if [ "$*" = --print-architecture ]; then exec /usr/bin/dpkg "$@"; fi
exec "${0%/*}/blocked"
STUB
for name in sudo curl locale-gen add-apt-repository; do
    ln -s blocked "$sandbox/bin/$name"
done
chmod +x "$sandbox/bin/"*
export TEST_CALLS="$sandbox/calls" TEST_ERROR
test_path="$sandbox/bin:$PATH"
# shellcheck source=/dev/null
source /etc/os-release
case "$VERSION_ID" in
    22.04) distro=humble ;;
    24.04) distro=jazzy ;;
    26.04) distro=lyrical ;;
    *) echo "Run this suite on a supported Ubuntu release" >&2; exit 1 ;;
esac
count=0
while IFS=$'\t' read -r code raw hint; do
    [[ -n "$code" && "$code" != \#* ]] || continue
    TEST_ERROR=$raw
    hint=${hint//DISTRO/$distro}
    : > "$TEST_CALLS"
    status=0
    # No source rewriting: this also runs directly against the downloaded file.
    # Keep a real pipe to exercise the documented curl | sh execution mode.
    # shellcheck disable=SC2002
    cat "$installer" | PATH="$test_path" timeout 20s setsid --wait sh -s -- --yes \
        > "$sandbox/stdout" 2> "$sandbox/stderr" || status=$?
    log=$(sed -n 's/^Detailed log: //p' "$sandbox/stderr")
    [[ -z "$log" ]] || printf '%s\n' "$log" >> "$sandbox/logs"
    expected="[get-ros2] ERROR $code: Update Ubuntu package indexes failed (exit code: 100). $hint"
    if [[ "$status" != 1 ]] || ! grep -Fxq -- "$expected" "$sandbox/stderr"; then
        cat "$sandbox/stdout" "$sandbox/stderr" >&2
        printf 'FAIL %s: expected exit 1 and exact diagnostic:\n%s\n' "$code" "$expected" >&2
        exit 1
    fi
    [[ $(wc -l < "$TEST_CALLS") -eq 1 ]] || { echo 'Commands continued after failure' >&2; exit 1; }
    grep -Fq 'APT::Update::Error-Mode=any' "$TEST_CALLS"
    [[ "$log" =~ ^/tmp/get-ros2\.[a-zA-Z0-9]{8}/install\.log$ && -f "$log" ]]
    grep -Fxq -- "$raw" "$log"
    [[ $(stat -c %a "$log") == 600 ]]
    [[ $(find "${log%/*}" -mindepth 1 -maxdepth 1 | wc -l) -eq 1 ]]
    if grep -Fq 'installation completed' "$sandbox/stdout"; then
        echo 'Failure was reported as success' >&2
        exit 1
    fi
    count=$((count + 1))
    printf 'ok %s - %s: exit status, exact message, log and stop-on-error\n' "$count" "$code"
done < "$fixtures"
[[ "$count" -ge 14 ]]
printf 'Passed %s intentional failure cases against %s\n' "$count" "$installer"
