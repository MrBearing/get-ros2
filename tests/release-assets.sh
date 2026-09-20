#!/usr/bin/env bash
# Test preparation and publication without modifying a real GitHub release.
set -euo pipefail
directory=$(cd -- "$(dirname -- "$0")" && pwd)
scripts=$directory/../.github/scripts
sandbox=$(mktemp -d /tmp/get-ros2-asset-tests.XXXXXXXX)
trap 'rm -r -- "$sandbox"' EXIT
mkdir "$sandbox/bin" "$sandbox/source files" "$sandbox/server"
printf '#!/bin/sh\nprintf "test installer\\n"\n' > "$sandbox/source files/install.sh"
cp "$directory/../README.md" "$directory/../LICENSE" "$sandbox/source files/"
cp "$directory/../index.html" "$sandbox/source files/"
# Make the tagged page distinct from the workflow checkout's page.
printf '\n<!-- Release fixture -->\n' >> "$sandbox/source files/index.html"
bash "$scripts/prepare-release.sh" "$sandbox/source files" "$sandbox/site files" > "$sandbox/preparation.log"
for name in install.sh README.md LICENSE index.html; do
    cmp "$sandbox/source files/$name" "$sandbox/site files/$name"
done
[[ -f "$sandbox/site files/.nojekyll" ]]
grep -Fxq 'install.sh: OK' "$sandbox/preparation.log"
if bash "$scripts/prepare-release.sh" "$sandbox/source files" "$sandbox/site files" > "$sandbox/repeated.log" 2>&1; then
    echo 'Preparation reused an existing output directory' >&2
    exit 1
fi
# A rollback to a release without a page must preserve its original download files.
rm -- "$sandbox/source files/index.html"
bash "$scripts/prepare-release.sh" "$sandbox/source files" "$sandbox/legacy site" > "$sandbox/legacy.log"
[[ ! -e "$sandbox/legacy site/index.html" ]]
for name in install.sh install.sh.sha256 README.md LICENSE; do
    cmp "$sandbox/site files/$name" "$sandbox/legacy site/$name"
done
export TEST_SERVER=$sandbox/server TEST_UPLOADS=$sandbox/uploads TEST_DELETES=$sandbox/deletes
cat > "$sandbox/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == api ]] || exit 99
shift
method=GET endpoint= input= accept= content_type= paginate=0 slurp=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --method) method=$2; shift 2 ;;
        --input) input=$2; shift 2 ;;
        -H)
            case "$2" in
                'Accept: application/octet-stream') accept=octet-stream ;;
                'Content-Type: application/octet-stream') content_type=octet-stream ;;
                *) exit 99 ;;
            esac
            shift 2
            ;;
        --paginate) paginate=1; shift ;;
        --slurp) slurp=1; shift ;;
        *) [[ -z $endpoint ]] || exit 99; endpoint=$1; shift ;;
    esac
done
metadata() {
    local name=$1 id=11 state=uploaded size
    size=$(wc -c < "$TEST_SERVER/$name")
    case "$name" in install.sh.sha256) id=12 ;; setup-source.sh) id=13 ;; setup-source.sh.sha256) id=14 ;; esac
    [[ $SCENARIO != invalid_metadata ]] || state=starter
    [[ ! -f $TEST_SERVER/$name.starter ]] || state=starter
    jq -n --arg name "$name" --arg state "$state" --argjson id "$id" --argjson size "$size" \
        '{name: $name, state: $state, id: $id, size: $size}'
}
if [[ $method == DELETE ]]; then
    case "$endpoint" in
        "repos/$REPOSITORY/releases/assets/11") name=install.sh ;;
        "repos/$REPOSITORY/releases/assets/12") name=install.sh.sha256 ;;
        "repos/$REPOSITORY/releases/assets/13") name=setup-source.sh ;;
        "repos/$REPOSITORY/releases/assets/14") name=setup-source.sh.sha256 ;;
        *) exit 99 ;;
    esac
    [[ -f $TEST_SERVER/$name.starter && ! -s $TEST_SERVER/$name ]] || exit 99
    printf '%s\n' "$name" >> "$TEST_DELETES"
    [[ $SCENARIO != delete_failure ]] || exit 1
    rm -- "$TEST_SERVER/$name" "$TEST_SERVER/$name.starter"
    exit 0
