#!/bin/bash
# Captain Levi: what the Project folders scan (bin/projects.sh) and engine/apply.sh --projects share.
# Sourced, never run. It loads Mole's own purge rules (lib/clean/project.sh): the build-folder names,
# the nested-folder filter, and the check that a folder holds nothing tracked or hand-made.
#
# MAC_CLEANER_PROJECTS=1 must be set before project.sh is sourced: without it, project.sh runs Mole's
# own discovery on load, which reads Documents, Desktop and Downloads (macOS would ask the user) and writes
# ~/.config/mole/purge_paths. Here the roots come from mc_projects_roots instead.

if [[ -n "${MAC_CLEANER_PROJECTS_LIB_LOADED:-}" ]]; then
    return 0
fi
MAC_CLEANER_PROJECTS_LIB_LOADED=1
export MAC_CLEANER_PROJECTS=1

_MC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if ! command -v ensure_user_dir > /dev/null 2>&1; then
    # shellcheck source=lib/core/common.sh
    source "$_MC_LIB_DIR/lib/core/common.sh"
fi
# shellcheck source=lib/clean/project.sh
source "$_MC_LIB_DIR/lib/clean/project.sh"

# Folders in the home folder that are never looked into on their own (macOS asks before an app reads
# some of them, and the never-delete list covers all of them).
mc_projects_skip_name() {
    local name="$1" had_nocasematch=false verdict=1
    shopt -q nocasematch && had_nocasematch=true
    shopt -s nocasematch
    case "$name" in
        .* | Library | Applications | Movies | Music | Pictures | Public | Documents | Desktop | Downloads | \
            captain-levi | "Captain Levi" | node_modules | \
            "Creative Cloud Files"* | *"Google Drive"* | Dropbox* | OneDrive* | "Box Sync"* | iCloud*)
            verdict=0
            ;;
    esac
    [[ "$had_nocasematch" == "true" ]] || shopt -u nocasematch
    return "$verdict"
}

