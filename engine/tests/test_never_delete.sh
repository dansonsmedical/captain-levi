#!/bin/bash
# The deletion guard refuses the user's personal folders, whatever path or link leads there.
source "$(dirname "$0")/lib.sh"
make_sandbox
trap cleanup_sandbox EXIT

H="$HOME"
for d in Documents/notes Desktop/shot Downloads/app Pictures "Pictures/Photos Library.photoslibrary/database" \
    Movies/clip Music/song Public/Drop Library/Messages/Attachments Library/Mail/V10 \
    "Library/Mobile Documents/com~apple~CloudDocs" Library/CloudStorage/GoogleDrive .ssh .gnupg \
    .claude/projects .codex/sessions Library/Caches/sync-fixture captain-levi-fixture/lib \
    Library/Caches/com.example.app "Library/Application Support/Code/Cache" .npm/_cacache Library/Logs/demo \
    work/project/.claude/worktrees/feature/node_modules work/project/.codex/worktrees/feature/node_modules .local/share/claude/versions/9.8.765; do
    mkdir -p "$H/$d"
    echo data > "$H/$d/file.txt"
done
ln -s "$H/Documents/notes" "$H/Library/Caches/link-to-documents"

# shellcheck disable=SC1091
source "$REPO_ROOT/lib/core/common.sh" > /dev/null 2>&1

refused() { ! validate_path_for_deletion "$1" > /dev/null 2>&1; }
allowed() { validate_path_for_deletion "$1" > /dev/null 2>&1; }

echo "never-delete list:"
for p in "$H" "$H/Library" "$H/Documents" "$H/Documents/notes/file.txt" "$H/Desktop/shot" "$H/Downloads/app/file.txt" \
    "$H/Pictures" "$H/Pictures/Photos Library.photoslibrary" "$H/Movies/clip" "$H/Music/song/file.txt" \
    "$H/Public/Drop" "$H/Library/Messages/Attachments" "$H/Library/Mail/V10/file.txt" \
    "$H/Library/Mobile Documents/com~apple~CloudDocs/file.txt" "$H/Library/CloudStorage/GoogleDrive/file.txt" \
    "$H/.ssh/file.txt" "$H/.gnupg" "$H/.claude/projects" "$H/.codex/sessions" \
    "$H/work/project/.claude/worktrees/feature/node_modules" "$H/work/project/.codex/worktrees/feature/node_modules" "$H/.local/share/claude/versions/9.8.765" \
    "$H/documents/notes" "$H/DESKTOP/shot"; do
    check "refuses ${p#"$H"/}" refused "$p"
done
check "refuses a cache path with a trailing slash" refused "$H/Library/Caches/com.example.app/"
check "refuses a cache symlink that points into Documents" refused "$H/Library/Caches/link-to-documents"
check "refuses the engine's own folder" refused "$REPO_ROOT/lib"

echo "ordinary caches stay cleanable:"
check "allows an app cache" allowed "$H/Library/Caches/com.example.app"
check "allows an app support cache" allowed "$H/Library/Application Support/Code/Cache"
check "allows the npm cache" allowed "$H/.npm/_cacache"
check "allows a user log folder" allowed "$H/Library/Logs/demo"
# Direct guard assertions avoid unrelated system-path refusals masking missing rules.
for p in '/Applications/Captain Levi.app' '/Applications/Captain Levi.app/Contents/file' \
    "$H/Applications/Captain Levi.app" "$H/Applications/Captain Levi.app/Contents/file" \
    "$H/Applications/Mac Cleaner.app" "$H/Library/Application Support/Mac Cleaner/history.tsv"; do
    check "guard protects $p" mac_cleaner_never_delete_path "$p"
done
fake="$SANDBOX/X Y.app/Contents/Resources/engine"
mkdir -p "$fake/lib/core"
cp "$REPO_ROOT/lib/core/never_delete.sh" "$fake/lib/core/never_delete.sh"
guard_from_copy() {
    /bin/bash -c 'unset MAC_CLEANER_NEVER_DELETE_LOADED; source "$1"; mac_cleaner_never_delete_path "$2"' bash "$1" "$2"
}
check 'renamed app protected' guard_from_copy "$fake/lib/core/never_delete.sh" "$SANDBOX/X Y.app"
check 'renamed app child protected' guard_from_copy "$fake/lib/core/never_delete.sh" "$SANDBOX/X Y.app/Contents/file"
check_not 'similar app name is allowed' guard_from_copy "$fake/lib/core/never_delete.sh" "$SANDBOX/X Y.app2"
check_not 'unrelated app is allowed' guard_from_copy "$fake/lib/core/never_delete.sh" "$SANDBOX/Other.app"
# Each mutation removes only its rule from a disposable copy.
for rule in system home-captain home-mac history bundle; do
    mutation="$SANDBOX/$rule.sh"
    case "$rule" in
        system) sed 's@/Applications/Captain\\ Levi.app@/Applications/Other\\ App.app@g' "$fake/lib/core/never_delete.sh" > "$mutation"; target='/Applications/Captain Levi.app' ;;
        home-captain) sed '/home\/Applications\/Captain Levi.app/d' "$fake/lib/core/never_delete.sh" > "$mutation"; target="$H/Applications/Captain Levi.app" ;;
        home-mac) sed '/home\/Applications\/Mac Cleaner.app/d' "$fake/lib/core/never_delete.sh" > "$mutation"; target="$H/Applications/Mac Cleaner.app" ;;
        history) sed '/home\/Library\/Application Support\/Mac Cleaner/d' "$fake/lib/core/never_delete.sh" > "$mutation"; target="$H/Library/Application Support/Mac Cleaner/history.tsv" ;;
        bundle) sed '/case "$path" in "$bundle"/d' "$fake/lib/core/never_delete.sh" > "$mutation"; target="$SANDBOX/X Y.app" ;;
    esac
    cp "$mutation" "$fake/lib/core/never_delete.sh"
    check_not "$rule mutation loses corresponding protection" guard_from_copy "$fake/lib/core/never_delete.sh" "$target"
    cp "$REPO_ROOT/lib/core/never_delete.sh" "$fake/lib/core/never_delete.sh"
done
finish
