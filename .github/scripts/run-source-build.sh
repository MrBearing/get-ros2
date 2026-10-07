#!/usr/bin/env bash
# Prepare a fresh environment, then build with optional compiler/download caches.
set -euo pipefail
case ${UBUNTU_VERSION:-} in 22.04|24.04|26.04) ;; *) echo 'UBUNTU_VERSION must be 22.04, 24.04, or 26.04.' >&2; exit 2 ;; esac
profile=${SOURCE_BUILD_PROFILE:-auto}
cache=${SOURCE_BUILD_CACHE_MODE:-off}
action=${SOURCE_BUILD_ACTION:-all}
case "$cache" in on|off|benchmark) ;; *) echo 'SOURCE_BUILD_CACHE_MODE must be on, off, or benchmark.' >&2; exit 2 ;; esac
case "$action" in prepare|build|all) ;; *) exit 2 ;; esac
if [[ $profile == benchmark ]]; then
    [[ $cache != benchmark ]] || { echo 'Compare concurrency and caching in separate runs.' >&2; exit 2; }
    cache=off
    [[ -z ${SOURCE_BUILD_WORKERS:-} && -z ${SOURCE_BUILD_JOBS:-} ]] || {
        echo 'The benchmark profile compares fixed baseline, auto, and low-memory settings; numeric overrides are not allowed.' >&2; exit 2;
    }
fi
installer=${1:?Usage: run-source-build.sh SETUP_SCRIPT}
common=(--init -e SOURCE_BUILD_TEST_CONTAINER=1 -e DEBIAN_FRONTEND=noninteractive
    -v "$PWD:/workspace:ro" -w /workspace)
settings=(-e SOURCE_BUILD_WORKERS="${SOURCE_BUILD_WORKERS:-}" -e SOURCE_BUILD_JOBS="${SOURCE_BUILD_JOBS:-}")
collect() {
    local container=$1 target="_ci/source-build/$1" distro item
    case "$UBUNTU_VERSION" in 22.04) distro=humble ;; 24.04) distro=jazzy ;; 26.04) distro=lyrical ;; esac
    mkdir -p "$target"
    docker logs "$container" > "$target/container.log" 2>&1 || true
    for item in exact.repos log talker.log listener.log build-metrics.txt build-memory-peak.txt cache-context.txt cache-toolchain.txt ccache-stats.txt sccache-stats.json sccache-stop.txt; do
        docker cp "$container:/home/builder/ros2_$distro/$item" "$target/" || true
    done
}
# Keep the direct uncached invocation available for local checks.
if [[ $action == all && $cache == off && $profile != benchmark ]]; then
    docker run --name source-build "${common[@]}" "${settings[@]}" -e SOURCE_BUILD_CACHE=off \
        -e SOURCE_BUILD_PROFILE="$profile" "ubuntu:$UBUNTU_VERSION" bash tests/source-build.sh "$installer"
    exit 0
fi
image=get-ros2-source-benchmark
if [[ $action != build ]]; then
    prepare_started=$SECONDS
    prepare_cache=off
    [[ $cache == off ]] || prepare_cache=on
    prepare_profile=$profile
    [[ $profile != benchmark ]] || prepare_profile=auto
    docker run --name source-build-prepare "${common[@]}" "${settings[@]}" \
        -e SOURCE_BUILD_PHASE=prepare -e SOURCE_BUILD_CACHE="$prepare_cache" -e SOURCE_BUILD_PROFILE="$prepare_profile" \
        "ubuntu:$UBUNTU_VERSION" bash tests/source-build.sh "$installer"
    docker commit source-build-prepare "$image" >/dev/null
    collect source-build-prepare
    printf 'prepare_seconds=%s\n' "$((SECONDS - prepare_started))" > _ci/source-build/source-build-prepare/phase-metrics.txt
    docker rm source-build-prepare >/dev/null
    if [[ $action == prepare ]]; then exit 0; fi
fi
trap 'docker image rm "$image" >/dev/null 2>&1 || true' EXIT
mkdir -p _ci/source-cache
if [[ $cache == benchmark && -n $(find _ci/source-cache -mindepth 1 -print -quit) ]]; then
    echo 'A cache benchmark requires an empty _ci/source-cache directory.' >&2; exit 2
fi
modes=(normal)
[[ $profile != benchmark ]] || modes=(baseline auto low-memory)
[[ $cache != benchmark ]] || modes=(no-cache cold warm)
status=0
for mode in "${modes[@]}"; do
    build_started=$SECONDS
    build_profile=$profile build_cache=$cache
    [[ $profile != benchmark ]] || build_profile=$mode
    if [[ $cache == benchmark ]]; then
        build_cache=on
        [[ $mode != no-cache ]] || build_cache=off
    fi
    container=source-build-$mode
    mount=()
    if [[ $build_cache == on ]]; then mount=(-v "$PWD/_ci/source-cache:/cache"); fi
    docker run --name "$container" "${common[@]}" "${settings[@]}" "${mount[@]}" \
        -e SOURCE_BUILD_PHASE=build -e SOURCE_BUILD_PROFILE="$build_profile" -e SOURCE_BUILD_CACHE="$build_cache" \
        "$image" bash tests/source-build.sh "$installer" || status=1
    collect "$container"
    printf 'container_seconds=%s\n' "$((SECONDS - build_started))" > "_ci/source-build/$container/phase-metrics.txt"
    docker rm "$container" >/dev/null
 done
exit "$status"
