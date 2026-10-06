#!/usr/bin/env bash
# Run source-build checks; benchmark profiles use independent copies of one prepared image.
set -euo pipefail
case ${UBUNTU_VERSION:-} in 22.04|24.04|26.04) ;; *) echo 'UBUNTU_VERSION must be 22.04, 24.04, or 26.04.' >&2; exit 2 ;; esac
profile=${SOURCE_BUILD_PROFILE:-auto}
installer=${1:?Usage: run-source-build.sh SETUP_SCRIPT}
common=(--init -e SOURCE_BUILD_TEST_CONTAINER=1 -e DEBIAN_FRONTEND=noninteractive
    -v "$PWD:/workspace:ro" -w /workspace)
collect() {
    local container=$1 target="_ci/source-build/$1" distro item
    case "$UBUNTU_VERSION" in 22.04) distro=humble ;; 24.04) distro=jazzy ;; 26.04) distro=lyrical ;; esac
    mkdir -p "$target"
    docker logs "$container" > "$target/container.log" 2>&1 || true
    for item in exact.repos log talker.log listener.log build-metrics.txt build-memory-peak.txt; do
        docker cp "$container:/home/builder/ros2_$distro/$item" "$target/" || true
    done
}
if [[ $profile != benchmark ]]; then
    docker run --name source-build "${common[@]}" \
        -e SOURCE_BUILD_PROFILE="$profile" \
        -e SOURCE_BUILD_WORKERS="${SOURCE_BUILD_WORKERS:-}" -e SOURCE_BUILD_JOBS="${SOURCE_BUILD_JOBS:-}" \
        "ubuntu:$UBUNTU_VERSION" bash tests/source-build.sh "$installer"
    exit 0
fi
[[ -z ${SOURCE_BUILD_WORKERS:-} && -z ${SOURCE_BUILD_JOBS:-} ]] || {
    echo 'The benchmark profile compares fixed baseline, auto, and low-memory settings; numeric overrides are not allowed.' >&2; exit 2;
}
# Setup/dependency resolution runs once; each build starts without build/install/compiler caches.
docker run --name source-build-prepare "${common[@]}" \
    -e SOURCE_BUILD_PHASE=prepare -e SOURCE_BUILD_PROFILE=auto \
    "ubuntu:$UBUNTU_VERSION" bash tests/source-build.sh "$installer"
image=get-ros2-source-benchmark
trap 'docker image rm "$image" >/dev/null 2>&1 || true' EXIT
docker commit source-build-prepare "$image" >/dev/null
collect source-build-prepare
docker rm source-build-prepare >/dev/null
status=0
for mode in baseline auto low-memory; do
    docker run --name "source-build-$mode" "${common[@]}" \
        -e SOURCE_BUILD_PHASE=build -e SOURCE_BUILD_PROFILE="$mode" \
        "$image" bash tests/source-build.sh "$installer" || status=1
    # Keep only diagnostics between builds to avoid retaining three large build layers.
    collect "source-build-$mode"
    docker rm "source-build-$mode" >/dev/null
done
exit "$status"