fi
if [[ $method == POST ]]; then
    [[ $content_type == octet-stream && -f $input ]] || exit 99
    name=${endpoint##*name=}
    case "$name" in install.sh|install.sh.sha256|setup-source.sh|setup-source.sh.sha256) ;; *) exit 99 ;; esac
    [[ $endpoint == "https://uploads.github.com/repos/$REPOSITORY/releases/101/assets?name=$name" ]] || exit 99
    printf '%s\n' "$name" >> "$TEST_UPLOADS"
    [[ $SCENARIO != upload_failure ]] || exit 1
    [[ $SCENARIO != second_upload_failure || $name != install.sh.sha256 ]] || exit 1
    [[ ! -f $TEST_SERVER/$name ]] || exit 99
    if [[ $SCENARIO == starter_upload_failure ]]; then
        touch "$TEST_SERVER/$name" "$TEST_SERVER/$name.starter"
        exit 1
    fi
    cp "$input" "$TEST_SERVER/$name"
    if [[ $SCENARIO == corrupted_upload ]]; then printf 'corrupted\n' >> "$TEST_SERVER/$name"; fi
    metadata "$name"
    exit 0
fi
[[ $method == GET ]] || exit 99
case "$endpoint" in
    "repos/$REPOSITORY/releases/101")
        [[ $SCENARIO != release_api_failure ]] || exit 1
        draft=false pre=false published='"2026-09-20T00:00:00Z"' immutable=false id=101 tag=$RELEASE_TAG
        case "$SCENARIO" in
            draft) draft=true ;;
            prerelease) pre=true ;;
            unpublished) published=null ;;
            wrong_release) id=202 ;;
            wrong_tag) tag=other ;;
            immutable_*) immutable=true ;;
        esac
        jq -n --argjson id "$id" --arg tag "$tag" --argjson draft "$draft" --argjson pre "$pre" \
            --argjson published "$published" --argjson immutable "$immutable" \
            '{id: $id, tag_name: $tag, draft: $draft, prerelease: $pre, published_at: $published, immutable: $immutable}'
        ;;
    "repos/$REPOSITORY/releases/101/assets?per_page=100")
        [[ $SCENARIO != list_api_failure ]] || exit 1
        [[ $paginate == 1 && $slurp == 1 ]] || exit 99
        first='[]' second='[]'
        if [[ -f $TEST_SERVER/install.sh ]]; then first=$(metadata install.sh | jq '[.]'); fi
        if [[ -f $TEST_SERVER/install.sh.sha256 ]]; then second=$(metadata install.sh.sha256 | jq '[.]'); fi
        if [[ $SCENARIO == duplicate_asset ]]; then first=$(jq '. + .' <<< "$first"); fi
        for name in setup-source.sh setup-source.sh.sha256; do
            if [[ -f $TEST_SERVER/$name ]]; then
                second=$(jq --argjson asset "$(metadata "$name")" '. + [$asset]' <<< "$second")
            fi
        done
        # Keep the checksum on a separate page to verify pagination.
        jq -n --argjson first "$first" --argjson second "$second" '[$first, $second]'
        ;;
    "repos/$REPOSITORY/releases/assets/11"|"repos/$REPOSITORY/releases/assets/12"|"repos/$REPOSITORY/releases/assets/13"|"repos/$REPOSITORY/releases/assets/14")
        [[ $accept == octet-stream ]] || exit 99
        [[ $SCENARIO != download_api_failure ]] || exit 1
        name=install.sh
        case "$endpoint" in */12) name=install.sh.sha256 ;; */13) name=setup-source.sh ;; */14) name=setup-source.sh.sha256 ;; esac
        cat "$TEST_SERVER/$name"
        ;;
    *) printf 'Unexpected API request: %s\n' "$endpoint" >&2; exit 99 ;;
