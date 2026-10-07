#!/usr/bin/env bash
# Compatible restores cannot cross OS, architecture, or prepared toolchain namespaces.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
sandbox=$(mktemp -d /tmp/get-ros2-cache-keys.XXXXXXXX)
trap 'rm -r -- "$sandbox"' EXIT
export UBUNTU_VERSION=24.04 BUILD_ARCH=amd64 GITHUB_RUN_ID=123 GITHUB_RUN_ATTEMPT=1 GITHUB_OUTPUT=$sandbox/output
namespace=$(printf toolchain | sha256sum); namespace=${namespace%% *}
source_digest=$(printf source | sha256sum); source_digest=${source_digest%% *}
printf 'namespace=%s\nsource=%s\n' "$namespace" "$source_digest" > "$sandbox/context"
run() { : > "$GITHUB_OUTPUT"; bash "$directory/../.github/scripts/source-cache-key.sh" "$sandbox/context"; }
run
prefix=$(sed -n 's/^prefix=//p' "$GITHUB_OUTPUT")
key=$(sed -n 's/^key=//p' "$GITHUB_OUTPUT")
count=0
pass() { count=$((count+1)); printf 'ok %s - %s\n' "$count" "$*"; }
[[ $prefix == "compiler-v1-24.04-amd64-$namespace-" && $key == "$prefix$source_digest-123-1" ]]
pass 'key includes prepared toolchain and source identities'
BUILD_ARCH=arm64; run; [[ $(sed -n 's/^prefix=//p' "$GITHUB_OUTPUT") != "$prefix" ]]; pass 'architecture isolation'
BUILD_ARCH=amd64 UBUNTU_VERSION=26.04; run; [[ $(sed -n 's/^prefix=//p' "$GITHUB_OUTPUT") != "$prefix" ]]; pass 'OS isolation'
UBUNTU_VERSION=24.04 GITHUB_RUN_ATTEMPT=2; run; [[ $(sed -n 's/^key=//p' "$GITHUB_OUTPUT") != "$key" ]]; pass 'retries can save refreshed compatible results'
source_new=$(printf newsource | sha256sum); source_new=${source_new%% *}
printf 'namespace=%s\nsource=%s\n' "$namespace" "$source_new" > "$sandbox/context"
run; [[ $(sed -n 's/^prefix=//p' "$GITHUB_OUTPUT") == "$prefix" && $(sed -n 's/^key=//p' "$GITHUB_OUTPUT") != "$key" ]]; pass 'new sources permit compatible C++ restores'
printf 'namespace=%s\nsource=%s\n' "$source_new" "$source_digest" > "$sandbox/context"
run; [[ $(sed -n 's/^prefix=//p' "$GITHUB_OUTPUT") != "$prefix" ]]; pass 'changed compiler/package context invalidates compatible restore prefix'
printf 'namespace=../../other\nsource=%s\n' "$source_digest" > "$sandbox/context"
status=0; run > "$sandbox/invalid.log" 2>&1 || status=$?; [[ $status == 2 && ! -s $GITHUB_OUTPUT ]]; pass 'invalid context fails before writing cache outputs'
printf 'Passed %s cache-key cases\n' "$count"
