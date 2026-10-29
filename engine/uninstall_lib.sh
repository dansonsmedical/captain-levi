#!/bin/bash
# Captain Levi: read-only identity and ownership checks. apply.sh alone moves files.
unset MOLE_UNINSTALL_MODE
source "$ENGINE_ROOT/lib/core/common.sh"
set +e
mc_u_json() {
    local s="$1"
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"
    s="${s//[[:cntrl:]]/?}"
    printf '"%s"' "$s"
}
mc_u_array() {
    local p first=true
    printf '['
    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        [[ "$first" == true ]] || printf ','
        first=false; mc_u_json "$p"
    done <<< "$1"
    printf ']'
}
mc_u_key() {
    local plist
    for plist in "$1/Contents/Info.plist" "$1"/Wrapper/*.app/Info.plist; do
        [[ -f "$plist" ]] || continue
        plutil -extract "$2" raw -o - "$plist" 2>/dev/null && return 0
    done
    return 1
}
mc_u_apps_roots() {
    printf '%s\n' /Applications /Applications/Setapp /Applications/Utilities "$HOME/Applications" \
        "$HOME/Library/Application Support/Setapp/Applications" /opt/homebrew/Caskroom \
        /usr/local/Caskroom '/Library/Input Methods' "$HOME/Library/Input Methods"
}
mc_u_app_root() {
    local root
    [[ "$1" == /*.app && "$1" != *.app/* ]] || return 1
    while IFS= read -r root; do
        [[ -n "$root" && "${1%/*}" == "$root" ]] && return 0
    done < <(mc_u_apps_roots)
    return 1
}
mc_u_allowed() {
    case "$MC_ID" in com.apple.* | app.captainlevi.cleaner) return 1;; esac
    case "$MC_APP" in /System | /System/*) return 1;; esac
    if should_protect_from_uninstall "$MC_ID"; then
        MC_REFUSAL='protected app'
        return 1
    fi
    if [[ -n "$(official_uninstaller_vendor "$MC_ID" "${MC_NAME:-}" "$MC_APP")" ]]; then
        MC_REFUSAL="use the vendor's own uninstaller"
        return 1
    fi
    return 0
}
mc_u_identity() {
    MC_APP="$1"
    [[ "$MC_APP" == /*.app && -d "$MC_APP" && ! "$MC_APP" =~ [[:cntrl:]] ]] || return 1
    MC_ID=$(mc_u_key "$MC_APP" CFBundleIdentifier) || return 1
    mole_is_reverse_dns_bundle_id "$MC_ID" || return 1
    MC_NAME=$(mc_u_key "$MC_APP" CFBundleDisplayName) || MC_NAME="${MC_APP##*/}"
    MC_NAME="${MC_NAME%.app}"
    MC_VERSION=$(mc_u_key "$MC_APP" CFBundleShortVersionString) || MC_VERSION=""
    MC_EXEC=$(mc_u_key "$MC_APP" CFBundleExecutable) || return 1
    [[ -n "$MC_EXEC" && "$MC_EXEC" != */* && ! "$MC_EXEC" =~ [[:cntrl:]] && ! "$MC_NAME" =~ [[:cntrl:]] ]] || return 1
    mc_u_allowed
}
mc_u_app_json() {
    local kb
    kb=$(du -sk "$MC_APP" 2>/dev/null | awk '{print $1}')
    [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
    printf '{"name":'; mc_u_json "$MC_NAME"
    printf ',"bundleID":'; mc_u_json "$MC_ID"
    printf ',"version":'; mc_u_json "$MC_VERSION"
    printf ',"path":'; mc_u_json "$MC_APP"
    printf ',"bytes":%s,"lastUsed":null}' "$((kb * 1024))"
}
mc_u_root() {
    local p="$1" probe="$1" refusal
    MC_ROOT_REFUSAL='protected or outside uninstall roots'
    [[ "$p" == /* && "$p" != */ && "$p" != *//* && ! "$p" =~ (^|/)\.\.?(/|$) && ! "$p" =~ [[:cntrl:]] ]] || return 1
    # Refuse leaf and ancestor links, so resolved paths cannot broaden permission.
    while [[ "$probe" == /?* ]]; do
        if [[ -L "$probe" ]]; then
            if [[ "$probe" == "$p" ]]; then MC_ROOT_REFUSAL="$MC_ROOT_REFUSAL; symbolic link"
            else MC_ROOT_REFUSAL="$MC_ROOT_REFUSAL; linked ancestor"; fi
            return 1
        fi
        probe="${probe%/*}"
    done
    if [[ "$p" == "$MC_APP" ]]; then
        mc_u_app_root "$p" || return 1
    else
        case "$p" in
            "$HOME/Library/"?*/?* | "$HOME/.config/"?* | "$HOME/.cache/"?* | "$HOME/.local/share/"?*) ;;
            *) return 1;;
        esac
        [[ "$p" != *.app && "$p" != *.app/* ]] || return 1
    fi
    if mac_cleaner_never_delete_path "$p"; then
        MC_ROOT_REFUSAL="$MC_ROOT_REFUSAL; on the never-delete list"
        return 1
    fi
    if [[ "$p" != "$MC_APP" ]]; then
        refusal=$(
            _MOLE_DEFER_CONTAINER_HANDLE_PROBE=false
            _MOLE_UNINSTALL_REFUSALS_ACTIVE=1
            _MOLE_UNINSTALL_REFUSAL_PATHS=(); _MOLE_UNINSTALL_REFUSAL_REASONS=()
            validate_path_for_deletion "$p" >/dev/null 2>&1 && exit 0
            printf '%s' "${_MOLE_UNINSTALL_REFUSAL_REASONS[@]+"${_MOLE_UNINSTALL_REFUSAL_REASONS[@]}"}"
            exit 1
        ) || {
            [[ "$refusal" != *live-cache* ]] || MC_ROOT_REFUSAL="$MC_ROOT_REFUSAL; cache is in use or could not be proved closed"
            return 1
        }
    fi
    return 0
}
mc_u_running() {
    local rc=0 pattern
    pattern=$(printf '%s' "$MC_APP/" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
    pgrep -f "$pattern" >/dev/null 2>&1 || rc=$?
    [[ "$rc" == 1 ]] && return 0
    MC_REFUSAL='quit it first'
    [[ "$rc" == 0 ]] || MC_REFUSAL='could not check running apps; quit it first'
    return 1
}
# Mole normally treats unreadable roots as best effort. This preview must expose
# those failures. Scope the stricter materializer to a discovery subshell only.
mc_u_probe() (
    local optional="$1"
    shift
    # Vendor nesting is heuristic evidence, separate from required ID discovery.
    find_vendor_nested_app_paths() { return 0; }
    _mole_uninstall_materialize_find0() {
        local output="$1" budget="$MOLE_TIMEOUT_MEDIUM_PROBE_SEC" rc=0
        shift
        : > "$output" || return 1
        if [[ -n "${_MOLE_UNINSTALL_DISCOVERY_DEADLINE:-}" ]]; then
            budget=$(_mole_timeout_with_deadline "$budget" "$_MOLE_UNINSTALL_DISCOVERY_DEADLINE") || return $?
        fi
        run_with_timeout "$budget" find "$@" < /dev/null > "$output" 2>/dev/null || rc=$?
        if [[ "$rc" == 1 && "$optional" == optional ]]; then
            printf 'partial discovery (unreadable folders)\n' >> "$MC_PROBE_NOTE"
            return 0
        fi
        if [[ "$rc" != 0 ]]; then : > "$output"; return "$rc"; fi
        local observed
        while IFS= read -r -d '' observed; do
            if [[ "$observed" =~ [[:cntrl:]] ]]; then
                printf 'uninspected path: %s\n' "$(mc_u_json "$observed")" >> "$MC_PROBE_NOTE"
            fi
        done < "$output"
    }
    "$@"
)
mc_u_discover() {
    local named receipts root copy id candidates sibling=false other_ids="" inventory foreign unknown=false
    MC_TIED=""; MC_NAMES=""; MC_ADMIN=""; MC_ERRORS=""; MC_REQUIRED_ERRORS=""; MC_OBSERVED=""
    # Discovery returns lines; expose names that cannot be represented there.
    local odd base
    for base in "$HOME/Library/"{Caches,Logs,Preferences,Containers,Group\ Containers,Application\ Support,Application\ Scripts,WebKit,HTTPStorages,Saved\ Application\ State} "$HOME/.config" "$HOME/.cache" "$HOME/.local/share"; do
        [[ -d "$base" && ! -L "$base" ]] || continue
        while IFS= read -r -d '' odd; do
            [[ "$odd" =~ [[:cntrl:]] ]] || continue
            MC_ERRORS="${MC_ERRORS:+$MC_ERRORS$'\n'}uninspected path: $(mc_u_json "$odd")"
        done < <(find "$base" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
    done
    MC_PROBE_NOTE="$MC_STATE/probe.$$"
    : > "$MC_PROBE_NOTE"
    candidates=$(mc_u_probe required find_app_files "$MC_ID" "" "$MC_APP") || MC_REQUIRED_ERRORS='user discovery incomplete'
    # Exact Mail observations are for --check only, never deletion eligibility.
    # Never enumerate Mail or preserve arbitrary paths claimed by a plan.
    if [[ -n "${plan_file:-}" ]]; then
        local sec observed kb count known ancestor
        while IFS= read -r -d '' sec && IFS= read -r -d '' observed &&
            IFS= read -r -d '' kb && IFS= read -r -d '' count &&
            IFS= read -r -d '' known && IFS= read -r -d '' ancestor; do
            if [[ "$sec" != 'Not tied to this app' && "$observed" == "$HOME/Library/Mail/$MC_ID" ]]; then
                MC_OBSERVED="${MC_OBSERVED:+$MC_OBSERVED$'\n'}$observed"
            fi
        done < "$plan_file"
    fi
    named=$(mc_u_probe optional find_app_files "$MC_ID" "$MC_NAME" "$MC_APP") || MC_ERRORS="${MC_ERRORS:+$MC_ERRORS$'\n'}name discovery incomplete"
    MC_ADMIN=$(mc_u_probe optional find_app_system_files "$MC_ID" "$MC_NAME") || MC_ERRORS="${MC_ERRORS:+$MC_ERRORS$'\n'}system discovery incomplete"
    receipts=$(mc_u_probe optional find_app_receipt_files "$MC_ID") || MC_ERRORS="${MC_ERRORS:+$MC_ERRORS$'\n'}receipt discovery incomplete"
    [[ -z "$MC_REQUIRED_ERRORS" ]] || MC_ERRORS="${MC_ERRORS:+$MC_ERRORS$'\n'}$MC_REQUIRED_ERRORS"
    local note
    note=$(cat "$MC_PROBE_NOTE")
    [[ -z "$note" ]] || MC_ERRORS="${MC_ERRORS:+$MC_ERRORS$'\n'}$note"
    rm -f "$MC_PROBE_NOTE"
    MC_ADMIN=$(printf '%s\n%s\n' "$MC_ADMIN" "$receipts" | sed '/^$/d' | LC_ALL=C sort -u)
    # Empty-name discovery still includes vendor heuristics. Require an ID boundary.
    while IFS= read -r copy; do
        [[ -n "$copy" ]] || continue
        if mole_name_has_bundle_id_boundary "${copy##*/}" "$MC_ID"; then
            MC_TIED="${MC_TIED:+$MC_TIED$'\n'}$copy"
        else
            MC_NAMES="${MC_NAMES:+$MC_NAMES$'\n'}$copy"
        fi
    done <<< "$candidates"
    MC_TIED=$(printf '%s\n' "$MC_TIED" | sed '/^$/d' | LC_ALL=C sort -u)
    while IFS= read -r copy; do
        [[ -n "$copy" ]] || continue
        grep -qxF "$copy" <<< "$MC_TIED" || MC_NAMES="${MC_NAMES:+$MC_NAMES$'\n'}$copy"
    done <<< "$named"
    MC_NAMES=$(printf '%s\n' "$MC_NAMES" | sed '/^$/d' | LC_ALL=C sort -u)
    for root in "${MC_APPS_ROOTS[@]+"${MC_APPS_ROOTS[@]}"}"; do
        [[ -d "$root" ]] || continue
        inventory=$(find "$root" -maxdepth 3 -name '*.app' -prune -print 2>/dev/null) || MC_ERRORS="${MC_ERRORS:+$MC_ERRORS$'\n'}installed copy inspection incomplete: $root"
        while IFS= read -r copy; do
            [[ -d "$copy" && "$copy" != "$MC_APP" ]] || continue
            id=$(mc_u_key "$copy" CFBundleIdentifier) || { unknown=true; MC_ERRORS="${MC_ERRORS:+$MC_ERRORS$'\n'}uninspected app: $copy"; continue; }
            mole_is_reverse_dns_bundle_id "$id" || { unknown=true; MC_ERRORS="${MC_ERRORS:+$MC_ERRORS$'\n'}uninspected app: $copy"; continue; }
            other_ids="${other_ids}${id}"$'\n'
            [[ "$id" != "$MC_ID" ]] || sibling=true
        done <<< "$inventory"
    done
    if [[ "$sibling" == true ]]; then
        MC_NAMES=$(printf '%s\n%s\n' "$MC_NAMES" "$MC_TIED" | sed '/^$/d' | LC_ALL=C sort -u)
        MC_TIED=""
    fi
    candidates="$MC_TIED"; MC_TIED=""
    while IFS= read -r copy; do
        [[ -n "$copy" ]] || continue
        foreign=false
        local longest="$MC_ID"
        while IFS= read -r id; do
            [[ -n "$id" && "$id" != "$MC_ID" ]] || continue
            if mole_name_has_bundle_id_boundary "${copy##*/}" "$id" && [[ ${#id} -gt ${#longest} ]]; then longest="$id"; fi
        done <<< "$other_ids"
        [[ "$longest" == "$MC_ID" ]] || foreign=true
        # Suffix data may belong to a bundle whose identity is unknown.
        if [[ "$unknown" == true && "${copy##*/}" != "$MC_ID" ]]; then foreign=true; fi
        if [[ "$foreign" == true ]]; then MC_NAMES="${MC_NAMES:+$MC_NAMES$'\n'}$copy"
        else MC_TIED="${MC_TIED:+$MC_TIED$'\n'}$copy"; fi
    done <<< "$candidates"
    [[ -z "$MC_REQUIRED_ERRORS" || "$MC_ERRORS" == *"$MC_REQUIRED_ERRORS"* ]] || MC_ERRORS="${MC_ERRORS:+$MC_ERRORS$'\n'}$MC_REQUIRED_ERRORS"
}
mc_u_section() {
    case "$1" in
        "$MC_APP") echo 'The app';;
        */Preferences/* | */Saved\ Application\ State/*) echo 'Settings and saved state';;
        */Caches/* | */Logs/* | */.cache/*) echo 'Caches and logs';;
        */LaunchAgents/* | */Helpers/*) echo 'Helpers and launch agents';;
        *) echo 'Its data';;
    esac
}
# Scan state preserves identity and observations, never approval.
mc_u_state() {
    local base="${TMPDIR%/}" mode
    [[ -d "$base" && -O "$base" && ! -L "$base" ]] || return 1
    mode=$(stat -f '%Lp' "$base") || return 1
    [[ "$mode" =~ ^[0-7]+$ ]] && (( (8#$mode & 2) == 0 )) || return 1
    MC_STATE="$base/mac-cleaner-uninstall"
    [[ ! -L "$MC_STATE" ]] || return 1
    if [[ -e "$MC_STATE" ]]; then
        [[ -d "$MC_STATE" && -O "$MC_STATE" ]] || return 1
        mode=$(stat -f '%Lp' "$MC_STATE") || return 1
        [[ "$mode" =~ ^[0-7]+$ ]] && (( (8#$mode & 077) == 0 )) || return 1
    fi
    (umask 077; mkdir -p "$MC_STATE") || return 1
    [[ -O "$MC_STATE" ]] || return 1
    chmod 700 "$MC_STATE"
}
mc_u_save() {
    local token
    token=$(printf '%s' "$MC_APP" | cksum | awk '{print $1}')
    MC_TOKEN="$token"
    printf '%s\0%s\0%s\0%s\0%s\0%s\0' "$MC_APP" "$MC_ID" "$MC_NAME" "$MC_VERSION" "$MC_EXEC" "$MC_TIED" > "$MC_STATE/$token.state"
}
mc_u_load() {
    local file
    for file in "$MC_STATE"/*.state; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        { IFS= read -r -d '' MC_APP && IFS= read -r -d '' MC_ID && IFS= read -r -d '' MC_NAME && IFS= read -r -d '' MC_VERSION && IFS= read -r -d '' MC_EXEC && IFS= read -r -d '' MC_PREVIOUS; } < "$file" || continue
        if [[ "$1" == "$MC_APP" || "$1" == "$MC_ID" ]]; then
            MC_TOKEN="${file##*/}"; MC_TOKEN="${MC_TOKEN%.state}"
            return 0
        fi
    done
    return 1
}
mc_u_plan_identity() {
    local file token saved
    for file in "$MC_STATE"/*.plan; do
        [[ -f "$file" && ! -L "$file" ]] || continue
        cmp -s "$file" "$plan_file" || continue
        token="${file##*/}"; token="${token%.plan}"
        saved="$MC_STATE/$token.state"
        [[ -f "$saved" && ! -L "$saved" ]] || continue
        IFS= read -r -d '' MC_APP < "$saved" || continue
        mc_u_load "$MC_APP" && mc_u_allowed && return 0
    done
    return 1
}
