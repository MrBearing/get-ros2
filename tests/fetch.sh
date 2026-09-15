#!/usr/bin/env bash
# Test download failure handling without depending on a live endpoint.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
installer=$(realpath "${1:-install.sh}")
sandbox=$(mktemp -d /tmp/get-ros2-fetch.XXXXXXXX)
trap 'rm -rf -- "$sandbox"' EXIT
mkdir "$sandbox/bin"
cat > "$sandbox/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ " $* " == *' --fail '* && " $* " == *' --location '* ]]
[[ "${!#}" == https://get-ros2.com/install.sh ]]
while [[ "$1" != --output ]]; do shift; done
case "$TEST_FETCH_CASE" in
    dns) echo 'curl: (6) Could not resolve host: get-ros2.com' >&2; exit 6 ;;
    http) echo 'curl: (22) The requested URL returned error: 404' >&2; exit 22 ;;
    timeout) echo 'curl: (28) Operation timed out' >&2; exit 28 ;;
    empty) : > "$2" ;;
    html) echo '<html>Not found</html>' > "$2" ;;
    truncated) printf '#!/bin/sh\n{\n' > "$2" ;;
    success) cp "$TEST_FETCH_SOURCE" "$2" ;;
    *) exit 99 ;;
esac
STUB
chmod +x "$sandbox/bin/curl"
count=0
for spec in 'success 0' 'dns 6' 'http 22' 'timeout 28' 'empty 1' 'html 1' 'truncated 2'; do
    read -r scenario expected <<< "$spec"
    # A stale local copy must not turn a failed download into a passing check.
    cp "$installer" "$sandbox/fetched.sh"
    status=0
    TEST_FETCH_CASE=$scenario TEST_FETCH_SOURCE=$installer PATH="$sandbox/bin:$PATH" \
        bash "$directory/fetch-installer.sh" "$sandbox/fetched.sh" \
        > "$sandbox/stdout" 2> "$sandbox/stderr" || status=$?
    if [[ "$status" != "$expected" ]]; then
        cat "$sandbox/stdout" "$sandbox/stderr" >&2
        echo "FAIL $scenario: expected exit $expected, got $status" >&2
        exit 1
    fi
    if [[ "$scenario" == success ]]; then cmp "$installer" "$sandbox/fetched.sh"; fi
    if [[ "$scenario" == dns || "$scenario" == http || "$scenario" == timeout ]]; then
        [[ ! -s "$sandbox/stdout" ]]
        grep -Fq "curl: ($expected)" "$sandbox/stderr"
    fi
    count=$((count + 1))
    printf 'ok %s - download handling: %s\n' "$count" "$scenario"
done
printf 'Passed %s download handling cases\n' "$count"
