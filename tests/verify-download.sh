#!/usr/bin/env bash
# Execute the README and landing page commands with real hashes and mocked downloads.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
sandbox=$(mktemp -d /tmp/get-ros2-download-tests.XXXXXXXX)
trap 'rm -r -- "$sandbox"' EXIT
mkdir "$sandbox/bin" "$sandbox/original" "$sandbox/downloads"
export TEST_SANDBOX=$sandbox TEST_EXECUTED=$sandbox/executed
cat > "$sandbox/original/install.sh" <<'INSTALLER'
#!/bin/sh
printf 'executed\n' >> "$TEST_EXECUTED"
INSTALLER
(cd "$sandbox/original" && sha256sum install.sh > install.sh.sha256)
cat > "$sandbox/bin/mktemp" <<'MOCK'
#!/bin/sh
[ "$SCENARIO" != directory_failure ] || exit 1
exec /usr/bin/mktemp -d "$TEST_SANDBOX/downloads/run space.XXXXXXXX"
MOCK
cat > "$sandbox/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == -fsSL && $2 == --proto && $3 == '=https' && $4 == --proto-redir && $5 == '=https' ]] || exit 99
url=$6
[[ $7 == -o ]] || exit 99
destination=$8
case "$SOURCE" in
    pages|site) prefix=https://get-ros2.com ;;
    release) prefix=https://github.com/MrBearing/get-ros2/releases/download/v1.2.3 ;;
    *) exit 99 ;;
esac
[[ $url == "$prefix/$destination" ]] || exit 99
if [[ $destination == install.sh ]]; then
    [[ $SCENARIO != installer_download_failure ]] || exit 22
    cp "$TEST_SANDBOX/original/install.sh" "$destination"
    if [[ $SCENARIO == altered_installer ]]; then printf '# altered\n' >> "$destination"; fi
    if [[ $SCENARIO == truncated_installer ]]; then head -c 20 "$TEST_SANDBOX/original/install.sh" > "$destination"; fi
elif [[ $destination == install.sh.sha256 ]]; then
    [[ $SCENARIO != checksum_download_failure ]] || exit 22
    cp "$TEST_SANDBOX/original/install.sh.sha256" "$destination"
    case "$SCENARIO" in
        mismatched_checksum) printf '%064d  install.sh\n' 0 > "$destination" ;;
        invalid_checksum) printf '<html>Not found</html>\n' > "$destination" ;;
        empty_checksum) : > "$destination" ;;
    esac
else
    exit 99
fi
MOCK
chmod +x "$sandbox/bin/"*
count=0
for source in pages release site; do
    if [[ $source == site ]]; then
        # Decode the HTML text shown and copied by the page without changing its shell code.
        sed -n '/<pre><code id="verify-command">/,/<\/code><\/pre>/p' "$directory/../index.html" |
            sed -e 's|.*<code id="verify-command">||' \
                -e 's|</code></pre>.*||' \
                -e 's|\&amp;|\&|g' > "$sandbox/verify.sh"
        cmp "$sandbox/pages.sh" "$sandbox/verify.sh"
    else
        # Read the actual README command, replacing only the documented tag placeholder.
        awk -v name="$source" '
            $0 == "<!-- BEGIN verify-" name " -->" {inside=1; next}
            $0 == "<!-- END verify-" name " -->" {exit}
            inside && $0 !~ /^```/ {print}
        ' "$directory/../README.md" | sed 's/vX.Y.Z/v1.2.3/g' > "$sandbox/verify.sh"
    fi
    if [[ $source == pages ]]; then cp "$sandbox/verify.sh" "$sandbox/pages.sh"; fi
    [[ -s "$sandbox/verify.sh" ]]
    for shell in /bin/dash /bin/bash; do
        for scenario in valid altered_installer truncated_installer mismatched_checksum invalid_checksum empty_checksum installer_download_failure checksum_download_failure directory_failure; do
            : > "$TEST_EXECUTED"
            status=0
            env PATH="$sandbox/bin:$PATH" SOURCE="$source" SCENARIO="$scenario" \
                "$shell" "$sandbox/verify.sh" > "$sandbox/stdout" 2> "$sandbox/stderr" || status=$?
            case "$scenario" in
                valid) expected=0 ;;
                *_download_failure) expected=22 ;;
                *) expected=1 ;;
            esac
            if [[ $status != "$expected" ]]; then
                cat "$sandbox/stdout" "$sandbox/stderr" >&2
                printf 'FAIL %s / %s / %s: expected exit %s, got %s\n' "$source" "$shell" "$scenario" "$expected" "$status" >&2
                exit 1
            fi
            if [[ $scenario == valid ]]; then
                [[ $(wc -l < "$TEST_EXECUTED") -eq 1 ]]
                grep -Fxq 'install.sh: OK' "$sandbox/stdout"
            else
                [[ ! -s "$TEST_EXECUTED" ]] || { echo 'Installer ran after failed verification' >&2; exit 1; }
            fi
            count=$((count + 1))
            printf 'ok %s - documented verification: %s / %s / %s\n' "$count" "$source" "$shell" "$scenario"
        done
    done
done
printf 'Passed %s documented download verification cases\n' "$count"
