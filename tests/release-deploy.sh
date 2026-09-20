#!/usr/bin/env bash
# Exercise the deployment gate offline with controlled GitHub API responses.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
verifier=$directory/../.github/scripts/verify-release.sh
sandbox=$(mktemp -d /tmp/get-ros2-release-tests.XXXXXXXX)
trap 'rm -r -- "$sandbox"' EXIT
mkdir "$sandbox/bin"
export TEST_SHA=1111111111111111111111111111111111111111
export TEST_OTHER_SHA=2222222222222222222222222222222222222222
export TEST_TAG_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export TEST_NESTED_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export TEST_CALLS=$sandbox/calls

cat > "$sandbox/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == api ]] || exit 99
shift
printf '%s\n' "$*" >> "$TEST_CALLS"
if [[ ${1:-} == --method ]]; then
    [[ $2 == GET ]] || exit 99
    shift 2
fi
endpoint=$1
shift
encoded=$(jq -rn --arg tag "$RELEASE_TAG" '$tag | @uri')
case "$endpoint" in
    "repos/$REPOSITORY/releases/tags/$encoded")
        [[ $SCENARIO != missing_release && $SCENARIO != api_failure ]] || exit 1
        draft=false prerelease=false published='"2026-09-19T00:00:00Z"' id=101 tag=$RELEASE_TAG
        case "$SCENARIO" in
            draft) draft=true ;;
            prerelease) prerelease=true ;;
            unpublished) published=null ;;
            replaced_release) id=202 ;;
            mismatched_release) tag=other ;;
        esac
        jq -n --arg tag "$tag" --argjson draft "$draft" --argjson pre "$prerelease" \
            --argjson published "$published" --argjson id "$id" \
            '{id: $id, tag_name: $tag, draft: $draft, prerelease: $pre, published_at: $published, target_commitish: "main"}'
        ;;
    "repos/$REPOSITORY/git/ref/tags/$encoded")
        [[ $SCENARIO != missing_tag ]] || exit 1
        type=commit sha=$TEST_SHA ref=refs/tags/$RELEASE_TAG
        case "$SCENARIO" in
            annotated|nested|cyclic|missing_annotation) type=tag; sha=$TEST_TAG_SHA ;;
            moved_tag) sha=$TEST_OTHER_SHA ;;
            invalid_sha) sha=invalid ;;
            non_commit) type=tree ;;
            mismatched_ref) ref=refs/heads/main ;;
        esac
        jq -n --arg type "$type" --arg sha "$sha" --arg ref "$ref" \
            '{ref: $ref, object: {type: $type, sha: $sha}}'
        ;;
    "repos/$REPOSITORY/git/tags/$TEST_TAG_SHA"|"repos/$REPOSITORY/git/tags/$TEST_NESTED_SHA")
        [[ $SCENARIO != missing_annotation ]] || exit 1
        type=commit sha=$TEST_SHA
        if [[ $SCENARIO == cyclic ]]; then
            type=tag sha=$TEST_TAG_SHA
        elif [[ $SCENARIO == nested && $endpoint == */"$TEST_TAG_SHA" ]]; then
            type=tag sha=$TEST_NESTED_SHA
        fi
        jq -n --arg type "$type" --arg sha "$sha" '{object: {type: $type, sha: $sha}}'
        ;;
    "repos/$REPOSITORY/actions/workflows/ci-ubuntu-"*.yml/runs)
        [[ "$*" == "-f branch=main -f event=push -f head_sha=$TEST_SHA -f per_page=1" ]] || exit 99
        [[ $SCENARIO != ci_api_failure ]] || exit 1
        if [[ $SCENARIO == ci_missing ]]; then
            printf '{"workflow_runs": []}\n'
            exit 0
        fi
        status=completed conclusion='"success"' sha=$TEST_SHA branch=main event=push
        case "$SCENARIO" in
            ci_failed_22) [[ $endpoint != */ci-ubuntu-22-04.yml/runs ]] || conclusion='"failure"' ;;
            ci_failed_24) [[ $endpoint != */ci-ubuntu-24-04.yml/runs ]] || conclusion='"failure"' ;;
            ci_failed_26) [[ $endpoint != */ci-ubuntu-26-04.yml/runs ]] || conclusion='"failure"' ;;
            ci_running) status=in_progress; conclusion=null ;;
            ci_queued) status=queued; conclusion=null ;;
            ci_cancelled) conclusion='"cancelled"' ;;
            ci_skipped) conclusion='"skipped"' ;;
            ci_wrong_sha) sha=$TEST_OTHER_SHA ;;
            ci_wrong_branch) branch=feature/test ;;
            ci_wrong_event) event=pull_request ;;
        esac
        jq -n --arg status "$status" --argjson conclusion "$conclusion" --arg sha "$sha" \
            --arg branch "$branch" --arg event "$event" \
            '{workflow_runs: [{status: $status, conclusion: $conclusion, head_sha: $sha, head_branch: $branch, event: $event}]}'
        ;;
    *) printf 'Unexpected API request: %s\n' "$endpoint" >&2; exit 99 ;;
