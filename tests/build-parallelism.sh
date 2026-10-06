#!/usr/bin/env bash
# Source this helper to select a bounded colcon/Make/CMake/Cargo configuration.
source_build_error() { printf 'Source build configuration error: %s\n' "$*" >&2; return 2; }
source_build_integer() {
    [[ $2 =~ ^[1-9][0-9]{0,5}$ ]] || source_build_error "$1 must be an integer from 1 to 999999 (got: $2)."
}
source_build_resources() {
    local proc_root=${SOURCE_BUILD_PROC_ROOT:-/proc} cgroup_root=${SOURCE_BUILD_CGROUP_ROOT:-/sys/fs/cgroup}
    local quota period limit cpu_limit memory_kib
    BUILD_CPUS=$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc) || return
    source_build_integer 'Detected CPU count' "$BUILD_CPUS" || return
    memory_kib=$(awk '$1 == "MemTotal:" {print $2}' "$proc_root/meminfo") || return
    [[ $memory_kib =~ ^[1-9][0-9]{0,12}$ ]] || { source_build_error 'Unable to determine physical memory.'; return 2; }
    BUILD_MEMORY_BYTES=$((memory_kib * 1024))
    # Docker's private cgroup namespace exposes its own limits at this root.
    if [[ -r $cgroup_root/cpu.max ]]; then
        read -r quota period < "$cgroup_root/cpu.max"
    elif [[ -r $cgroup_root/cpu/cpu.cfs_quota_us && -r $cgroup_root/cpu/cpu.cfs_period_us ]]; then
        quota=$(cat "$cgroup_root/cpu/cpu.cfs_quota_us")
        period=$(cat "$cgroup_root/cpu/cpu.cfs_period_us")
    else
        quota=max period=1
    fi
    if [[ $quota =~ ^[1-9][0-9]*$ && $period =~ ^[1-9][0-9]*$ ]]; then
        cpu_limit=$((quota / period))
        ((cpu_limit > 0)) || cpu_limit=1
        ((cpu_limit >= BUILD_CPUS)) || BUILD_CPUS=$cpu_limit
    fi
    if [[ -r $cgroup_root/memory.max ]]; then
        limit=$(cat "$cgroup_root/memory.max")
    elif [[ -r $cgroup_root/memory/memory.limit_in_bytes ]]; then
        limit=$(cat "$cgroup_root/memory/memory.limit_in_bytes")
    else
        limit=max
    fi
    if [[ $limit =~ ^[1-9][0-9]{0,17}$ ]] && ((limit < BUILD_MEMORY_BYTES)); then BUILD_MEMORY_BYTES=$limit; fi
}
source_build_configure() {
    BUILD_PROFILE=${SOURCE_BUILD_PROFILE:-auto}
    case "$BUILD_PROFILE" in auto|low-memory|baseline) ;; *) source_build_error 'SOURCE_BUILD_PROFILE must be auto, low-memory, or baseline.'; return 2 ;; esac
    # Validate before starting APT, checkout, or compilation.
    local workers=${SOURCE_BUILD_WORKERS:-} jobs=${SOURCE_BUILD_JOBS:-} budget memory_jobs
    [[ -z $workers ]] || source_build_integer SOURCE_BUILD_WORKERS "$workers" || return
    [[ -z $jobs ]] || source_build_integer SOURCE_BUILD_JOBS "$jobs" || return
    if [[ $BUILD_PROFILE != auto && ( -n $workers || -n $jobs ) ]]; then
        source_build_error 'Numeric overrides require SOURCE_BUILD_PROFILE=auto.'; return 2
    fi
    source_build_resources || return
    # Reserve 1 GiB for the OS/tools; budget about 1.5 GiB per compiler job.
    memory_jobs=$(((BUILD_MEMORY_BYTES - 1073741824) / 1610612736))
    ((memory_jobs > 0)) || memory_jobs=1
    budget=$BUILD_CPUS
    ((memory_jobs >= budget)) || budget=$memory_jobs
    case "$BUILD_PROFILE" in
        baseline) BUILD_WORKERS=1 BUILD_JOBS=2 ;;
        low-memory) BUILD_WORKERS=1 BUILD_JOBS=1 ;;
        auto)
            BUILD_WORKERS=${workers:-2}
            if [[ -z $workers && -n $jobs ]] && ((BUILD_WORKERS * jobs > budget)); then
                BUILD_WORKERS=$((budget / jobs))
                ((BUILD_WORKERS > 0)) || BUILD_WORKERS=1
            fi
            if [[ -z $workers ]] && ((BUILD_WORKERS > budget)); then BUILD_WORKERS=$budget; fi
            BUILD_JOBS=${jobs:-$((budget / BUILD_WORKERS))}
            ((BUILD_JOBS > 0)) || BUILD_JOBS=1
            if ((BUILD_WORKERS * BUILD_JOBS > budget)); then
                source_build_error "workers × jobs exceeds the detected CPU/memory budget ($budget). Reduce SOURCE_BUILD_WORKERS or SOURCE_BUILD_JOBS."; return 2
            fi ;;
    esac
    # The caller consumes this array after sourcing the helper.
    # shellcheck disable=SC2034
    BUILD_COLCON_ARGS=(--executor sequential)
    # shellcheck disable=SC2034
    if ((BUILD_WORKERS > 1)); then BUILD_COLCON_ARGS=(--executor parallel --parallel-workers "$BUILD_WORKERS"); fi
    export MAKEFLAGS="-j$BUILD_JOBS" CMAKE_BUILD_PARALLEL_LEVEL=$BUILD_JOBS
    # Baseline reproduces the previous configuration, with Cargo's default concurrency.
    if [[ $BUILD_PROFILE == baseline ]]; then unset CARGO_BUILD_JOBS; else export CARGO_BUILD_JOBS=$BUILD_JOBS; fi
    printf 'Build resources: CPUs=%s, memory=%s MiB, compiler budget=%s\n' "$BUILD_CPUS" "$((BUILD_MEMORY_BYTES / 1048576))" "$budget"
    printf 'Build configuration: profile=%s, packages=%s, Make/CMake jobs=%s, Cargo jobs=%s\n' \
        "$BUILD_PROFILE" "$BUILD_WORKERS" "$BUILD_JOBS" "${CARGO_BUILD_JOBS:-default}"
}
