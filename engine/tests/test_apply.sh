#!/bin/bash
# apply.sh deletes only what the user ticked from a plan, through Mole's guard, and nothing else.
source "$(dirname "$0")/lib.sh"
make_sandbox
trap cleanup_sandbox EXIT

H="$HOME"
APPLY="$REPO_ROOT/engine/apply.sh"
mkdir -p "$H/Library/Caches/com.example.one" "$H/Library/Caches/com.example.two" "$H/Library/Caches/com.example.three" \
    "$H/Documents/notes" "$H/Downloads" "$H/.Trash" "$SANDBOX/outside/cache"
for d in one two three; do echo x > "$H/Library/Caches/com.example.$d/data"; done
echo precious > "$H/Documents/notes/file.txt"
echo outside > "$SANDBOX/outside/cache/data"
ln -s "$H/Documents/notes" "$H/Library/Caches/link-to-documents"
echo dmg > "$H/Downloads/Tool-1.2.dmg"
echo letter > "$H/Downloads/letter.pdf"

plan_record() { printf '%s\0%s\0%s\0%s\0%s\0%s\0' "$1" "$2" 4 1 true "" >> "$SANDBOX/plan.bin"; }
plan_record "App caches" "$H/Library/Caches/com.example.one"
plan_record "App caches" "$H/Library/Caches/com.example.two"
plan_record "App caches" "$H/Library/Caches/com.example.three"
plan_record "App caches" "$H/Library/Caches/link-to-documents"
plan_record "App caches" "$H/Documents/notes"
plan_record "App caches" "$SANDBOX/outside/cache"
plan_record "Old installers" "$H/Downloads/Tool-1.2.dmg"
plan_record "Old installers" "$H/Downloads/letter.pdf"

approve() { : > "$SANDBOX/approved.bin"; local p; for p in "$@"; do printf '%s\0' "$p" >> "$SANDBOX/approved.bin"; done; }
run_apply() { /bin/bash "$APPLY" --plan "$SANDBOX/plan.bin" --approved "$SANDBOX/approved.bin" \
    --log "$SANDBOX/history.tsv" --jail "$H" "$@" > "$SANDBOX/apply.out" 2>&1 < /dev/null; }
said() { grep -qF "$1" "$SANDBOX/apply.out"; }
said_for() { grep -F "$1" "$SANDBOX/apply.out" | grep -qF "$2"; }

echo "dry run:"
approve "$H/Library/Caches/com.example.one"
check "exits cleanly" run_apply --dry-run
check "deletes nothing" test -e "$H/Library/Caches/com.example.one/data"
check "says what it would delete" said "would-delete"

echo "real run:"
approve "$H/Library/Caches/com.example.one" "$H/Library/Caches/com.example.three" "$H/Library/Caches/not-in-plan" \
    "$H/Library/Caches/link-to-documents" "$H/Documents/notes" "$SANDBOX/outside/cache"
check "exits cleanly" run_apply
check "deletes a ticked plan item" test ! -e "$H/Library/Caches/com.example.one"
check "deletes another ticked plan item" test ! -e "$H/Library/Caches/com.example.three"
check "leaves an unticked plan item alone" test -e "$H/Library/Caches/com.example.two/data"
check "refuses a path that was not in the plan" said "not in the plan"
check "refuses a link into Documents, which stays" test -e "$H/Documents/notes/file.txt"
check "refuses Documents even when it is in the plan" test -e "$H/Documents/notes"
check "refuses a path outside the jail" test -e "$SANDBOX/outside/cache/data"
check "writes a history line for each deletion" grep -qF "$H/Library/Caches/com.example.one" "$SANDBOX/history.tsv"

echo "logs a running program has open stay:"
# lsof lists the caller's own working folder (as the real one always does) and whatever lsof-out holds ("n/path" lines).
cat > "$SANDBOX/stubs/lsof" << STUB
#!/bin/sh
[ -f "$SANDBOX/lsof-fail" ] && exit 1
printf 'p1\nfcwd\nn%s\n' "\$(pwd -P)"
[ -f "$SANDBOX/lsof-out" ] && cat "$SANDBOX/lsof-out"
exit 0
STUB
chmod +x "$SANDBOX/stubs/lsof"
mkdir -p "$H/Library/Logs/OpenApp" "$H/Library/Logs/ClosedApp" "$H/Library/Caches/com.example.live" "$H/Library/Logs"
echo l > "$H/Library/Logs/OpenApp/today.log"; echo l > "$H/Library/Logs/ClosedApp/old.log"; echo l > "$H/Library/Logs/live.log"
echo c > "$H/Library/Caches/com.example.live/data"
for p in "$H/Library/Logs/OpenApp" "$H/Library/Logs/ClosedApp" "$H/Library/Logs/live.log" "$H/Library/Caches/com.example.live"; do
    plan_record "App caches" "$p"
