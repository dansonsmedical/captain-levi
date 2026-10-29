#!/bin/bash
# The scan never offers things that are the user's rather than caches, or that sit where macOS would ask
# for permission (Downloads, Documents, cloud folders), and it never stops processes.
source "$(dirname "$0")/lib.sh"
make_sandbox
trap cleanup_sandbox EXIT
if ! grep -q 'MAC_CLEANER_CLEAN_ALWAYS_DRY' "$REPO_ROOT/bin/clean.sh"; then
    fail "bin/clean.sh is not this copy's always-dry-run version; refusing to run it"
    finish
    exit 1
fi

H="$HOME"
put() { mkdir -p "$(dirname "$H/$1")" && echo x > "$H/$1" && touch -t 202601010000 "$H/$1"; }
put "Library/Caches/com.example.app/blob"
put "Downloads/movie.crdownload"
put "Library/Caches/com.apple.akd/token"
put "Library/IdentityCaches/id"
put "Library/Saved Application State/com.example.app.savedState/window"
put "Library/Application Support/com.apple.sharedfilelist/recent.sfl3"
put ".zsh_history.bak1"
put ".gitconfig.bak"
put ".aws/cli/cache/sso.json"
put ".prometheus/data/wal/0001"
put ".jupyter/runtime/kernel.json"
put ".sonar/cache/plugin"
put "Movies/Edit.fcpbundle/Project/Render Files/High Quality Media/r.mov"
put "work/app/.git/HEAD"
put "work/app/src/__pycache__/m.pyc"

/bin/bash "$REPO_ROOT/bin/clean.sh" --plan-out "$SANDBOX/plan.bin" > "$SANDBOX/clean.log" 2>&1 < /dev/null
plan_text() { tr '\0' '\n' < "$SANDBOX/plan.bin"; }
offered() { plan_text | grep -qF "$H/$1"; }

echo "ordinary caches are still offered:"
check "an app cache" offered "Library/Caches/com.example.app"
echo "never offered:"
for p in Downloads/movie.crdownload Library/Caches/com.apple.akd Library/IdentityCaches "Library/Saved Application State" \
    "Library/Application Support/com.apple.sharedfilelist" .zsh_history.bak1 .gitconfig.bak .aws/cli/cache \
    .prometheus/data/wal .jupyter/runtime .sonar "Movies/Edit.fcpbundle" "work/app/src/__pycache__"; do
    check_not "$p" offered "$p"
done
check_not "the scan never mentions stopping processes" grep -q "Leaked automation browsers" "$SANDBOX/clean.log"
finish
