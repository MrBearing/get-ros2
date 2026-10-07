#!/usr/bin/env bash
# Compile real fixtures to verify hits, invalidation, bypass, and error propagation.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
sandbox=$(mktemp -d /tmp/get-ros2-compiler-cache.XXXXXXXX)
trap 'sccache --stop-server >/dev/null 2>&1 || true; rm -r -- "$sandbox"' EXIT
mkdir "$sandbox/cache" "$sandbox/source"
cd "$sandbox/source"
printf 'fixture revision one\n' > exact.repos
export SOURCE_BUILD_CACHE=on SOURCE_BUILD_CACHE_DIR=$sandbox/cache
# shellcheck source=tests/build-cache.sh
source "$directory/build-cache.sh"
source_cache_enable > "$sandbox/startup.log"
count=0
pass() { count=$((count+1)); printf 'ok %s - %s\n' "$count" "$*"; }
hits() { ccache --print-stats | awk '$1 == "direct_cache_hit" || $1 == "preprocessed_cache_hit" {sum += $2} END {print sum+0}'; }
misses() { ccache --print-stats | awk '$1 == "cache_miss" {print $2}'; }
printf '#define VALUE 1\n' > value.h
cat > main.cpp <<'CPP'
#include "value.h"
#include <cstdio>
#ifndef EXTRA
#define EXTRA 0
#endif
int main() { std::printf("%d\n", VALUE + EXTRA); }
CPP
compile() { c++ -c main.cpp -o main.o "$@" && c++ main.o -o fixture; }
compile
[[ $(./fixture) == 1 && $(misses) -gt 0 ]]
pass 'cold C++ compile produces a cache miss and runs'
rm main.o fixture
before=$(hits); compile
[[ $(hits) -gt $before && $(./fixture) == 1 ]]
pass 'fresh C++ output directory reuses a cached object and relinks'
printf '#define VALUE 2\n' > value.h
before=$(misses); compile
[[ $(misses) -gt $before && $(./fixture) == 2 ]]
pass 'changed header invalidates cached compilation'
before=$(misses); compile -DEXTRA=3
[[ $(misses) -gt $before && $(./fixture) == 5 ]]
pass 'changed compiler flags invalidate cached compilation'
printf '\ninvalid C++ source\n' >> main.cpp
if compile > "$sandbox/failed.log" 2>&1; then echo 'A cached build hid a compiler error.' >&2; exit 1; fi
pass 'real compiler errors remain failures'
cat > library.rs <<'RUST'
mod value;
pub fn get_value() -> u32 { value::VALUE }
RUST
printf 'pub const VALUE: u32 = 1;\n' > value.rs
mkdir output
rust_compile() { sccache "$(command -v rustc)" --crate-name cache_fixture --crate-type rlib --emit link,dep-info --out-dir output library.rs; }
rust_hits() { sccache --show-stats | awk '/^Cache hits / {print $NF; exit}'; }
rust_misses() { sccache --show-stats | awk '/^Cache misses / {print $NF; exit}'; }
rust_compile
[[ $(rust_misses) -gt 0 ]]
pass 'cold Rust library compile produces a miss'
cp output/libcache_fixture.rlib "$sandbox/old.rlib"
rm -r output; mkdir output
before=$(rust_hits); rust_compile
[[ $(rust_hits) -gt $before ]]
cmp output/libcache_fixture.rlib "$sandbox/old.rlib"
pass 'fresh Rust output directory reuses a cached library'
printf 'pub const VALUE: u32 = 2;\n' > value.rs
before=$(rust_misses); rust_compile
[[ $(rust_misses) -gt $before ]]
if cmp -s output/libcache_fixture.rlib "$sandbox/old.rlib"; then exit 1; fi
pass 'changed Rust dependency invalidates the cached library'
before=$(rust_misses)
sccache "$(command -v rustc)" --crate-name cache_fixture --crate-type rlib --emit link,dep-info -C opt-level=2 --out-dir output library.rs
[[ $(rust_misses) -gt $before ]]
pass 'changed Rust build options invalidate compilation'
printf 'not valid Rust\n' > library.rs
if rust_compile > "$sandbox/rust-failed.log" 2>&1; then exit 1; fi
pass 'cached Rust builds preserve compiler failures'
source_cache_context
namespace=$(sed -n 's/^namespace=//p' cache-context.txt)
source_before=$(sed -n 's/^source=//p' cache-context.txt)
printf 'fixture revision two\n' > exact.repos
source_cache_context
[[ $(sed -n 's/^namespace=//p' cache-context.txt) == "$namespace" ]]
[[ $(sed -n 's/^source=//p' cache-context.txt) != "$source_before" ]]
pass 'source revision changes preserve compatible C++ namespace but change source identity'
# Tool/package context changes must select a different compatible-cache namespace.
mkdir "$sandbox/bin"
cat > "$sandbox/bin/dpkg-query" <<'MOCK'
#!/bin/sh
printf 'fixture-package=2\n'
MOCK
chmod +x "$sandbox/bin/dpkg-query"
PATH="$sandbox/bin:$PATH" source_cache_context
[[ $(sed -n 's/^namespace=//p' cache-context.txt) != "$namespace" ]]
pass 'changed system package context selects a different compiler namespace'
source_cache_stats > "$sandbox/stats.log"
[[ -s ccache-stats.txt && -s sccache-stats.json ]]
pass 'cache statistics are recorded'
# Changing source revisions must not re-enable the previous Rust namespace.
old_dir=$SCCACHE_DIR
source_cache_enable > "$sandbox/restart.log"
[[ $SCCACHE_DIR != "$old_dir" && ! -d $old_dir ]]
source_cache_stats > /dev/null
pass 'Rust cache namespace changes after source revisions'
SOURCE_BUILD_CACHE=off
# Run bypass in a fresh shell as done by a fresh uncached Docker container.
# shellcheck disable=SC2016
env -u RUSTC_WRAPPER -u CCACHE_DIR SOURCE_BUILD_CACHE=off bash -eu -c 'source "$1"; source_cache_enable; test -z "${RUSTC_WRAPPER:-}"' bash "$directory/build-cache.sh"
pass 'cache bypass leaves Rust compilation unwrapped'
SOURCE_BUILD_CACHE=unknown
status=0; source_cache_validate > "$sandbox/invalid.log" 2>&1 || status=$?
[[ $status == 2 ]]
pass 'invalid cache mode rejected'
printf 'Passed %s real compiler-cache cases\n' "$count"
