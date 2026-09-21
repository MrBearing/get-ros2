#!/usr/bin/env bash
# Download the published installer. A failed download must fail the check.
set -euo pipefail
destination=${1:?Usage: fetch-installer.sh DESTINATION}
script=${2:-install.sh}
case "$script" in
    install.sh|setup-source.sh) ;;
    *) printf 'Unsupported script name: %s. Allowed: install.sh, setup-source.sh.\n' "$script" >&2; exit 2 ;;
esac
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --retry 3 --connect-timeout 15 --max-time 120 \
    --output "$destination" "https://get-ros2.com/$script"
test -s "$destination"
head -n 1 "$destination" | grep -Fx '#!/bin/sh'
sh -n "$destination"
sha256sum "$destination"
