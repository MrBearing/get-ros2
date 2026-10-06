#!/usr/bin/env bash
# Test resource selection without changing the host or compiling ROS.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
sandbox=$(mktemp -d /tmp/get-ros2-parallelism.XXXXXXXX)
trap 'rm -r -- "$sandbox"' EXIT
mkdir -p "$sandbox/bin" "$sandbox/proc" "$sandbox/cgroup/cpu" "$sandbox/cgroup/memory"
cat > "$sandbox/bin/nproc" <<'MOCK'
#!/bin/sh
printf '%s\n' "$TEST_CPUS"
MOCK
chmod +x "$sandbox/bin/nproc"
export PATH="$sandbox/bin:$PATH" SOURCE_BUILD_PROC_ROOT=$sandbox/proc SOURCE_BUILD_CGROUP_ROOT=$sandbox/cgroup TEST_CPUS=8
# shellcheck source=tests/build-parallelism.sh
source "$directory/build-parallelism.sh"
reset() {
    unset SOURCE_BUILD_PROFILE SOURCE_BUILD_WORKERS SOURCE_BUILD_JOBS CARGO_BUILD_JOBS
    TEST_CPUS=8
    printf 'MemTotal: 32768000 kB\n' > "$sandbox/proc/meminfo"
    printf 'max 100000\n' > "$sandbox/cgroup/cpu.max"
    printf 'max\n' > "$sandbox/cgroup/memory.max"
    rm -f "$sandbox/cgroup/cpu/cpu.cfs_quota_us" "$sandbox/cgroup/cpu/cpu.cfs_period_us" "$sandbox/cgroup/memory/memory.limit_in_bytes"
}
count=0
pass() { count=$((count+1)); printf 'ok %s - %s\n' "$count" "$*"; }
check() {
    local workers=$1 jobs=$2
    source_build_configure > "$sandbox/log"
    [[ $BUILD_WORKERS == "$workers" && $BUILD_JOBS == "$jobs" ]]
    [[ $MAKEFLAGS == "-j$jobs" && $CMAKE_BUILD_PARALLEL_LEVEL == "$jobs" ]]
    [[ ${CARGO_BUILD_JOBS:-default} == "$jobs" ]]
    if [[ $workers == 1 ]]; then [[ ${BUILD_COLCON_ARGS[*]} == '--executor sequential' ]];
    else [[ ${BUILD_COLCON_ARGS[*]} == "--executor parallel --parallel-workers $workers" ]]; fi
}
reset; check 2 4; pass 'eight CPUs use two packages with four compiler jobs'
reset; TEST_CPUS=4; check 2 2; pass 'standard four-CPU runner'
reset; TEST_CPUS=1; check 1 1; pass 'single CPU stays sequential'
reset; printf '200000 100000\n' > "$sandbox/cgroup/cpu.max"; check 2 1; pass 'v2 CPU quota overrides host CPU count'
reset; printf '50000 100000\n' > "$sandbox/cgroup/cpu.max"; check 1 1; pass 'fractional CPU quota rounds down to at least one'
reset; printf '4294967296\n' > "$sandbox/cgroup/memory.max"; check 1 1; pass 'v2 memory limit bounds concurrency'
reset; printf '8589934592\n' > "$sandbox/cgroup/memory.max"; check 2 1; pass 'eight GiB reserves headroom for large compiler processes'
reset; TEST_CPUS=4; printf 'MemTotal: 16330120 kB\n' > "$sandbox/proc/meminfo"; check 2 2; pass 'recorded native runner resources retain the benchmarked configuration'
reset; printf 'MemTotal: 1048576 kB\n' > "$sandbox/proc/meminfo"; check 1 1; pass 'small memory never produces zero jobs'
reset; rm "$sandbox/cgroup/cpu.max" "$sandbox/cgroup/memory.max"; printf '200000\n' > "$sandbox/cgroup/cpu/cpu.cfs_quota_us"; printf '100000\n' > "$sandbox/cgroup/cpu/cpu.cfs_period_us"; printf '4294967296\n' > "$sandbox/cgroup/memory/memory.limit_in_bytes"; check 1 1; pass 'v1 container limits'
reset; SOURCE_BUILD_WORKERS=4 SOURCE_BUILD_JOBS=1; check 4 1; pass 'explicit workers and jobs'
reset; TEST_CPUS=4; SOURCE_BUILD_JOBS=4; check 1 4; pass 'automatic workers adapt to explicit compiler jobs'
reset; SOURCE_BUILD_PROFILE=low-memory; check 1 1; pass 'low-memory profile bounds Cargo too'
reset; SOURCE_BUILD_PROFILE=baseline; source_build_configure > "$sandbox/log"; [[ $BUILD_WORKERS == 1 && $BUILD_JOBS == 2 && ! ${CARGO_BUILD_JOBS+x} ]]; pass 'baseline retains old concurrency including default Cargo'
for spec in 'SOURCE_BUILD_WORKERS=0' 'SOURCE_BUILD_WORKERS=-1' 'SOURCE_BUILD_WORKERS=1.5' 'SOURCE_BUILD_JOBS=abc' 'SOURCE_BUILD_JOBS=9999999' 'SOURCE_BUILD_JOBS=01' 'SOURCE_BUILD_PROFILE=unknown'; do
    reset; export "${spec?}"
    status=0; source_build_configure > "$sandbox/log" 2>&1 || status=$?
    [[ $status == 2 ]]; grep -Fq 'Source build configuration error:' "$sandbox/log"
    pass "reject $spec"
done
reset; SOURCE_BUILD_WORKERS=8 SOURCE_BUILD_JOBS=2; status=0; source_build_configure > "$sandbox/log" 2>&1 || status=$?; [[ $status == 2 ]]; grep -Fq 'CPU/memory budget' "$sandbox/log"; pass 'reject oversubscribed explicit configuration'
reset; SOURCE_BUILD_PROFILE=low-memory SOURCE_BUILD_JOBS=2; status=0; source_build_configure > "$sandbox/log" 2>&1 || status=$?; [[ $status == 2 ]]; pass 'reject conflicting profile and overrides'
printf 'Passed %s parallelism cases\n' "$count"