# A folder the user named with --root: printed (as its physical path) only when it is strictly inside the user's home
# folder, reached without crossing a link or a "." / ".." step, not Library or the Trash, not on the
# never-delete list, and not one of the folders macOS asks about (Documents, Desktop, Downloads, ...).
# Dot folders other than the protected ones are allowed: that is the point of naming one.
mc_projects_named_root() {
    local given="${1%/}" rel first physical expected lexical_home="${HOME%/}"
    local had_nocasematch=false verdict=1
    [[ "$given" == "$lexical_home"/* ]] || return 1
    case "$given/" in
        */./* | */../* | *//*) return 1 ;;
    esac
    [[ -d "$given" ]] || return 1
    rel="${given#"$lexical_home"/}"
    first="${rel%%/*}"
    shopt -q nocasematch && had_nocasematch=true
    shopt -s nocasematch
    case "$first" in
        Library | .Trash) verdict=2 ;;
    esac
    [[ "$had_nocasematch" == "true" ]] || shopt -u nocasematch
    [[ $verdict -eq 2 ]] && return 1
    case "$first" in
        .*) ;;
        *) mc_projects_skip_name "$first" && return 1 ;;
    esac
    # A named root inside a build folder would list the packages' own nested build folders.
    local part target
    while IFS= read -r part; do
        for target in "${MOLE_PURGE_TARGETS[@]}"; do
            [[ "$part" == "$target" ]] && return 1
        done
    done <<< "${rel//\//$'\n'}"
    had_nocasematch=false
    verdict=1
    physical=$(cd "$given" 2> /dev/null && /bin/pwd -P) || return 1
    expected="$MOLE_PURGE_PHYSICAL_HOME/$rel"
    shopt -q nocasematch && had_nocasematch=true
    shopt -s nocasematch
    [[ "$physical" == "$expected" ]] && verdict=0
    [[ "$had_nocasematch" == "true" ]] || shopt -u nocasematch
    [[ $verdict -eq 0 ]] || return 1
    mac_cleaner_never_delete_path "$given" && return 1
    mac_cleaner_never_delete_path "$physical" && return 1
    printf '%s\n' "$physical"
}

# The folders to look in: every folder in the home folder that holds projects (skipping the names above
# and every link, which could lead to cloud storage or a network drive), plus the folders named as
# arguments that pass mc_projects_named_root. One physical path per line.
mc_projects_roots() {
    local dir name extra
    {
        for dir in "$HOME"/*/; do
            dir="${dir%/}"
            name="${dir##*/}"
            [[ -L "$dir" ]] && continue
            [[ "$dir" =~ [[:cntrl:]] ]] && continue
            mc_projects_skip_name "$name" && continue
            [[ -d "$dir" ]] || continue
            if is_project_container "$dir" 2; then
                mole_purge_resolve_path_case "$dir"
            fi
        done
        for extra in "$@"; do
            mc_projects_named_root "$extra"
        done
    } | LC_ALL=C sort -u
}

# Paths of the folders the user's programs are running in (lsof, current working folders only). Reading
# this shows no macOS permission box. MC_CWD_OK is false when lsof could not answer: lsof also exits 1 on
# errors and can answer in part, so the answer counts only if it lists this script's own working folder.
MC_CWD_OK=false
MC_CWDS=()
_MC_CWD_LOADED_AT=-100
mc_projects_load_cwds() {
    if [[ $((SECONDS - _MC_CWD_LOADED_AT)) -lt 5 && "$MC_CWD_OK" == "true" ]]; then
        return 0
    fi
    local out rc=0 line self_cwd own=false
    MC_CWDS=()
    MC_CWD_OK=false
    out=$(run_with_timeout 20 lsof -b -w -n -a -u "$(id -u)" -d cwd -Fn 2> /dev/null) || rc=$?
    if [[ $rc -ne 0 && $rc -ne 1 ]]; then
        return 1
    fi
    self_cwd="$(/bin/pwd -P)"
    while IFS= read -r line; do
        if [[ "$line" == n/* ]]; then
            MC_CWDS+=("${line#n}")
            [[ "${line#n}" == "$self_cwd" ]] && own=true
        fi
    done <<< "$out"
    if [[ "$own" != "true" ]]; then
        MC_CWDS=()
        return 1
    fi
    MC_CWD_OK=true
    _MC_CWD_LOADED_AT=$SECONDS
}

# Whether a program runs in this folder or below it.
mc_cwd_inside() {
    local project="${1%/}" cwd
    for cwd in "${MC_CWDS[@]+"${MC_CWDS[@]}"}"; do
        if [[ "$cwd" == "$project" || "$cwd" == "$project"/* ]]; then
            return 0
        fi
    done
    return 1
}

# Whether the project's own files (not its build folders), at any depth, changed in the last 7 days, or the git
# index was written lately. A node_modules keeps old file dates after an install, so its own date proves
# nothing. Returns 0 when recent, 1 when not, 2 when it could not be told.
mc_project_files_recent() {
    local project="$1" target hit rc=0 mtime
    local -a prune=(-name .git -o -name .claude -o -name .codex)
    for target in "${MOLE_PURGE_TARGETS[@]}"; do
        prune+=(-o -name "$target")
    done
    hit=$(run_with_timeout 20 find "$project" -type d \( "${prune[@]}" \) -prune -o \
        -type f -mtime -7 -print -quit 2> /dev/null) || rc=$?
    [[ $rc -eq 0 ]] || return 2
    [[ -z "$hit" ]] || return 0
    if [[ -f "$project/.git/index" ]]; then
        mtime=$(get_file_mtime "$project/.git/index" 2> /dev/null || true)
        [[ "$mtime" =~ ^[0-9]+$ ]] || return 2
        [[ $(($(get_epoch_seconds) - mtime)) -lt $((7 * 86400)) ]] && return 0
    fi
    return 1
}

_MC_FILES_PROJECT=""
_MC_FILES_RC=0
_MC_FILES_AT=0
# Sets MC_PROJECT (the project folder), MC_MTIME (the build folder's last change) and MC_STATE:
#   running     a program runs in the project
#   recent      the build folder or the project's files changed in the last 7 days
#   unverified  something could not be told (lsof, the date walk, the project walk): never overridable
#   old         none of the above
mc_project_state() {
    local artifact="${1%/}" now activity_rc=0 files_rc=0
    now="$(get_epoch_seconds)"
    MC_PROJECT=$(find_purge_project_root_for_artifact "$artifact") || MC_PROJECT="${artifact%/*}"
    MC_MTIME=$(get_file_mtime "$artifact" 2> /dev/null || true)
    [[ "$MC_MTIME" =~ ^[0-9]+$ ]] || MC_MTIME=0
    MC_STATE=old
    mc_projects_load_cwds || true
    if [[ "$MC_CWD_OK" != "true" ]]; then
        MC_STATE=unverified
    elif mc_cwd_inside "$MC_PROJECT"; then
        MC_STATE=running
    else
        classify_purge_activity "$artifact" "$now" || activity_rc=$?
        # One walk per project: a project often has several build folders, listed one after another.
        # (Only the scan reuses it: before a delete every folder is walked afresh.)
        if [[ "${MC_CACHE_FILES:-}" == "true" && "$_MC_FILES_PROJECT" == "$MC_PROJECT" && $((SECONDS - _MC_FILES_AT)) -lt 30 ]]; then
            files_rc=$_MC_FILES_RC
        else
            mc_project_files_recent "$MC_PROJECT" || files_rc=$?
            _MC_FILES_PROJECT="$MC_PROJECT"
            _MC_FILES_RC=$files_rc
            _MC_FILES_AT=$SECONDS
        fi
        if [[ $activity_rc -ne 0 || "$_PURGE_ACTIVITY_STATE" == "uncertain" || $files_rc -eq 2 ]]; then
            MC_STATE=unverified
        elif [[ "$_PURGE_ACTIVITY_STATE" == "recent" || $files_rc -eq 0 ]]; then
            MC_STATE=recent
        fi
    fi
}

# Size of a folder in KB (du, physical, links not followed), within the shared deadline. Prints a number,
# or TIMEOUT or ERROR when the size could not be read in time or in full.
mc_dir_size_kb() {
    local path="$1" deadline="${2:-}" limit="${MO_PURGE_SIZE_TIMEOUT_SEC:-15}" out rc=0
    [[ "$limit" =~ ^[1-9][0-9]*$ ]] || limit=15
    if [[ "$deadline" =~ ^[0-9]+$ ]]; then
        limit=$(_mole_timeout_with_deadline "$limit" "$deadline") || {
            echo TIMEOUT
            return 0
        }
    fi
    out=$(run_with_timeout "$limit" du -skP "$path" 2> /dev/null) || rc=$?
    if mole_rc_timeout "$rc"; then
        echo TIMEOUT
    elif [[ $rc -ne 0 ]]; then
        echo ERROR
    else
        out="${out%%[[:space:]]*}"
        [[ "$out" =~ ^[0-9]+$ ]] && echo "$out" || echo ERROR
    fi
}

# Whether the name is one of Mole's build-folder names, or the folder carries a valid CACHEDIR.TAG.
mc_artifact_name_ok() {
    local path="${1%/}" base target
    base="${path##*/}"
    for target in "${MOLE_PURGE_TARGETS[@]}"; do
        [[ "$base" == "$target" ]] && return 0
    done
    mole_dir_has_cachedir_tag "$path"
}

mc_in_worktree() {
    case "$1" in
        */.claude/worktrees/* | */.codex/worktrees/*) return 0 ;;
    esac
    return 1
}

# Whether the user's rules start this folder ticked: old, a specific name whose manifest sits beside it.
# Generic names (build, dist, out, coverage, bin, vendor, ...) can hold files the user made, so they start unticked.
mc_tick_suggestion() {
    local path="${1%/}" base parent
    base="${path##*/}"
    parent="${path%/*}"
    case "$base" in
        node_modules | .next | .nuxt | .svelte-kit | .astro | .turbo | .parcel-cache | .angular)
            [[ -f "$parent/package.json" ]]
            ;;
        __pycache__ | .pytest_cache | .mypy_cache | .ruff_cache | .tox | .nox) return 0 ;;
        .venv | venv) [[ -f "$path/pyvenv.cfg" ]] ;;
        target) [[ -f "$parent/Cargo.toml" ]] ;;
        .build) [[ -f "$parent/Package.swift" ]] ;;
        Pods) [[ -f "$parent/Podfile" ]] ;;
        *) return 1 ;;
    esac
}

