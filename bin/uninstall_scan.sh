#!/bin/bash
# Captain Levi: preview an uninstall and look again after removal. Never removes files.
set -uo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
mode=""; app=""; plan_out=""; MC_APPS_ROOTS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --list) [[ -z "$mode" ]] || exit 2; mode=list;;
        --app) [[ -z "$mode" ]] || exit 2; mode=plan; app="${2:-}"; shift;;
        --check) [[ -z "$mode" ]] || exit 2; mode=check; app="${2:-}"; shift;;
        --plan-out) plan_out="${2:-}"; shift;;
        --apps-root) [[ "${MOLE_TEST_NO_AUTH:-}" == 1 ]] || { echo '--apps-root is test-only' >&2; exit 2; }; MC_APPS_ROOTS+=("${2:-}"); shift;;
        *) echo "Unknown option: $1" >&2; exit 2;;
    esac
    shift
done
[[ -n "$mode" ]] || exit 2
umask 077
source "$ENGINE_ROOT/engine/uninstall_lib.sh"
[[ ${#MC_APPS_ROOTS[@]} -gt 0 ]] || while IFS= read -r root; do MC_APPS_ROOTS+=("$root"); done < <(mc_u_apps_roots)
if [[ "$mode" == list ]]; then
    first=true; printf '['
    for root in "${MC_APPS_ROOTS[@]}"; do
        [[ -d "$root" ]] || continue
        for candidate in "$root"/*.app; do
            mc_u_identity "$candidate" || continue
            [[ "$first" == true ]] || printf ','
            first=false; mc_u_app_json
        done
    done
    printf ']\n'; exit 0
fi
mc_u_state || exit 2
MC_PREVIOUS=""
if [[ "$mode" == check ]]; then
    mc_u_load "$app" || { echo 'No saved app identity; scan the app first' >&2; exit 2; }
else
    [[ "$plan_out" == /* ]] || { echo '--plan-out needs an absolute path' >&2; exit 2; }
    if [[ ! -e "$app" ]]; then
        mc_u_load "$app" && mc_u_allowed || { echo 'No saved app identity' >&2; exit 2; }
    else
        mc_u_identity "$app" || { echo "${MC_REFUSAL:-App identity is unavailable or protected}" >&2; exit 2; }
    fi
fi
mc_u_discover
if [[ "$mode" == check ]]; then
    left=$(printf '%s\n%s\n' "$MC_TIED" "$MC_ADMIN")
    while IFS= read -r p; do
        [[ -n "$p" && ( -e "$p" || -L "$p" ) ]] && left="$left"$'\n'"$p"
    done <<< "$MC_PREVIOUS"
    [[ ! -e "$MC_APP" ]] || left="$left"$'\n'"$MC_APP"
    # Keep protected tied observations from the current plan visible as well.
    if [[ -f "$MC_STATE/$MC_TOKEN.plan" && ! -L "$MC_STATE/$MC_TOKEN.plan" ]]; then
        while IFS= read -r -d '' sec && IFS= read -r -d '' p &&
            IFS= read -r -d '' kb && IFS= read -r -d '' count &&
            IFS= read -r -d '' known && IFS= read -r -d '' ancestor; do
            [[ ! "$p" =~ [[:cntrl:]] && "$sec" != 'Not tied to this app' && "$p" == "$HOME/"* && ( -e "$p" || -L "$p" ) ]] && left="$left"$'\n'"$p"
        done < "$MC_STATE/$MC_TOKEN.plan"
    fi
    left=$(printf '%s\n' "$left" | sed '/^$/d' | LC_ALL=C sort -u)
    printf '{"left":'; mc_u_array "$left"
    printf ',"nameOnly":'; mc_u_array "$MC_NAMES"
else
    : > "$plan_out" || exit 1
    tied=0; names=0; seen=$'\037'
    for kind in app tied names; do
        case "$kind" in app) paths=""; [[ ! -e "$MC_APP" ]] || paths="$MC_APP";; tied) paths="$MC_TIED";; names) paths="$MC_NAMES";; esac
        while IFS= read -r p; do
            [[ -n "$p" && "$p" == /* && ! "$p" =~ [[:cntrl:]] ]] || continue
            [[ "$seen" != *$'\037'"$p"$'\037'* ]] || continue
            seen="$seen$p"$'\037'
            case "$p" in "$HOME/"* | "$MC_APP") ;; *) continue;; esac
            section=$(mc_u_section "$p")
            if [[ "$kind" == names ]]; then section='Not tied to this app'; names=$((names + 1)); else tied=$((tied + 1)); fi
            kb=""; known=true
            case "$p" in
                "$HOME/Library/Containers/"* | "$HOME/Library/Group Containers/"*) ;;
                *) kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}');;
            esac
            [[ "$kb" =~ ^[0-9]+$ ]] || { kb=0; known=false; }
            printf '%s\0%s\0%s\0%s\0%s\0%s\0' "$section" "$p" "$kb" 1 "$known" '' >> "$plan_out"
        done <<< "$paths"
    done
    mc_u_save || exit 1
    # Keep an independent observation: later editing a plan cannot change saved state.
    cp "$plan_out" "$MC_STATE/$MC_TOKEN.plan" || exit 1
    printf '{"app":'; mc_u_app_json
    printf ',"tied":%s,"nameOnly":%s,"needsAdmin":' "$tied" "$names"; mc_u_array "$MC_ADMIN"
fi
printf ',"uninspected":["login items","complete receipt inventory"],"errors":'
mc_u_array "$MC_ERRORS"
printf '}\n'
[[ -z "$MC_REQUIRED_ERRORS" ]]
