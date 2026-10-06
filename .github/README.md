# Source-build CI controls

The source-build checks compile the C++/Python demos, CLI, and their dependency closure on Ubuntu 22.04, 24.04, and 26.04 using native amd64/arm64 runners. Every normal run starts with a clean Ubuntu container and runs source environment setup. These controls configure the CI build, not `setup-source.sh` itself.

## Concurrency

The per-OS repository and published-source workflows accept these **Run workflow** inputs:

| Input | Default | Meaning |
| --- | --- | --- |
| `source_profile` | `auto` | `auto`, `low-memory`, or `baseline` |
| `source_package_workers` | empty | Concurrent colcon packages; a positive integer, or automatic when empty |
| `source_compiler_jobs` | empty | Make/CMake/Cargo jobs per package; a positive integer, or automatic when empty |

The repository workflows also accept `benchmark` to run the three-profile comparison for that OS. Numeric overrides require the `auto` profile. Reusable `check-source.yml` takes the same values as `profile`, `package_workers`, and `compiler_jobs`.

- **Auto:** use the smaller of available CPUs and a memory budget. Reserve 1 GiB for tools/the OS and allow roughly 3 GiB per compiler job. Select up to two concurrent packages and divide the budget between them. Respect Linux CPU affinity and exposed cgroup v1/v2 CPU quotas and memory limits. Explicit settings must fit within this budget.
- **Low-memory:** one package and one compiler job, including Cargo. This reduces concurrency but does not guarantee a build can fit in any amount of memory.
- **Baseline:** the previous sequential colcon configuration with two Make/CMake jobs and Cargo's default concurrency, for comparison. It does not apply auto's resource budget.

For example, four CPUs with adequate memory select two packages with two compiler jobs each. An eight-CPU container limited to 4 GiB selects one package with one job. With 8 GiB it selects two packages with one job each. `source_compiler_jobs=4` on a four-CPU runner with adequate memory reduces automatic package concurrency to one. Specifying both numbers gives an explicit configuration; invalid or oversubscribed values fail before APT/source setup.

The memory budget describes the runner/container allocation and assumes a clean CI environment; it does not measure currently free RAM. Large individual compiler processes can exceed the per-job estimate. In the recorded Lyrical run, the maximum recorded per-process RSS was about 4 GiB, and reducing concurrency did not substantially lower peak total container memory. Allocate sufficient memory for individual packages even in low-memory mode.

The helper sets `MAKEFLAGS`, `CMAKE_BUILD_PARALLEL_LEVEL`, and `CARGO_BUILD_JOBS` to coordinate nested builds. Packages may have their own build-tool overrides; these settings are a concurrency budget, not a strict memory or process limit. Defaults remain conservative and must be evaluated using recorded measurements.

For a local disposable container, the corresponding environment variables are `SOURCE_BUILD_PROFILE`, `SOURCE_BUILD_WORKERS`, and `SOURCE_BUILD_JOBS`:

```sh
docker run --rm --init --cpus=4 --memory=16g \
  -e SOURCE_BUILD_TEST_CONTAINER=1 -e DEBIAN_FRONTEND=noninteractive \
  -e SOURCE_BUILD_PROFILE=auto -e SOURCE_BUILD_WORKERS=2 -e SOURCE_BUILD_JOBS=2 \
  -v "$PWD:/workspace:ro" -w /workspace \
  ubuntu:24.04 bash tests/source-build.sh
```

## Measurements and comparison

Each build logs detected resources and effective concurrency and saves `build-metrics.txt`. It records compilation elapsed seconds, GNU time's maximum per-process RSS, and the peak sampled **total container memory usage** (including page cache) during compilation. Memory sampling occurs once per second; brief peaks can be missed. Setup/download time is outside the compilation timer. Communication with the source-built talker/listener is checked after compilation and can still fail even when the compiler exits successfully.

Run **Benchmark source-build parallelism** to compare all three profiles on every supported OS/architecture. It prepares sources/dependencies once per job, snapshots the container before compilation, then runs baseline, auto, and low-memory builds in separate containers from that snapshot. Each build starts without build/install/compiler caches and shares the same checked-out ROS revisions and installed APT packages. Logs, exact source revisions, and measurements are retained in artifacts and a workflow summary. Completed build containers are removed after collecting diagnostics to limit disk usage.

External dependencies downloaded by vendor packages during compilation may still track upstream branches. Network variability and runner variability also affect timings. Treat a single run as evidence for that run, and retain source manifests when comparing results. The benchmark does not enable compiler caching or change the normal CI triggers.

## Recorded comparison: 2026-10-06

All six native runner configurations passed all three builds and the C++ talker/Python listener communication checks (18 successful build/runtime checks). Within each job, the three exported source manifests were byte-identical. Runners reported four effective CPUs and approximately 16 GiB of memory; auto selected two concurrent packages with two Make/CMake/Cargo jobs each.

Measurements were taken from commit `0ccfe4f`. After observing Lyrical's memory use, the scheduling estimate was increased from 1.5 to 3 GiB per compiler job. The updated selector was checked against all six recorded resource allocations and still selects the benchmarked 2 × 2 configuration. Smaller memory allocations now select fewer jobs.

The following times cover compilation, including vendor dependency retrieval during compilation, and exclude setup and source checkout. Each value is one run, not a statistical guarantee for future runners or upstream revisions.

| Ubuntu / architecture | Baseline | Auto | Low-memory | Auto time reduction |
| --- | --- | --- | --- | --- |
| 22.04 / amd64 | 18m 41s | 13m 41s | 30m 17s | 26.7% |
| 22.04 / arm64 | 16m 36s | 9m 24s | 27m 19s | 43.4% |
| 24.04 / amd64 | 19m 17s | 13m 34s | 32m 19s | 29.6% |
| 24.04 / arm64 | 21m 58s | 12m 56s | 36m 38s | 41.1% |
| 26.04 / amd64 | 48m 33s | 37m 35s | 81m 26s | 22.6% |
| 26.04 / arm64 | 42m 24s | 25m 39s | 70m 36s | 39.5% |

Peak sampled total container memory, in MiB (including page cache):

| Ubuntu / architecture | Baseline | Auto | Low-memory |
| --- | --- | --- | --- |
| 22.04 / amd64 | 1876 | 1825 | 1295 |
| 22.04 / arm64 | 1955 | 1980 | 1369 |
| 24.04 / amd64 | 2016 | 1959 | 1411 |
| 24.04 / arm64 | 2166 | 2165 | 1529 |
| 26.04 / amd64 | 7902 | 8260 | 7894 |
| 26.04 / arm64 | 8368 | 8957 | 8896 |

For Lyrical, the maximum recorded per-process RSS was approximately 4 GiB, and sampled total container memory reached approximately 8–9 GiB. The low-memory profile reduced concurrency and increased runtime, but did not substantially reduce peak memory for this workload. It is not a substitute for sufficient RAM for individual compiler processes.

Evidence: [Ubuntu 22.04](https://github.com/MrBearing/get-ros2/actions/runs/37423453468), [Ubuntu 24.04](https://github.com/MrBearing/get-ros2/actions/runs/37423457184), [Ubuntu 26.04](https://github.com/MrBearing/get-ros2/actions/runs/37423461152). Artifacts include exact source revisions, build logs, communication logs, and raw measurements.
