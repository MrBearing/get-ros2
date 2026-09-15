#!/usr/bin/env bash
# Download the published installer. A failed download must fail the check.
set -euo pipefail
destination=${1:?Usage: fetch-installer.sh DESTINATION}
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --retry 3 --connect-timeout 15 --max-time 120 \
    --output "$destination" https://get-ros2.com/install.sh
test -s "$destination"
head -n 1 "$destination" | grep -Fx '#!/bin/sh'
sh -n "$destination"
sha256sum "$destination"
