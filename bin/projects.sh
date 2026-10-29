#!/bin/bash
# Captain Levi: look for old build folders (node_modules, target, .venv, .next, ...) in project folders.
#
# Only ever looks: it writes a plan and deletes nothing. The plan has the same six fields per record as
# bin/clean.sh --plan-out (section, path, size in KB, item count, size known, covering ancestor). A second
# file, PLAN.meta, holds what the app shows beside each folder and is never trusted to delete anything:
# five NUL-separated fields per record: path, last change (epoch seconds), state (old, recent, running,
# unverified), project folder, ticked (yes or no). Deleting happens only in engine/apply.sh --projects,
# which checks every folder again.
#
# Usage: projects.sh --plan-out FILE [--root DIR]...
#   --plan-out  absolute path of the plan to write
#   --root      one more folder to look in (inside the home folder); repeatable
# Progress goes to stdout as "➤ Looking in NAME"; a line starting "! " says a folder was not fully read.

set -uo pipefail

if [[ "$EUID" -eq 0 ]]; then
    echo "Run without sudo: Captain Levi never uses admin rights." >&2
    exit 2
fi

ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

plan_out=""
extra_roots=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan-out) plan_out="${2:-}"; shift ;;
        --root) extra_roots+=("${2:-}"); shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
if [[ "$plan_out" != /* ]]; then
    echo "--plan-out needs an absolute file path" >&2
    exit 2
fi
umask 077

# Scratch space for Mole's scan (it keeps a "still scanning" marker under XDG_CACHE_HOME). One fixed folder,
# reused each run, in the per-user temporary folder.
scratch="${TMPDIR:-/tmp}"
scratch="${scratch%/}/captain-levi-projects"
mkdir -p "$scratch/xdg/mole" || exit 1
export XDG_CACHE_HOME="$scratch/xdg"
export MOLE_TEST_NO_AUTH="${MOLE_TEST_NO_AUTH:-1}"

# shellcheck source=engine/projects_lib.sh
source "$ENGINE_ROOT/engine/projects_lib.sh"
set +e # the sourced files turn errexit on; every step here is handled on its own

budget="${MAC_CLEANER_PROJECTS_BUDGET:-120}"
[[ "$budget" =~ ^[1-9][0-9]*$ ]] || budget=120
deadline=$((SECONDS + budget))

MC_CACHE_FILES=true # one date walk per project during the scan; apply.sh walks afresh before each delete
mc_projects_load_cwds || echo "! could not see which programs are running; every folder is left unticked"

roots="$(mc_projects_roots "${extra_roots[@]+"${extra_roots[@]}"}")"
found="$scratch/found.txt"
: > "$found"
root_index=0
while IFS= read -r root; do
    [[ -n "$root" ]] || continue
    root_index=$((root_index + 1))
    echo "➤ Looking in ${root##*/}"
    if [[ $SECONDS -ge $deadline ]]; then
        echo "! ${root##*/} was not read: out of time"
        continue
    fi
    out="$scratch/scan-$root_index.txt"
    if ! scan_purge_targets "$root" "$out"; then
        echo "! ${root##*/} was only partly read"
        continue
    fi
    while IFS= read -r artifact; do
        [[ -n "$artifact" ]] || continue
        printf '%s\037%s\0' "$artifact" "$out.verified" >> "$found"
    done < "$out"
done <<< "$roots"

plan_tmp="$plan_out.tmp.$$"
meta_tmp="$plan_out.meta.tmp.$$"
: > "$plan_tmp"
: > "$meta_tmp"
now="$(get_epoch_seconds)"
count=0
seen=$'\037'
while IFS= read -r -d '' record; do
    artifact="${record%$'\037'*}"
    verified_file="${record##*$'\037'}"
    [[ -n "$artifact" ]] || continue
    artifact="${artifact%/}"
    [[ "$artifact" != *$'\n'* && ! "$artifact" =~ [[:cntrl:]] ]] || continue
    [[ -d "$artifact" && ! -L "$artifact" ]] || continue
    mc_in_worktree "$artifact" && continue
    mc_artifact_name_ok "$artifact" || continue
    mac_cleaner_never_delete_path "$artifact" && continue
    # The same folder can arrive twice (a named root inside an automatic one); list it once.
    [[ "$seen" == *$'\037'"$artifact"$'\037'* ]] && continue
    seen+="$artifact"$'\037'

    mc_project_state "$artifact"
    state="$MC_STATE"
    verified=false
    grep -qxF -- "$artifact" "$verified_file" 2> /dev/null && verified=true
    if [[ "$state" == "old" && "$verified" != "true" ]]; then
        state=unverified
    fi

    kb="$(mc_dir_size_kb "$artifact" "$deadline")"
    size_known=true
    if [[ ! "$kb" =~ ^[0-9]+$ ]]; then
        kb=0
        size_known=false
    fi

    tick=no
    if [[ "$state" == "old" && "$size_known" == "true" ]] && mc_tick_suggestion "$artifact"; then
        tick=yes
    fi

    printf '%s\0%s\0%s\0%s\0%s\0%s\0' "Project folders" "$artifact" "$kb" 1 "$size_known" "" >> "$plan_tmp"
    printf '%s\0%s\0%s\0%s\0%s\0' "$artifact" "$MC_MTIME" "$state" "$MC_PROJECT" "$tick" >> "$meta_tmp"
    count=$((count + 1))
done < <(LC_ALL=C sort -zu "$found")

mv -f "$meta_tmp" "$plan_out.meta" && mv -f "$plan_tmp" "$plan_out" || exit 1
echo "Found $count build folders (now $now)."
exit 0