esac
MOCK
chmod +x "$sandbox/bin/gh"
count=0
run_case() {
    local scenario=$1 expected=$2 writes=$3 message=${4:-} deletes=${5:-0} status=0
    : > "$TEST_UPLOADS"
    : > "$TEST_DELETES"
    env PATH="$sandbox/bin:$PATH" SCENARIO="$scenario" REPOSITORY=MrBearing/get-ros2 RELEASE_TAG=v1.2.3 \
        RELEASE_ID=101 GITHUB_STEP_SUMMARY="$sandbox/summary" \
        bash "$scripts/publish-release-assets.sh" "$sandbox/site files" > "$sandbox/stdout" 2> "$sandbox/stderr" || status=$?
    if [[ $status != "$expected" || $(wc -l < "$TEST_UPLOADS") != "$writes" || $(wc -l < "$TEST_DELETES") != "$deletes" ]]; then
        cat "$sandbox/stdout" "$sandbox/stderr" "$TEST_UPLOADS" >&2
        printf 'FAIL %s: exit %s, expected %s; expected %s uploads\n' "$scenario" "$status" "$expected" "$writes" >&2
        exit 1
    fi
    if [[ $expected == 0 ]]; then
        for name in install.sh install.sh.sha256 setup-source.sh setup-source.sh.sha256; do
            if [[ -f $sandbox/site\ files/$name ]]; then cmp "$sandbox/site files/$name" "$TEST_SERVER/$name"; fi
        done
        grep -Fq 'Verified release assets' "$sandbox/stdout"
    else
        grep -Fq -- "$message" "$sandbox/stderr" || { cat "$sandbox/stderr" >&2; exit 1; }
    fi
    count=$((count + 1))
    printf 'ok %s - release assets: %s\n' "$count" "$scenario"
}
clear_assets() { find "$TEST_SERVER" -type f -delete; }
run_case first_upload 0 2
run_case identical_retry 0 0
run_case immutable_existing 0 0
run_case duplicate_asset 1 0 'Multiple assets'
run_case download_api_failure 1 0 'Unable to download'
run_case invalid_metadata 1 0 'Invalid asset metadata'
printf 'changed\n' >> "$TEST_SERVER/install.sh"
run_case conflicting_installer 1 0 'differs from the prepared file'
clear_assets
cp "$sandbox/site files/install.sh.sha256" "$TEST_SERVER/install.sh.sha256"
printf 'changed\n' >> "$TEST_SERVER/install.sh.sha256"
run_case conflicting_checksum 1 0 'differs from the prepared file'
clear_assets
run_case immutable_missing 1 0 'release is immutable'
for scenario in draft prerelease unpublished wrong_release wrong_tag; do
    run_case "$scenario" 1 0 'release must still be published and stable'
done
run_case release_api_failure 1 0 'Unable to read the verified release'
run_case list_api_failure 1 0 'Unable to list release assets'
run_case upload_failure 1 1 'Unable to upload'
run_case second_upload_failure 1 2 'Unable to upload'
run_case retry_partial_upload 0 1
clear_assets
cp "$sandbox/site files/install.sh.sha256" "$TEST_SERVER/install.sh.sha256"
run_case existing_checksum 0 1
clear_assets
run_case corrupted_upload 1 1 'differs from the prepared file'
clear_assets
run_case starter_upload_failure 1 1 'Unable to upload'
run_case immutable_starter 1 0 'release is immutable'
cp "$sandbox/site files/install.sh.sha256" "$TEST_SERVER/install.sh.sha256"
printf 'changed\n' >> "$TEST_SERVER/install.sh.sha256"
run_case starter_with_conflict 1 0 'differs from the prepared file'
cp "$sandbox/site files/install.sh.sha256" "$TEST_SERVER/install.sh.sha256"
run_case delete_failure 1 0 'Unable to remove incomplete asset' 1
run_case starter_retry 0 1 '' 1
clear_assets
touch "$TEST_SERVER/install.sh.sha256" "$TEST_SERVER/install.sh.sha256.starter"
run_case checksum_starter_retry 0 2 '' 1
clear_assets
# New releases publish both standalone scripts; old releases above still publish two assets.
cp "$directory/../setup-source.sh" "$directory/../SOURCE_BUILD.md" "$sandbox/source files/"
bash "$scripts/prepare-release.sh" "$sandbox/source files" "$sandbox/source site" > "$sandbox/source-preparation.log"
for name in setup-source.sh setup-source.sh.sha256 SOURCE_BUILD.md; do
    cp "$sandbox/source site/$name" "$sandbox/site files/"
done
cmp "$directory/../setup-source.sh" "$sandbox/site files/setup-source.sh"
run_case both_scripts 0 4
run_case both_scripts_retry 0 0
run_case immutable_both_scripts 0 0
printf 'changed\n' >> "$TEST_SERVER/setup-source.sh"
run_case source_conflict 1 0 'setup-source.sh differs'
clear_assets
cp "$sandbox/site files/setup-source.sh.sha256" "$TEST_SERVER/setup-source.sh.sha256"
printf 'changed\n' >> "$TEST_SERVER/setup-source.sh.sha256"
run_case source_checksum_conflict 1 0 'setup-source.sh.sha256 differs'
clear_assets
touch "$TEST_SERVER/setup-source.sh" "$TEST_SERVER/setup-source.sh.starter"
run_case source_starter_retry 0 4 '' 1
clear_assets
run_case second_upload_failure 1 2 'Unable to upload'
run_case both_scripts_partial_retry 0 3
printf 'bad manifest\n' > "$sandbox/site files/setup-source.sh.sha256"
run_case invalid_source_checksum 1 0 'local checksum must match setup-source.sh'
clear_assets
rm -- "$sandbox/site files/setup-source.sh" "$sandbox/site files/setup-source.sh.sha256"
printf 'bad manifest\n' > "$sandbox/site files/install.sh.sha256"
run_case invalid_local_checksum 1 0 'local checksum must match'
printf 'Passed %s release asset publication cases and preparation checks\n' "$count"
