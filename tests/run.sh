#!/usr/bin/env bash
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
installer=$(realpath "${1:-install.sh}")
sh -n "$installer"
bash "$directory/fetch.sh" "$installer"
bash "$directory/errors.sh" "$installer"
bash "$directory/regression.sh" "$installer"
