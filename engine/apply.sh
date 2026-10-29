#!/bin/bash
# Captain Levi: delete exactly what the user ticked, and nothing else.
#
# bin/clean.sh only ever looks and writes a plan (--plan-out). The app shows that plan, the user ticks
# items and clicks Delete, and the app runs this script with the plan and the ticked paths. Each
# ticked path must be in the plan, inside the jail when one is given, and pass Mole's own guard
# (validate_path_for_deletion, which includes the user's never-delete list) before safe_remove deletes
# it. With --trash, installer files are moved to the Trash instead. Never uses admin rights, never
# runs AppleScript, never talks to the network.
#
# Usage: apply.sh --plan FILE --approved FILE [--log FILE] [--jail DIR] [--dry-run] [--trash]
#                 [--projects [--allow-recent FILE] [--root DIR]...]
#                 [--uninstall]
#   --plan      NUL-separated records from clean.sh --plan-out (6 fields each, the path second)
#   --approved  NUL-separated paths the user ticked
#   --log       history file: one tab-separated line per item (time, result, KB, path, reason)
#   --jail      refuse anything outside this folder (the tests use it)
#   --dry-run   check everything and report, delete nothing
#   --trash     move installer files (.dmg .pkg .mpkg .iso .xip .zip) from Downloads or Desktop to the Trash
#   --uninstall move eligible, tied app files to the Trash after checking the app again
#   --projects  delete "Project folders" items (old build folders such as node_modules) from a plan written by
#               bin/projects.sh. Each is checked again first (engine/projects_lib.sh): still a build folder inside
#               a project folder, nothing tracked or made by hand, not in an agent worktree, no program running in
#               the project, not changed in the last 7 days. Without --projects such an item is never deleted.
#   --allow-recent FILE  with --projects: NUL-separated paths the user ticked on purpose although they are "in use
#               lately". Only paths that are also approved count. A running program is never overridden.
#   --root DIR  with --projects: one more folder the user named for the scan (inside the user's home folder); repeatable
# Output: one tab-separated line per ticked path: result, KB, path, reason. Results are deleted,
# would-delete, trashed, would-trash and skipped.

set -uo pipefail

if [[ "$EUID" -eq 0 ]]; then
    echo "Run without sudo: Captain Levi never uses admin rights." >&2
    exit 2
fi

ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

plan_file=""
approved_file=""
log_file=""
jail=""
dry_run=false
trash_mode=false
projects_mode=false
uninstall_mode=false
allow_recent_file=""
extra_roots=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan) plan_file="${2:-}"; shift ;;
        --approved) approved_file="${2:-}"; shift ;;
        --log) log_file="${2:-}"; shift ;;
        --jail) jail="${2:-}"; shift ;;
        --dry-run) dry_run=true ;;
        --trash) trash_mode=true ;;
        --projects) projects_mode=true ;;
        --uninstall) uninstall_mode=true ;;
        --allow-recent) allow_recent_file="${2:-}"; shift ;;
        --root) extra_roots+=("${2:-}"); shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
if [[ ! -f "$plan_file" || ! -f "$approved_file" ]]; then
    echo "Usage: apply.sh --plan FILE --approved FILE [--log FILE] [--jail DIR] [--dry-run] [--trash]" >&2
    exit 2
fi
jail="${jail%/}"
if [[ "$uninstall_mode" == true && ( "$projects_mode" == true || "$trash_mode" == true ) ]]; then
    echo "--uninstall cannot be used with --projects or --trash" >&2
    exit 2
fi
if [[ "$projects_mode" == "true" && "$trash_mode" == "true" ]]; then
    echo "--projects and --trash cannot be used together" >&2
    exit 2
fi

# Settings that would bend Mole's helpers somewhere else are never inherited here.
unset MOLE_DRY_RUN MOLE_TEST_TRASH_DIR MOLE_DELETE_LOG MOLE_DELETE_MODE MOLE_RESOLVED_TMPDIR MO_TIMEOUT_BIN
unset MOLE_UNINSTALL_MODE

# shellcheck source=lib/core/common.sh
source "$ENGINE_ROOT/lib/core/common.sh"
if [[ "$uninstall_mode" == true ]]; then
    export MOLE_TEST_NO_AUTH=1
    source "$ENGINE_ROOT/engine/uninstall_lib.sh"
fi
if [[ "$projects_mode" == "true" ]]; then
    # shellcheck source=engine/projects_lib.sh
    source "$ENGINE_ROOT/engine/projects_lib.sh"
fi
set +e # common.sh turns errexit on; every item here is handled on its own