done
printf 'p77\nf5\nn%s\nf6\nn%s\nf7\nn%s\n' "$H/Library/Logs/OpenApp/today.log" "$H/Library/Logs/live.log" "$H/Library/Caches/com.example.live/data" > "$SANDBOX/lsof-out"
approve "$H/Library/Logs/OpenApp" "$H/Library/Logs/ClosedApp" "$H/Library/Logs/live.log" "$H/Library/Caches/com.example.live"
check "exits cleanly" run_apply
check "keeps a log file a program has open" test -e "$H/Library/Logs/live.log"
check "keeps a log folder with an open file inside" test -e "$H/Library/Logs/OpenApp/today.log"
check "says a running program has it open" said_for "$H/Library/Logs/live.log" "running program"
check "deletes a log folder nothing has open" test ! -e "$H/Library/Logs/ClosedApp"
check "an open cache that is not a log is left to Mole's own checks" test ! -e "$H/Library/Caches/com.example.live"
rm -f "$SANDBOX/lsof-out"
mkdir -p "$H/Library/Logs/AnyApp"; echo l > "$H/Library/Logs/AnyApp/a.log"; plan_record "App caches" "$H/Library/Logs/AnyApp"
approve "$H/Library/Logs/AnyApp"
touch "$SANDBOX/lsof-fail"
check "exits cleanly when lsof fails" run_apply
rm -f "$SANDBOX/lsof-fail"
check "a log is kept when nothing can tell whether it is open" test -e "$H/Library/Logs/AnyApp/a.log"
check "and says it could not tell" said_for "$H/Library/Logs/AnyApp" "could not tell"

echo "log folders outside Library/Logs, other letter case, and a big lsof answer:"
mkdir -p "$H/Library/Application Support/Code/logs/20250601T0000" "$H/Library/Application Support/Code/logs/20250101T0000" \
    "$H/Library/Logs/MixedCase"
echo l > "$H/Library/Application Support/Code/logs/20250601T0000/main.log"
echo l > "$H/Library/Application Support/Code/logs/20250101T0000/main.log"
echo l > "$H/Library/Logs/MixedCase/a.log"
for p in "$H/Library/Application Support/Code/logs/20250601T0000" "$H/Library/Application Support/Code/logs/20250101T0000" "$H/Library/Logs/MixedCase"; do
    plan_record "App caches" "$p"
done
{
    printf 'p88\nf3\nn%s\nf4\nn%s\n' "$H/Library/Application Support/Code/logs/20250601T0000/main.log" "$H/library/logs/MIXEDCASE/a.log"
    i=0; while [[ $i -lt 6000 ]]; do printf 'f9\nn/private/var/some/open/file-%s\n' "$i"; i=$((i + 1)); done
} > "$SANDBOX/lsof-out"
approve "$H/Library/Application Support/Code/logs/20250601T0000" "$H/Library/Application Support/Code/logs/20250101T0000" "$H/Library/Logs/MixedCase"
check "exits cleanly" run_apply
check "keeps VS Code's open log folder (a Logs folder outside Library/Logs)" test -e "$H/Library/Application Support/Code/logs/20250601T0000/main.log"
check "deletes the same app's old log folder that nothing has open" test ! -e "$H/Library/Application Support/Code/logs/20250101T0000"
check "keeps an open log when lsof spells the folder in other letter case" test -e "$H/Library/Logs/MixedCase/a.log"
check "a big lsof answer does not make every log 'could not tell'" test "$(grep -c 'could not tell' "$SANDBOX/apply.out")" -eq 0
rm -f "$SANDBOX/lsof-out"

echo "a plan or list that cannot be read safely:"
mkdir -p "$H/Library/Caches/com.example.four"; echo x > "$H/Library/Caches/com.example.four/data"
approve "$H/Library/Caches/com.example.four"
cp "$SANDBOX/plan.bin" "$SANDBOX/plan-full.bin"
: > "$SANDBOX/plan.bin"
check "exits cleanly with an empty plan" run_apply
check "an empty plan lists nothing to delete" test -e "$H/Library/Caches/com.example.four/data"
check "and says it is not in the plan" said "not in the plan"
cp "$SANDBOX/plan-full.bin" "$SANDBOX/plan.bin"
plan_record "App caches" "$H/Library/Caches/odd
name"
check_not "a plan with a line break in a path is refused whole" run_apply
check "and deletes nothing" test -e "$H/Library/Caches/com.example.four/data"
cp "$SANDBOX/plan-full.bin" "$SANDBOX/plan.bin"
plan_record "App caches" "$H/Library/Caches/com.example.four"
approve "$H/Library/Caches/com.example.four" "$H/Library/Caches/one
two"
check_not "a ticked list with a line break in a path is refused whole" run_apply
check "and deletes nothing there either" test -e "$H/Library/Caches/com.example.four/data"
approve "$H/Library/Caches/com.example.four"
check "a good list after that still works" run_apply
check "and deletes the ticked item" test ! -e "$H/Library/Caches/com.example.four"

echo "installers go to the Trash:"
approve "$H/Downloads/Tool-1.2.dmg" "$H/Downloads/letter.pdf"
check "exits cleanly" run_apply --trash
check "moves the installer out of Downloads" test ! -e "$H/Downloads/Tool-1.2.dmg"
check "puts it in the Trash" test -e "$H/.Trash/Tool-1.2.dmg"
check "refuses a file that is not an installer" test -e "$H/Downloads/letter.pdf"

echo "no prompts, no admin rights:"
check_not "never called sudo or osascript" grep -qsE '^(sudo|osascript)' "$SANDBOX/stub-calls.log"
check_not "never tried rm outside the sandbox" grep -qsE '^rm ' "$SANDBOX/stub-calls.log"
[[ $T_FAILS -eq 0 ]] || { echo "--- apply.out"; tail -20 "$SANDBOX/apply.out"; }
finish
