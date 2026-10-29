#!/bin/bash
# `clean` only ever looks: it writes a plan of what could go and deletes nothing, with or without flags.
source "$(dirname "$0")/lib.sh"
make_sandbox
trap cleanup_sandbox EXIT

H="$HOME"
mkdir -p "$H/Library/Caches/com.example.app" "$H/Library/Logs/demo" "$H/.Trash"
dd if=/dev/zero of="$H/Library/Caches/com.example.app/blob.bin" bs=1024 count=2048 2> /dev/null
echo log > "$H/Library/Logs/demo/old.log"
touch -t 202601010000 "$H/Library/Logs/demo/old.log"
echo keep > "$H/.Trash/thrown-away.txt"

# Never run a clean.sh that could delete outside the sandbox.
if ! grep -q 'MAC_CLEANER_CLEAN_ALWAYS_DRY' "$REPO_ROOT/bin/clean.sh"; then
    fail "bin/clean.sh is not this copy's always-dry-run version; refusing to run it"
    finish
    exit 1
fi

run_clean() { # args → exit status; output in $SANDBOX/clean.log
    /bin/bash "$REPO_ROOT/bin/clean.sh" "$@" > "$SANDBOX/clean.log" 2>&1 < /dev/null
}

echo "clean with --plan-out:"
check "exits cleanly" run_clean --plan-out "$SANDBOX/plan.bin"
check "deletes nothing: the app cache is still there" test -f "$H/Library/Caches/com.example.app/blob.bin"
check "deletes nothing: the old log is still there" test -f "$H/Library/Logs/demo/old.log"
check "deletes nothing: the Trash is untouched" test -f "$H/.Trash/thrown-away.txt"
check "writes the plan" test -s "$SANDBOX/plan.bin"
plan_text() { tr '\0' '\n' < "$SANDBOX/plan.bin"; }
check "the plan lists the app cache" grep -qxF "$H/Library/Caches/com.example.app" <(plan_text)
check "the plan lists the old log" grep -qF "$H/Library/Logs/demo" <(plan_text)

echo "clean with no flags at all:"
check "exits cleanly" run_clean
check "still deletes nothing" test -f "$H/Library/Caches/com.example.app/blob.bin"

echo "no prompts, no admin rights:"
check_not "never called sudo or osascript" grep -qsE '^(sudo|osascript)' "$SANDBOX/stub-calls.log"
check_not "never tried rm outside the sandbox" grep -qsE '^rm ' "$SANDBOX/stub-calls.log"
[[ $T_FAILS -eq 0 ]] || { echo "--- clean.log (tail)"; tail -25 "$SANDBOX/clean.log"; }
finish
