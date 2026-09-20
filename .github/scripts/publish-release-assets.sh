#!/usr/bin/env bash
# Upload or verify the exact Pages installer and checksum on a verified release.
set -euo pipefail
fail() { printf 'Release asset publication failed: %s\n' "$*" >&2; exit 1; }
[[ -n ${REPOSITORY:-} && -n ${RELEASE_TAG:-} && ${RELEASE_ID:-} =~ ^[1-9][0-9]*$ ]] ||
    fail 'REPOSITORY, RELEASE_TAG, and a numeric RELEASE_ID are required.'
site_directory=$(realpath "${1:?Usage: publish-release-assets.sh SITE_DIRECTORY}")
expected=$(cd "$site_directory" && sha256sum install.sh)
[[ $(cat "$site_directory/install.sh.sha256") == "$expected" ]] ||
    fail 'The local checksum must match install.sh and name only install.sh.'
(cd "$site_directory" && sha256sum --check --strict install.sh.sha256)

# Use the verified release ID for every API operation, including uploads.
release=$(gh api "repos/$REPOSITORY/releases/$RELEASE_ID") || fail 'Unable to read the verified release.'
jq -e --arg tag "$RELEASE_TAG" --argjson id "$RELEASE_ID" '
    .id == $id and .tag_name == $tag and .draft == false and .prerelease == false and
    (.published_at | type == "string" and length > 0)
' <<< "$release" >/dev/null || fail 'The verified release must still be published and stable.'
pages=$(gh api --paginate --slurp "repos/$REPOSITORY/releases/$RELEASE_ID/assets?per_page=100") ||
    fail 'Unable to list release assets.'
assets=$(jq -ce 'add' <<< "$pages")
temporary=$(mktemp -d /tmp/get-ros2-release-assets.XXXXXXXX)
trap 'rm -r -- "$temporary"' EXIT

verify_asset() {
    local name=$1 metadata=$2 asset_id
    asset_id=$(jq -er --arg name "$name" '
        select(.name == $name and .state == "uploaded") | .id |
        select(type == "number" and . > 0 and . == floor)
    ' <<< "$metadata") || fail "Invalid asset metadata for $name."
    [[ $asset_id =~ ^[1-9][0-9]*$ ]] || fail "Invalid asset ID for $name."
    gh api -H 'Accept: application/octet-stream' \
        "repos/$REPOSITORY/releases/assets/$asset_id" > "$temporary/$name" ||
        fail "Unable to download $name for verification."
    cmp -s "$site_directory/$name" "$temporary/$name" ||
        fail "$name differs from the prepared file. Existing assets will not be overwritten."
}

# Check both existing files before uploading anything, so a conflict fails early.
missing=()
incomplete=()
for name in install.sh install.sh.sha256; do
    matches=$(jq -c --arg name "$name" '[.[] | select(.name == $name)]' <<< "$assets")
    case $(jq length <<< "$matches") in
        0) missing+=("$name") ;;
        1)
            metadata=$(jq -c '.[0]' <<< "$matches")
            if jq -e '.state == "starter" and .size == 0' <<< "$metadata" >/dev/null; then
                asset_id=$(jq -er '.id | select(type == "number" and . > 0 and . == floor)' <<< "$metadata") ||
                    fail "Invalid asset ID for $name."
                [[ $asset_id =~ ^[1-9][0-9]*$ ]] || fail "Invalid asset ID for $name."
                incomplete+=("$asset_id")
                missing+=("$name")
            else
                verify_asset "$name" "$metadata"
            fi
            ;;
        *) fail "Multiple assets named $name exist." ;;
    esac
done
if [[ ${#missing[@]} -gt 0 ]] && jq -e '.immutable == true' <<< "$release" >/dev/null; then
    fail 'This release is immutable. Attach matching files while the release is a draft, before publishing it.'
fi
# Recover empty placeholders left by failed uploads only after all conflict checks.
for asset_id in "${incomplete[@]}"; do
    gh api --method DELETE "repos/$REPOSITORY/releases/assets/$asset_id" ||
        fail "Unable to remove incomplete asset $asset_id. Retry after resolving the API error."
done
for name in "${missing[@]}"; do
    metadata=$(gh api --method POST \
        "https://uploads.github.com/repos/$REPOSITORY/releases/$RELEASE_ID/assets?name=$name" \
        -H 'Content-Type: application/octet-stream' --input "$site_directory/$name") ||
        fail "Unable to upload $name. Retry after resolving the API error."
    verify_asset "$name" "$metadata"
done

printf 'Verified both release assets against the files prepared for GitHub Pages.\n%s\n' "$expected"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    encoded_tag=$(jq -rn --arg tag "$RELEASE_TAG" '$tag | @uri')
    printf '### Release assets\n\n[Download installer and checksum](https://github.com/%s/releases/tag/%s)\n\nSHA-256 for install.sh: %s\n' \
        "$REPOSITORY" "$encoded_tag" "${expected%% *}" >> "$GITHUB_STEP_SUMMARY"
fi