# Which ticked path is in the plan, and its size and section, is worked out in one awk pass before the loop. A
# ticked list can hold ten thousand items, and matching each against a long string in bash got slower the later
# the item sat in the plan (a 40-minute clean). Line breaks and unit separators in a path would break the pass,
# and Mole's guard refuses such paths anyway, so a plan or list that has one is refused whole.
US=$'\x1f'
for list_file in "$plan_file" "$approved_file"; do
    if [[ "$(LC_ALL=C tr -cd '\n\037' < "$list_file" | wc -c)" -ne 0 ]]; then
        echo "A path in the plan or the ticked list has a line break or a control character; nothing was changed." >&2
        exit 2
    fi
done
# Files a running program has open right now (lsof, this user's processes, no permission box). A log file or log
# folder with one inside it is never deleted: a running program's logs were lost that way, and a log that is open is
# how the user finds out why a program stopped. The answer counts only if it lists this script's own working folder
# (lsof also exits 1 on errors and can answer in part); otherwise every log-like item is held back.
open_unknown=false
open_out=""
open_rc=0
open_out="$(run_with_timeout 40 lsof -b -w -n -u "$(id -u)" -Fn 2> /dev/null)" || open_rc=$?
self_cwd="$(/bin/pwd -P)"
# (A here-string, not a pipe: under pipefail a pipe into grep -q fails with a broken pipe on a big answer.)
if [[ $open_rc -ne 0 && $open_rc -ne 1 ]] || ! grep -qxF "n$self_cwd" <<< "$open_out"; then
    open_unknown=true
    open_out=""
fi

