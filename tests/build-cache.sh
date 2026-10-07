#!/usr/bin/env bash
# Cache only compiler results/downloads; never reuse an installed ROS environment.
source_cache_validate() {
    case ${SOURCE_BUILD_CACHE:-off} in on|off) ;; *) echo 'SOURCE_BUILD_CACHE must be on or off.' >&2; return 2 ;; esac
}
source_cache_install() {
    # Signed Ubuntu packages supply ccache; pin and verify the portable Rust wrapper.
    apt-get install -y --no-install-recommends ccache
    local target checksum temporary
    case $(dpkg --print-architecture) in
        amd64) target=x86_64-unknown-linux-musl; checksum=45f1447fbe231e3037bde351ef70677dd212216c8d62ae7ca409fecc4d6acc89 ;;
        arm64) target=aarch64-unknown-linux-musl; checksum=2b3284d5da3b46a47dc4229e75bb7b88ac4aa99c8d754fb7d2f84997e5a4354a ;;
        *) echo 'Compiler caching supports only amd64 and arm64.' >&2; return 2 ;;
    esac
    temporary=$(mktemp -d)
    curl -fLsS --proto '=https' --proto-redir '=https' --retry 3 \
        "https://github.com/mozilla/sccache/releases/download/v0.18.0/sccache-v0.18.0-$target.tar.gz" -o "$temporary/sccache.tar.gz"
    printf '%s  %s\n' "$checksum" "$temporary/sccache.tar.gz" | sha256sum --check --strict
    tar -xzf "$temporary/sccache.tar.gz" -C "$temporary"
    install -m 755 "$temporary/sccache-v0.18.0-$target/sccache" /usr/local/bin/sccache
    rm -r -- "$temporary"
}
source_cache_context() {
    local tool binary namespace source_digest
    local PATH=${PATH//\/usr\/lib\/ccache:/}
    {
        printf 'compiler-cache-format=v1\ncmake=Release,BUILD_TESTING=OFF\ncargo-incremental=0\n'
        dpkg-query -W -f='${binary:Package}=${Version}\n' | LC_ALL=C sort
        for tool in cc c++ cmake ccache sccache rustc cargo; do
            if binary=$(command -v "$tool"); then
                sha256sum "$(readlink -f "$binary")"
                "$tool" --version | head -n 1
            fi
        done
    } > cache-toolchain.txt
    namespace=$(sha256sum cache-toolchain.txt); namespace=${namespace%% *}
    source_digest=$(sha256sum exact.repos); source_digest=${source_digest%% *}
    printf 'namespace=%s\nsource=%s\n' "$namespace" "$source_digest" > cache-context.txt
}
source_cache_enable() {
    source_cache_validate || return
    # Cache-off runs use the same release settings without compiler wrappers.
    export CARGO_INCREMENTAL=0
    if [[ ${SOURCE_BUILD_CACHE:-off} == off ]]; then return 0; fi
    local root=${SOURCE_BUILD_CACHE_DIR:-/cache} source_digest
    [[ -d $root && -w $root ]] || { echo 'The developer must own a writable SOURCE_BUILD_CACHE_DIR.' >&2; return 2; }
    source_digest=$(sha256sum exact.repos); source_digest=${source_digest%% *}
    mkdir -p "$root/ccache" "$root/rust/$source_digest" "$root/downloads"
    # Rust does not restore across source revisions; keep only the active namespace.
    find "$root/rust" -mindepth 1 -maxdepth 1 -type d ! -name "$source_digest" -exec rm -r -- {} +
    # Never load configuration files from a restored compiler cache.
    export CCACHE_DIR=$root/ccache CCACHE_CONFIGPATH=/tmp/get-ros2-ccache.conf
    printf 'compiler_check = content\nmax_size = 512M\n' > "$CCACHE_CONFIGPATH"
    export CCACHE_BASEDIR=$HOME CCACHE_COMPILERCHECK=content CCACHE_MAXSIZE=512M
    export SCCACHE_DIR=$root/rust/$source_digest SCCACHE_CACHE_SIZE=768M
    export SCCACHE_IDLE_TIMEOUT=0 SCCACHE_IGNORE_SERVER_IO_ERROR=1
    export CARGO_HOME=$root/downloads RUSTC_WRAPPER=/usr/local/bin/sccache
    # PATH wrappers also cover nested CMake/Make projects that do not inherit launchers.
    export PATH="/usr/lib/ccache:$PATH"
    ccache --zero-stats
    sccache --start-server
    sccache --zero-stats
}
source_cache_stats() {
    [[ ${SOURCE_BUILD_CACHE:-off} == on ]] || return 0
    ccache --print-stats > ccache-stats.txt
    sccache --show-stats --stats-format json > sccache-stats.json
    sccache --stop-server > sccache-stop.txt
    cat ccache-stats.txt sccache-stats.json
    source_cache_trim_downloads
}

source_cache_trim_downloads() {
    local directory limit size entry
    # Evict whole archives/repos, never individual Git objects or active build outputs.
    for directory in "$CARGO_HOME/registry/cache" "$CARGO_HOME/git/db"; do
        [[ -d $directory ]] || continue
        limit=268435456
        size=$(du -sb "$directory"); size=${size%%[[:space:]]*}
        while ((size > limit)); do
            entry=$(find "$directory" -mindepth 1 -maxdepth 1 -printf '%T@ %p\n' | LC_ALL=C sort -n | sed -n '1p')
            [[ -n $entry ]] || break
            rm -r -- "${entry#* }"
            size=$(du -sb "$directory"); size=${size%%[[:space:]]*}
        done
    done
}