# The check before anything is deleted, run again at delete time because a plan can be hours old.
# Args: path, allow_recent (true when the user ticked this "in use lately" row on purpose), roots (lines).
# Returns 1 and sets MC_REFUSAL to refuse. Returns 0 when the folder may go, with the folder's identity
# (physical parent, parent id, target id) in MC_SNAP_* so safe_remove can hold the delete to the folder that
# was checked: a parent swapped for a link in between is refused there.
MC_REFUSAL=""
MC_SNAP_PARENT=""
MC_SNAP_PARENT_ID=""
MC_SNAP_TARGET_ID=""
mc_project_refusal() {
    local path="${1%/}" allow_recent="$2" roots="$3" root under=false rc=0
    MC_REFUSAL=""
    if [[ -L "$path" || ! -d "$path" ]]; then
        MC_REFUSAL="not a plain folder"
        return 1
    fi
    if ! _mole_snapshot_path_identity "$path"; then
        MC_REFUSAL="could not be identified"
        return 1
    fi
    MC_SNAP_PARENT="$_MOLE_PATH_SNAPSHOT_PARENT"
    MC_SNAP_PARENT_ID="$_MOLE_PATH_SNAPSHOT_PARENT_ID"
    MC_SNAP_TARGET_ID="$_MOLE_PATH_SNAPSHOT_TARGET_ID"
    if mc_in_worktree "$path" || mc_in_worktree "$MC_SNAP_PARENT/${path##*/}"; then
        MC_REFUSAL="inside an agent worktree"
        return 1
    fi
    if ! mc_artifact_name_ok "$path"; then
        MC_REFUSAL="not a build folder"
        return 1
    fi
    if mac_cleaner_never_delete_path "$path" || mac_cleaner_never_delete_path "$MC_SNAP_PARENT/${path##*/}"; then
        MC_REFUSAL="protected"
        return 1
    fi
    while IFS= read -r root; do
        [[ -n "$root" ]] || continue
        if is_safe_project_artifact "$path" "$root"; then
            under=true
            break
        fi
    done <<< "$roots"
    if [[ "$under" != "true" ]]; then
        MC_REFUSAL="not inside a project folder"
        return 1
    fi
    is_protected_purge_artifact "$path" || rc=$?
    if [[ $rc -eq 0 ]]; then
        if [[ "$PURGE_PROTECTION_UNVERIFIED" == "true" ]]; then
            MC_REFUSAL="could not check whether it holds files you made"
        else
            MC_REFUSAL="holds files tracked by git or made by you"
        fi
        return 1
    fi
    mc_project_state "$path"
    case "$MC_STATE" in
        running)
            MC_REFUSAL="a program is running in the project"
            return 1
            ;;
        unverified)
            MC_REFUSAL="could not tell whether it is in use"
            return 1
            ;;
        recent)
            if [[ "$allow_recent" != "true" ]]; then
                MC_REFUSAL="in use lately"
                return 1
            fi
            ;;
    esac
    return 0
}
