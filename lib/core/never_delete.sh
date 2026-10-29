#!/bin/bash
# Hard never-delete rules for user data.
#
# Mole's own guard protects the system. This list protects user data: personal folders, cloud
# and sync folders, keys, iPhone backups, other tools' data folders, and this
# tool's own folder. validate_path_for_deletion consults it through _mole_is_critical_deletion_path
# for the literal path, a symlink's target and the path with every parent folder resolved, so no
# spelling and no link reaches these folders. Matching ignores case, like the Mac's disk.

if [[ -n "${MAC_CLEANER_NEVER_DELETE_LOADED:-}" ]]; then
    return 0
fi
MAC_CLEANER_NEVER_DELETE_LOADED=1

# The folder this copy runs from (lib/core/../..).
MAC_CLEANER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2> /dev/null && pwd -P)"

# Returns 0 when the path must never be deleted.
mac_cleaner_never_delete_path() {
    local path="$1"
    local home="${HOME%/}"
    local had_nocasematch=false
    shopt -q nocasematch && had_nocasematch=true
    shopt -s nocasematch

    local verdict=1
    # A trailing slash makes rm follow a symlink into its target.
    if [[ "$path" == */ && "$path" != "/" ]]; then
        verdict=0
    fi
    case "$path" in
        /Applications/Mac\ Cleaner.app | /Applications/Mac\ Cleaner.app/* | \
            /Applications/Captain\ Levi.app | /Applications/Captain\ Levi.app/*)
            verdict=0
            ;;
        */.claude/worktrees | */.claude/worktrees/* | \
            */.codex/worktrees | */.codex/worktrees/* | \
            *.photoslibrary | *.photoslibrary/*)
            verdict=0
            ;;
    esac
    if [[ -n "$MAC_CLEANER_ROOT" ]]; then
        case "$path" in
            "$MAC_CLEANER_ROOT" | "$MAC_CLEANER_ROOT"/*) verdict=0 ;;
        esac
    fi
    # A bundled engine also protects its containing app, regardless of its filename.
    case "$MAC_CLEANER_ROOT" in
        *.app/Contents/Resources/engine)
            local bundle="${MAC_CLEANER_ROOT%/Contents/Resources/engine}"
            case "$path" in "$bundle" | "$bundle"/*) verdict=0 ;; esac
            ;;
    esac
    if [[ -n "$home" ]]; then
        case "$path" in
            "$home" | "$home/Library" | \
                "$home/Documents" | "$home/Documents/"* | \
                "$home/Desktop" | "$home/Desktop/"* | \
                "$home/Downloads" | "$home/Downloads/"* | \
                "$home/Pictures" | "$home/Pictures/"* | \
                "$home/Movies" | "$home/Movies/"* | \
                "$home/Music" | "$home/Music/"* | \
                "$home/Public" | "$home/Public/"* | \
                "$home/Library/Messages" | "$home/Library/Messages/"* | \
                "$home/Library/Mail" | "$home/Library/Mail/"* | \
                "$home/Library/Keychains" | "$home/Library/Keychains/"* | \
                "$home/Library/Safari" | "$home/Library/Safari/"* | \
                "$home/Library/Calendars" | "$home/Library/Calendars/"* | \
                "$home/Library/Mobile Documents" | "$home/Library/Mobile Documents/"* | \
                "$home/Library/CloudStorage" | "$home/Library/CloudStorage/"* | \
                "$home/Library/Application Support/MobileSync" | "$home/Library/Application Support/MobileSync/"* | \
                "$home/Library/Application Support/AddressBook" | "$home/Library/Application Support/AddressBook/"* | \
                "$home/.ssh" | "$home/.ssh/"* | \
                "$home/.gnupg" | "$home/.gnupg/"* | \
                "$home/.claude" | "$home/.claude/"* | \
                "$home/.codex" | "$home/.codex/"* | \
                "$home/.local/share/claude" | "$home/.local/share/claude/"* | \
                "$home/Applications/Mac Cleaner.app" | "$home/Applications/Mac Cleaner.app/"* | \
                "$home/Applications/Captain Levi.app" | "$home/Applications/Captain Levi.app/"* | \
                "$home/Library/Application Support/Mac Cleaner" | "$home/Library/Application Support/Mac Cleaner/"*)
                verdict=0
                ;;
        esac
    fi

    [[ "$had_nocasematch" == "true" ]] || shopt -u nocasematch
    return "$verdict"
}
