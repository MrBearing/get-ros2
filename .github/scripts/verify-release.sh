#!/usr/bin/env bash
# Verify a published stable release and CI for its exact commit without deploying it.
set -euo pipefail

fail() {
    printf 'Release verification failed: %s\n' "$*" >&2
    if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
        printf 'Deployment blocked: %s No files were published.\n' "$*" >> "$GITHUB_STEP_SUMMARY"
    fi
    exit 1
}

[[ -n ${REPOSITORY:-} && -n ${RELEASE_TAG:-} && -n ${GITHUB_OUTPUT:-} ]] ||
    fail 'REPOSITORY, RELEASE_TAG, and GITHUB_OUTPUT are required.'
[[ ! $RELEASE_TAG =~ [[:cntrl:]] ]] || fail 'The release tag contains control characters.'
encoded_tag=$(jq -rn --arg tag "$RELEASE_TAG" '$tag | @uri')
release=$(gh api "repos/$REPOSITORY/releases/tags/$encoded_tag") ||
    fail 'Unable to read the release. Check that it exists and the token has access.'
jq -e --arg tag "$RELEASE_TAG" '
    .tag_name == $tag and .draft == false and .prerelease == false and
    (.published_at | type == "string" and length > 0) and
    (.id | type == "number" and . > 0 and . == floor)
' <<< "$release" >/dev/null || fail 'The tag must belong to a published, non-draft, non-prerelease release.'
release_id=$(jq -r .id <<< "$release")
if [[ -n ${EXPECTED_RELEASE_ID:-} && $release_id != "$EXPECTED_RELEASE_ID" ]]; then
    fail 'The release was replaced after this deployment was requested.'
fi

# Resolve the tag reference explicitly; target_commitish can be a moving branch name.
reference=$(gh api "repos/$REPOSITORY/git/ref/tags/$encoded_tag") || fail 'Unable to read the release tag.'
jq -e --arg ref "refs/tags/$RELEASE_TAG" '.ref == $ref' <<< "$reference" >/dev/null ||
    fail 'The tag reference does not match the requested release.'
object=$(jq -c .object <<< "$reference")
depth=0
while :; do
    sha=$(jq -r .sha <<< "$object")
    [[ $sha =~ ^[0-9a-f]{40}$ ]] || fail 'The release tag has an invalid Git object SHA.'
    type=$(jq -r .type <<< "$object")
    case "$type" in
        commit) break ;;
        tag)
            depth=$((depth + 1))
            [[ $depth -le 10 ]] || fail 'The release tag has too many nested annotated tags.'
            annotation=$(gh api "repos/$REPOSITORY/git/tags/$sha") || fail 'Unable to resolve the annotated tag.'
            object=$(jq -c .object <<< "$annotation")
            ;;
        *) fail 'The release tag must resolve to a commit.' ;;
    esac
done
if [[ -n ${EXPECTED_SHA:-} && $sha != "$EXPECTED_SHA" ]]; then
    fail 'The release tag no longer points to the expected commit.'
fi

for workflow in ci-ubuntu-22-04.yml ci-ubuntu-24-04.yml ci-ubuntu-26-04.yml; do
    runs=$(gh api --method GET "repos/$REPOSITORY/actions/workflows/$workflow/runs" \
        -f branch=main -f event=push -f head_sha="$sha" -f per_page=1) ||
        fail "Unable to read CI results for $workflow."
    if ! jq -e --arg sha "$sha" '
        .workflow_runs[0] |
        .head_sha == $sha and .head_branch == "main" and .event == "push" and
        .status == "completed" and .conclusion == "success"
    ' <<< "$runs" >/dev/null; then
        state=$(jq -r '.workflow_runs[0] | .conclusion // .status // "missing"' <<< "$runs")
        fail "$workflow is $state for $sha. All three main push CI workflows must pass; retry after CI succeeds."
    fi
done

printf 'sha=%s\ntag=%s\nrelease_id=%s\n' "$sha" "$RELEASE_TAG" "$release_id" >> "$GITHUB_OUTPUT"
printf 'Verified release %s (ID %s), commit %s, and all three CI workflows.\n' "$RELEASE_TAG" "$release_id" "$sha"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    printf 'Verified release %s (ID %s), commit %s, and all three CI workflows.\n' \
        "$RELEASE_TAG" "$release_id" "$sha" >> "$GITHUB_STEP_SUMMARY"
fi
