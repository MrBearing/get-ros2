#!/usr/bin/env bash
# Prepare one set of files for both release assets and GitHub Pages.
set -euo pipefail
source_directory=${1:?Usage: prepare-release.sh SOURCE_DIRECTORY OUTPUT_DIRECTORY}
output_directory=${2:?Usage: prepare-release.sh SOURCE_DIRECTORY OUTPUT_DIRECTORY}
mkdir "$output_directory"
cp "$source_directory/install.sh" "$source_directory/README.md" "$source_directory/LICENSE" "$output_directory/"
# Older releases can still be redeployed without borrowing a page from a newer release.
if [[ -f "$source_directory/index.html" ]]; then
    cp "$source_directory/index.html" "$output_directory/"
fi
if [[ -f "$source_directory/setup-source.sh" ]]; then
    cp "$source_directory/setup-source.sh" "$output_directory/"
fi
touch "$output_directory/.nojekyll"
cd "$output_directory"
for script in install.sh setup-source.sh; do
    if [[ -f $script ]]; then
        sha256sum "$script" > "$script.sha256"
        sha256sum --check --strict "$script.sha256"
    fi
done
