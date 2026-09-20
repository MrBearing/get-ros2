#!/usr/bin/env bash
# Prepare one set of files for both release assets and GitHub Pages.
set -euo pipefail
source_directory=${1:?Usage: prepare-release.sh SOURCE_DIRECTORY OUTPUT_DIRECTORY}
output_directory=${2:?Usage: prepare-release.sh SOURCE_DIRECTORY OUTPUT_DIRECTORY}
mkdir "$output_directory"
cp "$source_directory/install.sh" "$source_directory/README.md" "$source_directory/LICENSE" "$output_directory/"
touch "$output_directory/.nojekyll"
cd "$output_directory"
sha256sum install.sh > install.sh.sha256
sha256sum --check --strict install.sh.sha256
