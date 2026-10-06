#!/usr/bin/env bash
# Run only inside a disposable Ubuntu container: prepare, build, and exercise ROS 2.
set -euo pipefail
[[ ${SOURCE_BUILD_TEST_CONTAINER:-} == 1 ]] || { echo 'Run this test in a disposable container with SOURCE_BUILD_TEST_CONTAINER=1.' >&2; exit 1; }
directory=$(cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=tests/build-parallelism.sh
source "$directory/build-parallelism.sh"
source_build_configure
phase=${SOURCE_BUILD_PHASE:-all}
case "$phase" in all|prepare|build) ;; *) source_build_error 'SOURCE_BUILD_PHASE must be all, prepare, or build.'; exit 2 ;; esac
setup_script=${1:-$directory/../setup-source.sh}
if [[ $phase != build ]]; then
    cp "$setup_script" /tmp/source-setup-under-test.sh
    setup_script=/tmp/source-setup-under-test.sh
    apt-get -o APT::Update::Error-Mode=any update
    apt-get install -y --no-install-recommends sudo ca-certificates time
    if ! id builder >/dev/null 2>&1; then useradd --create-home --shell /bin/bash builder; fi
    printf 'builder ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/source-build-test
    chmod 440 /etc/sudoers.d/source-build-test
    # Exercise both user entry points; the second run must reuse system configuration.
    runuser -u builder -- sh "$setup_script" --yes
    runuser -u builder -- sudo sh "$setup_script" --yes
    [[ $(stat -c %U /home/builder/.ros/rosdep/sources.cache) == builder ]]
fi
# shellcheck disable=SC1091
source /etc/os-release
case "$VERSION_ID" in
    22.04) distro=humble; skip='fastcdr rti-connext-dds-6.0.1 urdfdom_headers' ;;
    24.04) distro=jazzy; skip='fastcdr rti-connext-dds-6.0.1 urdfdom_headers' ;;
    26.04) distro=lyrical; skip='fastcdr rti-connext-dds-7.7.0 urdfdom_headers' ;;
    *) exit 1 ;;
esac
runuser -u builder -- env DISTRO="$distro" SKIP_KEYS="$skip" BUILD_HELPER="$directory/build-parallelism.sh" BUILD_PHASE="$phase" bash <<'BUILD'
set -euo pipefail
cd "$HOME"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
[[ $(locale charmap) == UTF-8 ]]
if [[ $BUILD_PHASE != build ]]; then
    mkdir -p "ros2_$DISTRO/src"
    cd "ros2_$DISTRO"
    curl -fL --proto '=https' --proto-redir '=https' "https://raw.githubusercontent.com/ros2/ros2/$DISTRO/ros2.repos" -o ros2.repos
    vcs import --recursive --input ros2.repos src
    vcs export --exact src > exact.repos
    rosdep install --from-paths src --ignore-src --rosdistro "$DISTRO" -y --skip-keys "$SKIP_KEYS"
    touch .source-build-prepared
    if [[ $BUILD_PHASE == prepare ]]; then exit 0; fi
else
    cd "ros2_$DISTRO"
    [[ -f .source-build-prepared ]] || { echo 'Missing prepared source workspace.' >&2; exit 2; }
fi
# Build the C++ and Python demos, CLI, and their complete dependency closure from source.
# shellcheck source=tests/build-parallelism.sh
source "$BUILD_HELPER"
source_build_configure
# Sample total container memory, including page cache; time's RSS is per process.
memory_file=/sys/fs/cgroup/memory.current
[[ -r $memory_file ]] || memory_file=/sys/fs/cgroup/memory/memory.usage_in_bytes
monitor=
if [[ -r $memory_file ]]; then
    (
        peak=0
        while true; do
            current=$(cat "$memory_file")
            if ((current > peak)); then peak=$current; printf '%s\n' "$peak" > build-memory-peak.txt; fi
            sleep 1
        done
    ) &
    monitor=$!
fi
stop_monitor() {
    if [[ -n $monitor ]]; then kill "$monitor" 2>/dev/null || true; wait "$monitor" 2>/dev/null || true; fi
}
trap stop_monitor EXIT
build_status=0
/usr/bin/time -o build-metrics.txt -f 'elapsed_seconds=%e\nmax_process_rss_kib=%M' \
    colcon build --symlink-install "${BUILD_COLCON_ARGS[@]}" \
    --packages-up-to demo_nodes_cpp demo_nodes_py ros2run \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF || build_status=$?
stop_monitor
trap - EXIT
{
    printf 'profile=%s\npackage_workers=%s\ncompiler_jobs=%s\ncargo_jobs=%s\n' \
        "$BUILD_PROFILE" "$BUILD_WORKERS" "$BUILD_JOBS" "${CARGO_BUILD_JOBS:-default}"
    printf 'effective_cpus=%s\neffective_memory_bytes=%s\n' "$BUILD_CPUS" "$BUILD_MEMORY_BYTES"
    printf 'sampled_peak_container_bytes=%s\nbuild_exit_code=%s\n' "$(cat build-memory-peak.txt 2>/dev/null || echo unavailable)" "$build_status"
} >> build-metrics.txt
cat build-metrics.txt
((build_status == 0)) || exit "$build_status"
set +u
source install/local_setup.bash
set -u
export ROS_DOMAIN_ID=83
ros2 run demo_nodes_cpp talker > talker.log 2>&1 &
talker=$!
ros2 run demo_nodes_py listener > listener.log 2>&1 &
listener=$!
trap 'kill "$talker" "$listener" 2>/dev/null || true; wait "$talker" "$listener" 2>/dev/null || true' EXIT
for ((attempt=0; attempt<60; attempt++)); do
    if grep -q 'I heard:' listener.log && grep -q 'Publishing:' talker.log; then
        echo 'Source-built C++ talker and Python listener communicated successfully.'
        exit 0
    fi
    kill -0 "$talker" "$listener" || { cat talker.log listener.log >&2; exit 1; }
    sleep 1
done
cat talker.log listener.log >&2
echo 'Timed out waiting for source-built nodes to communicate.' >&2
exit 1
BUILD
