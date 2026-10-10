#!/usr/bin/env bash
# Verify benchmark orchestration without Docker or changes to real images/containers.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
sandbox=$(mktemp -d /tmp/get-ros2-build-driver.XXXXXXXX)
trap 'rm -r -- "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/work"
export TEST_DOCKER_CALLS=$sandbox/calls
cat > "$sandbox/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TEST_DOCKER_CALLS"
case $1 in
    run)
        if [[ ${TEST_DOCKER_FAIL:-} == prepare && $* == *SOURCE_BUILD_PHASE=prepare* ]]; then exit 1; fi
        if [[ ${TEST_DOCKER_FAIL:-} == baseline && $* == *source-build-baseline* ]]; then exit 1; fi ;;
    commit) echo 'sha256:fixture' ;;
    cp) [[ $2 != *build-metrics.txt ]] || printf 'elapsed_seconds=42\n' > "$3/build-metrics.txt" ;;
    logs) echo 'fixture build log' ;;
    rm|image) ;;
    *) exit 99 ;;
esac
MOCK
chmod +x "$sandbox/bin/docker"
export PATH="$sandbox/bin:$PATH"
count=0
run() {
    local expected=$1 status=0
    : > "$TEST_DOCKER_CALLS"
    rm -rf -- "$sandbox/work/_ci"
    (cd "$sandbox/work" && bash "$directory/../.github/scripts/run-source-build.sh" /workspace/setup-source.sh) \
        > "$sandbox/stdout" 2> "$sandbox/stderr" || status=$?
    [[ $status == "$expected" ]] || { cat "$sandbox/stderr" >&2; exit 1; }
}
pass() { count=$((count+1)); printf 'ok %s - %s\n' "$count" "$*"; }
export UBUNTU_VERSION=24.04 SOURCE_BUILD_PROFILE=auto SOURCE_BUILD_WORKERS=2 SOURCE_BUILD_JOBS=2 SOURCE_BUILD_CACHE_MODE=off SOURCE_BUILD_ACTION=all
run 0
grep -Fq 'SOURCE_BUILD_WORKERS=2' "$TEST_DOCKER_CALLS"
grep -Fq 'SOURCE_BUILD_JOBS=2' "$TEST_DOCKER_CALLS"
[[ $(grep -c '^run ' "$TEST_DOCKER_CALLS") == 1 ]]
pass 'normal run forwards settings without snapshotting'
SOURCE_BUILD_PROFILE=benchmark SOURCE_BUILD_WORKERS='' SOURCE_BUILD_JOBS=''
run 0
[[ $(grep -c '^run ' "$TEST_DOCKER_CALLS") == 4 ]]
for profile in baseline auto low-memory; do
    grep -Fq "SOURCE_BUILD_PHASE=build -e SOURCE_BUILD_PROFILE=$profile" "$TEST_DOCKER_CALLS"
    grep -Fxq "rm source-build-$profile" "$TEST_DOCKER_CALLS"
    [[ -f $sandbox/work/_ci/source-build/source-build-$profile/build-metrics.txt ]]
done
grep -Fxq 'commit source-build-prepare get-ros2-source-benchmark' "$TEST_DOCKER_CALLS"
grep -Fxq 'image rm get-ros2-source-benchmark' "$TEST_DOCKER_CALLS"
pass 'benchmark clones one prepared image and retains measurements before cleanup'
export TEST_DOCKER_FAIL=baseline
run 1
grep -Fq 'source-build-low-memory' "$TEST_DOCKER_CALLS"
grep -Fxq 'image rm get-ros2-source-benchmark' "$TEST_DOCKER_CALLS"
pass 'failed build does not hide failure or prevent other profiles'
TEST_DOCKER_FAIL=prepare
run 1
[[ $(grep -c '^run ' "$TEST_DOCKER_CALLS") == 1 ]]
pass 'preparation failure stops benchmark'
unset TEST_DOCKER_FAIL
SOURCE_BUILD_PROFILE=auto SOURCE_BUILD_CACHE_MODE=on
run 0
[[ $(grep -c '^run ' "$TEST_DOCKER_CALLS") == 2 ]]
grep -Fq '/workspace:ro' "$TEST_DOCKER_CALLS"
grep -Fq '/cache' "$TEST_DOCKER_CALLS"
pass 'cached builds still prepare a fresh environment before mounting cache data'
SOURCE_BUILD_ACTION=prepare
run 0
[[ $(grep -c '^run ' "$TEST_DOCKER_CALLS") == 1 ]]
if grep -q '^image rm' "$TEST_DOCKER_CALLS"; then exit 1; fi
pass 'separate preparation leaves its snapshot for cache restoration'
SOURCE_BUILD_ACTION=build
run 0
[[ $(grep -c '^run ' "$TEST_DOCKER_CALLS") == 1 ]]
grep -Fq 'SOURCE_BUILD_PHASE=build' "$TEST_DOCKER_CALLS"
pass 'build stage uses the prepared snapshot'
SOURCE_BUILD_ACTION=all SOURCE_BUILD_CACHE_MODE=benchmark
run 0
for mode in no-cache cold warm; do
    grep -Fq "source-build-$mode" "$TEST_DOCKER_CALLS"
    [[ -f $sandbox/work/_ci/source-build/source-build-$mode/build-metrics.txt ]]
done
[[ $(grep -c 'source-cache:/cache' "$TEST_DOCKER_CALLS") == 2 ]]
pass 'cache comparison gives cold and warm a shared cache but leaves no-cache unmounted'
SOURCE_BUILD_CACHE_MODE=off SOURCE_BUILD_PROFILE=benchmark
SOURCE_BUILD_WORKERS=2
run 2
[[ ! -s $TEST_DOCKER_CALLS ]]
grep -Fq 'numeric overrides are not allowed' "$sandbox/stderr"
pass 'benchmark rejects conflicting overrides before Docker'
SOURCE_BUILD_WORKERS='' UBUNTU_VERSION=20.04
run 2
[[ ! -s $TEST_DOCKER_CALLS ]]
pass 'unsupported Ubuntu rejected before Docker'
printf 'Passed %s build orchestration cases\n' "$count"
