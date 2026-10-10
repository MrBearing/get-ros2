#!/usr/bin/env bash
# Generate compatible restore prefixes from the prepared container's toolchain.
set -euo pipefail
case ${UBUNTU_VERSION:-} in 22.04|24.04|26.04) ;; *) exit 2 ;; esac
case ${BUILD_ARCH:-} in amd64|arm64) ;; *) exit 2 ;; esac
context=${1:?Usage: source-cache-key.sh CACHE_CONTEXT}
namespace=$(sed -n 's/^namespace=//p' "$context")
source_digest=$(sed -n 's/^source=//p' "$context")
[[ $namespace =~ ^[a-f0-9]{64}$ && $source_digest =~ ^[a-f0-9]{64}$ ]] || { echo 'Invalid compiler cache context.' >&2; exit 2; }
[[ ${GITHUB_RUN_ID:-} =~ ^[0-9]+$ && ${GITHUB_RUN_ATTEMPT:-} =~ ^[0-9]+$ ]] || exit 2
prefix="compiler-v1-$UBUNTU_VERSION-$BUILD_ARCH-$namespace-"
download_prefix="cargo-downloads-v1-$UBUNTU_VERSION-$BUILD_ARCH-"
{
    printf 'prefix=%s\nkey=%s%s-%s-%s\n' "$prefix" "$prefix" "$source_digest" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT"
    printf 'download_prefix=%s\ndownload_key=%s%s-%s-%s\n' "$download_prefix" "$download_prefix" "$source_digest" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT"
} >> "${GITHUB_OUTPUT:?}"