esac
MOCK
chmod +x "$sandbox/bin/gh"

count=0
check_case() {
    local scenario=$1 expected=$2 message=$3 status=0
    shift 3
    : > "$TEST_CALLS"
    : > "$sandbox/output"
    : > "$sandbox/summary"
    env PATH="$sandbox/bin:$PATH" SCENARIO="$scenario" REPOSITORY=MrBearing/get-ros2 \
        RELEASE_TAG=v1.2.3 EXPECTED_SHA= EXPECTED_RELEASE_ID= \
        GITHUB_OUTPUT="$sandbox/output" GITHUB_STEP_SUMMARY="$sandbox/summary" \
        "$@" bash "$verifier" > "$sandbox/stdout" 2> "$sandbox/stderr" || status=$?
    if [[ $status != "$expected" ]]; then
        cat "$sandbox/stdout" "$sandbox/stderr" >&2
        printf 'FAIL %s: expected exit %s, got %s\n' "$scenario" "$expected" "$status" >&2
        exit 1
    fi
    if [[ $expected == 0 ]]; then
        grep -Fxq "sha=$TEST_SHA" "$sandbox/output"
        grep -Fxq 'release_id=101' "$sandbox/output"
        [[ $(grep -c '/actions/workflows/' "$TEST_CALLS") -eq 3 ]]
    else
        grep -Fq -- "$message" "$sandbox/stderr" || { cat "$sandbox/stderr" >&2; exit 1; }
        grep -Fq 'No files were published.' "$sandbox/summary"
        [[ ! -s "$sandbox/output" ]]
    fi
    count=$((count + 1))
    printf 'ok %s - release verification: %s\n' "$count" "$scenario"
}

check_case stable 0 '' EXPECTED_SHA="$TEST_SHA" EXPECTED_RELEASE_ID=101
check_case manual_older_release 0 ''
check_case annotated 0 '' EXPECTED_SHA="$TEST_SHA"
check_case nested 0 '' EXPECTED_SHA="$TEST_SHA"
check_case encoded_tag 0 '' RELEASE_TAG=release/v1.2.3
grep -Fq '/releases/tags/release%2Fv1.2.3' "$TEST_CALLS"
grep -Fxq 'tag=release/v1.2.3' "$sandbox/output"
check_case empty_tag 1 'are required' RELEASE_TAG=
check_case invalid_tag 1 'control characters' RELEASE_TAG=$'v1.2.3\nsha=injected'
check_case missing_release 1 'Unable to read the release'
check_case api_failure 1 'Unable to read the release'
for scenario in draft prerelease unpublished mismatched_release; do
    check_case "$scenario" 1 'published, non-draft, non-prerelease'
done
check_case replaced_release 1 'release was replaced' EXPECTED_RELEASE_ID=101
check_case missing_tag 1 'Unable to read the release tag'
check_case mismatched_ref 1 'tag reference does not match'
check_case invalid_sha 1 'invalid Git object SHA'
check_case non_commit 1 'must resolve to a commit'
check_case cyclic 1 'too many nested annotated tags'
check_case missing_annotation 1 'Unable to resolve the annotated tag'
check_case moved_tag 1 'no longer points to the expected commit' EXPECTED_SHA="$TEST_SHA"
for scenario in ci_failed_22 ci_failed_24 ci_failed_26 ci_running ci_queued ci_cancelled ci_skipped ci_missing ci_wrong_sha ci_wrong_branch ci_wrong_event; do
    check_case "$scenario" 1 'All three main push CI workflows must pass'
done
check_case ci_api_failure 1 'Unable to read CI results'
printf 'Passed %s release deployment cases\n' "$count"