# Whether an item is a log (or a folder of logs), by where it lives or what it is called.
log_like() {
    local had_nocasematch=false verdict=1
    shopt -q nocasematch && had_nocasematch=true
    shopt -s nocasematch
    case "$1" in
        "$HOME/Library/Logs/"* | */logs | */logs/* | */log | */log/* | *.log | *.log.[0-9]* | *.out | *.err) verdict=0 ;;
    esac
    [[ "$had_nocasematch" == "true" ]] || shopt -u nocasematch
    return "$verdict"
}

join_plan() {
    if [[ ! -s "$plan_file" ]]; then
        LC_ALL=C tr '\0' '\n' < "$approved_file" | LC_ALL=C awk '{ printf "0\0370\037\0370\n" }'
        return
    fi
    # Three inputs: the plan (six lines per record), the open files (a first line that is ignored, then "n/path"
    # lines; each open file also marks every folder above it, in lower case because the Mac's disk ignores case),
    # the ticked paths.
    LC_ALL=C awk '
        FNR == 1 { fileno++ }
        fileno == 1 {
            k = (FNR - 1) % 6
            if (k == 0) section = $0
            else if (k == 1) path = $0
            else if (k == 2) size = ($0 == "" ? "0" : $0)
            else if (k == 5 && !(path in kb)) { kb[path] = size; sec[path] = section } # only a whole record counts
            next
        }
        fileno == 2 {
            if (substr($0, 1, 2) == "n/") {
                p = tolower(substr($0, 2))
                while (length(p) > 1) { open[p] = 1; sub(/\/[^\/]*$/, "", p) }
            }
            next
        }
        {
            o = (tolower($0) in open) ? "1" : "0"
            if ($0 in kb) printf "1\037%s\037%s\037%s\n", kb[$0], sec[$0], o; else printf "0\0370\037\037%s\n", o
        }
    ' <(LC_ALL=C tr '\0' '\n' < "$plan_file") <(printf 'x\n%s\n' "$open_out") <(LC_ALL=C tr '\0' '\n' < "$approved_file")
}
plan_kb_found=0
plan_section_found=""
plan_found=0
plan_open=0
# Reads the next joined line (one per ticked path, in order): sets plan_found, plan_kb_found, plan_section_found,
# plan_open (1 when a running program has the path, or a file inside it, open).
next_plan_line() {
    local line
    IFS= read -r -u 3 line || line=$'0\0370\037\0370'
    plan_found="${line%%"$US"*}"
    line="${line#*"$US"}"
    plan_kb_found="${line%%"$US"*}"
    line="${line#*"$US"}"
    plan_section_found="${line%%"$US"*}"
    plan_open="${line#*"$US"}"
}

# Projects mode: the paths the user ticked on purpose although they are in use lately, and today's project roots.
allow_paths="$US"
project_roots=""
if [[ "$projects_mode" == "true" ]]; then
    if [[ -n "$allow_recent_file" && -f "$allow_recent_file" ]]; then
        while IFS= read -r -d '' allowed; do
            allow_paths+="$allowed$US"
        done < "$allow_recent_file"
    fi
    project_roots="$(mc_projects_roots "${extra_roots[@]+"${extra_roots[@]}"}")"
fi

report() { # result kb path reason
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}"
    if [[ -n "$log_file" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1" "$2" "$3" "${4:-}" >> "$log_file"
    fi
}

reason_for_rc() {
    case "$1" in
        "$MOLE_ERR_SIP_PROTECTED") echo "protected by macOS" ;;
        "$MOLE_ERR_AUTH_FAILED") echo "needs admin rights" ;;
        "$MOLE_ERR_READONLY_FS") echo "read-only disk" ;;
        "$MOLE_ERR_PROTECTED_PATH") echo "protected" ;;
        "$MOLE_ERR_PRIVACY_DENIED") echo "macOS privacy settings block it" ;;
        "$MOLE_ERR_OWNER_UNVERIFIED") echo "its app may be running" ;;
        *) echo "could not be removed (code $1)" ;;
    esac
}

is_installer_file() {
    local path="$1" rel
    [[ -f "$path" && ! -L "$path" && -O "$path" ]] || return 1
    case "$path" in
        "$HOME/Downloads/"* | "$HOME/Desktop/"*) ;;
        *) return 1 ;;
    esac
    rel="${path#"$HOME"/}"
    rel="${rel#*/}"
    [[ "$rel" != */*/* ]] || return 1 # at most one folder deep
    case "$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')" in
        dmg | pkg | mpkg | iso | xip | zip) return 0 ;;
    esac
    return 1
}

move_to_trash() {
    local path="$1" name dest n=1
    name="$(basename "$path")"
    dest="$HOME/.Trash/$name"
    while [[ -e "$dest" || -L "$dest" ]]; do
        dest="$HOME/.Trash/${name%.*} $n.${name##*.}"
        n=$((n + 1))
    done
    mkdir -p "$HOME/.Trash" && mv -n "$path" "$dest" && [[ ! -e "$path" ]]
}

# Check the one planned app before visiting ANY approved item, even if its record is last.
if [[ "$uninstall_mode" == true ]]; then
    app_count=0
    planned_app=""
    while IFS= read -r -d '' sec && IFS= read -r -d '' item &&
        IFS= read -r -d '' size && IFS= read -r -d '' count &&
        IFS= read -r -d '' known && IFS= read -r -d '' ancestor; do
        if [[ "$sec" == 'The app' ]]; then
            app_count=$((app_count + 1)); planned_app="$item"
        fi
    done < "$plan_file"
    MC_REFUSAL="app identity is unavailable or protected"
    uninstall_ready=false
    mc_u_state || exit 2
    identity_ready=false
    if [[ "$app_count" == 1 && -d "$planned_app" ]]; then
        mc_u_identity "$planned_app" && identity_ready=true
    elif [[ "$app_count" == 1 ]] && mc_u_load "$planned_app" && mc_u_allowed && [[ ! -e "$MC_APP" ]]; then
        identity_ready=true
    elif [[ "$app_count" == 0 ]] && mc_u_plan_identity && [[ ! -e "$MC_APP" ]]; then
        planned_app="$MC_APP"; identity_ready=true
    fi
    [[ "$identity_ready" != true ]] || MC_REFUSAL='protected or outside uninstall roots'
    if [[ "$identity_ready" == true ]] && mc_u_root "$MC_APP" && mc_u_running; then
        MC_APPS_ROOTS=()
        while IFS= read -r app_root; do MC_APPS_ROOTS+=("$app_root"); done < <(mc_u_apps_roots)
        mc_u_discover
        if [[ -z "$MC_REQUIRED_ERRORS" ]]; then uninstall_ready=true; else MC_REFUSAL="$MC_REQUIRED_ERRORS"; fi
        # Save only observations re-established by ID discovery, never plan claims.
        state_token=$(printf '%s' "$MC_APP" | cksum | awk '{print $1}')
        if [[ "$dry_run" != true && "$uninstall_ready" == true && -f "$MC_STATE/$state_token.state" && ! -L "$MC_STATE/$state_token.plan" ]]; then
            state_pending=$(mktemp "$MC_STATE/observations.XXXXXX") || exit 2
            while IFS= read -r observed; do
                [[ -n "$observed" ]] || continue
                printf '%s\0%s\0%s\0%s\0%s\0%s\0' "$(mc_u_section "$observed")" "$observed" 0 1 false '' >> "$state_pending" || exit 2
            done <<< "$(printf '%s\n%s\n' "$MC_TIED" "$MC_OBSERVED")"
            if [[ -s "$state_pending" ]]; then
                mv "$state_pending" "$MC_STATE/$state_token.plan" || exit 2
            else
                rm -f "$state_pending"
            fi
        fi
    fi
fi

while IFS= read -r -d '' path; do
    next_plan_line # always, so the joined lines stay in step with the ticked paths
    [[ -n "$path" ]] || continue
    # Control characters could forge a match between plan entries; Mole's guard refuses them anyway.
    if [[ "$path" =~ [[:cntrl:]] ]]; then
        report skipped 0 "${path//[[:cntrl:]]/?}" "unusual characters in the path"
        continue
    fi
    if [[ "$plan_found" != "1" ]]; then
        report skipped 0 "$path" "not in the plan"
        continue
    fi
    kb="$plan_kb_found"
    section="$plan_section_found"
    if [[ -n "$jail" && "$path" != "$jail/"* ]]; then
        report skipped "$kb" "$path" "outside the allowed folder"
        continue
    fi
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        report skipped "$kb" "$path" "already gone"
        continue
    fi
    if log_like "$path"; then
        if [[ "$open_unknown" == "true" ]]; then
            report skipped "$kb" "$path" "could not tell whether a running program is using it"
            continue
        elif [[ "$plan_open" == "1" ]]; then
            report skipped "$kb" "$path" "a running program has it open"
            continue
        fi
    fi

    if [[ "$section" == "Project folders" && "$projects_mode" != "true" ]]; then
        report skipped "$kb" "$path" "Project folders items are deleted only from the Project folders pane"
        continue
    fi
    if [[ "$uninstall_mode" != true ]]; then
        case "$section" in
            'The app' | 'Settings and saved state' | 'Caches and logs' | 'Its data' | 'Helpers and launch agents' | 'Not tied to this app')
                report skipped "$kb" "$path" "uninstall items are moved to the Trash only from the Uninstall pane"
                continue;;
        esac
    fi
    if [[ "$projects_mode" == "true" ]]; then
        if [[ "$section" != "Project folders" ]]; then
            report skipped "$kb" "$path" "not a Project folders item"
            continue
        fi
        allow_this=false
        [[ "$allow_paths" == *"$US$path$US"* ]] && allow_this=true
        if ! mc_project_refusal "$path" "$allow_this" "$project_roots"; then
            report skipped "$kb" "$path" "$MC_REFUSAL"
            continue
        fi
    fi

    if [[ "$uninstall_mode" == true ]]; then
        if [[ "$uninstall_ready" != true ]]; then
            report skipped "$kb" "$path" "$MC_REFUSAL"
        elif [[ "$path" == *.app && "$path" != "$planned_app" ]]; then
            report skipped "$kb" "$path" "not the planned app bundle"
        elif ! mc_u_root "$path"; then
            report skipped "$kb" "$path" "$MC_ROOT_REFUSAL"
        elif grep -qxF "$path" <<< "$MC_ADMIN"; then
            report skipped "$kb" "$path" "system discovery is report-only"
        elif [[ "$path" != "$MC_APP" ]] && { [[ "$section" == 'Not tied to this app' ]] || ! grep -qxF "$path" <<< "$MC_TIED"; }; then
            report skipped "$kb" "$path" "not tied exclusively to this app"
        elif [[ -n "$jail" && "$(cd -P "${path%/*}" && pwd -P)/${path##*/}" != "$jail/"* ]]; then
            report skipped "$kb" "$path" "outside the allowed folder"
        elif [[ -L "$HOME/.Trash" ]]; then
            report skipped "$kb" "$path" "Trash is a link"
        elif [[ "$dry_run" == true ]]; then
            report would-trash "$kb" "$path"
        elif move_to_trash "$path"; then
            report trashed "$kb" "$path"
        else
            report skipped "$kb" "$path" "could not be moved to the Trash"
        fi
        continue
    fi

    if [[ "$trash_mode" == "true" ]]; then
        if ! is_installer_file "$path"; then
            report skipped "$kb" "$path" "not an installer file in Downloads or Desktop"
        elif [[ "$dry_run" == "true" ]]; then
            report would-trash "$kb" "$path"
        elif move_to_trash "$path"; then
            report trashed "$kb" "$path"
        else
            report skipped "$kb" "$path" "could not be moved to the Trash"
        fi
        continue
    fi

    if ! validate_path_for_deletion "$path" > /dev/null 2>&1; then
        report skipped "$kb" "$path" "protected"
        continue
    fi
    if [[ "$dry_run" == "true" ]]; then
        report would-delete "$kb" "$path"
        continue
    fi
    if [[ "$projects_mode" == "true" ]]; then
        # Held to the folder that was checked: a parent swapped for a link since then is refused.
        safe_remove "$path" true "" "" "$MC_SNAP_PARENT" "$MC_SNAP_PARENT_ID" "$MC_SNAP_TARGET_ID" > /dev/null 2>&1
    else
        safe_remove "$path" true > /dev/null 2>&1
    fi
    rc=$?
    if [[ $rc -eq 0 && ! -e "$path" && ! -L "$path" ]]; then
        report deleted "$kb" "$path"
    elif [[ $rc -eq 0 ]]; then
        report skipped "$kb" "$path" "left in place by a safety check"
    else
        report skipped "$kb" "$path" "$(reason_for_rc "$rc")"
    fi
done < "$approved_file" 3< <(join_plan)
exit 0
