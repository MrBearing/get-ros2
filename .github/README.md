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

- **Auto:** use the smaller of available CPUs and a memory budget. Reserve 1 GiB for tools/the OS and allow roughly 1.5 GiB per compiler job. Select up to two concurrent packages and divide the budget between them. Respect Linux CPU affinity and exposed cgroup v1/v2 CPU quotas and memory limits. Explicit settings must fit within this budget.
- **Low-memory:** one package and one compiler job, including Cargo. This reduces concurrency but does not guarantee a build can fit in any amount of memory.
- **Baseline:** the previous sequential colcon configuration with two Make/CMake jobs and Cargo's default concurrency, for comparison. It does not apply auto's resource budget.

For example, four CPUs with adequate memory select two packages with two compiler jobs each. An eight-CPU container limited to 4 GiB selects two packages with one job each. `source_compiler_jobs=4` on a four-CPU runner reduces automatic package concurrency to one. Specifying both numbers gives an explicit configuration; invalid or oversubscribed values fail before APT/source setup.

The helper sets `MAKEFLAGS`, `CMAKE_BUILD_PARALLEL_LEVEL`, and `CARGO_BUILD_JOBS` to coordinate nested builds. Packages may have their own build-tool overrides; these settings are a concurrency budget, not a strict memory or process limit. Defaults remain conservative and must be evaluated using recorded measurements.

For a local disposable container, the corresponding environment variables are `SOURCE_BUILD_PROFILE`, `SOURCE_BUILD_WORKERS`, and `SOURCE_BUILD_JOBS`:

```sh
docker run --rm --init --cpus=4 --memory=8g \
  -e SOURCE_BUILD_TEST_CONTAINER=1 -e DEBIAN_FRONTEND=noninteractive \
  -e SOURCE_BUILD_PROFILE=auto -e SOURCE_BUILD_WORKERS=2 -e SOURCE_BUILD_JOBS=2 \
  -v "$PWD:/workspace:ro" -w /workspace \
  ubuntu:24.04 bash tests/source-build.sh
```

## Measurements and comparison

Each build logs detected resources and effective concurrency and saves `build-metrics.txt`. It records compilation elapsed seconds, GNU time's maximum per-process RSS, and the peak sampled **total container memory usage** (including page cache) during compilation. Memory sampling occurs once per second; brief peaks can be missed. Setup/download time is outside the compilation timer. Communication with the source-built talker/listener is checked after compilation and can still fail even when the compiler exits successfully.

Run **Benchmark source-build parallelism** to compare all three profiles on every supported OS/architecture. It prepares sources/dependencies once per job, snapshots the container before compilation, then runs baseline, auto, and low-memory builds in separate containers from that snapshot. Each build starts without build/install/compiler caches and shares the same checked-out ROS revisions and installed APT packages. Logs, exact source revisions, and measurements are retained in artifacts and a workflow summary. Completed build containers are removed after collecting diagnostics to limit disk usage.

External dependencies downloaded by vendor packages during compilation may still track upstream branches. Network variability and runner variability also affect timings. Treat a single run as evidence for that run, and retain source manifests when comparing results. The benchmark does not enable compiler caching or change the normal CI triggers.
