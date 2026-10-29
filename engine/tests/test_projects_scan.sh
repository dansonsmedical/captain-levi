#!/bin/bash
# bin/projects.sh only ever looks: it lists old build folders in project folders as a plan (same six
# fields as clean.sh --plan-out) plus a display-only .meta file with each folder's age and state.
# It never reads Documents, Desktop or Downloads, skips cloud folders, links and agent worktrees, and
# calls a project "in use" when its files changed lately or a program runs inside it.
source "$(dirname "$0")/lib.sh"
make_sandbox
trap cleanup_sandbox EXIT

H="$HOME"
PROJECTS="$REPO_ROOT/bin/projects.sh"

# Never run a projects.sh that could delete.
if grep -qE '(safe_remove|[[:space:]]rm[[:space:]]|rm -rf|validate_path_for_deletion)' "$PROJECTS"; then
    fail "bin/projects.sh has a delete call; refusing to run it"
    finish
    exit 1
fi

# Wrappers that log what the scan reads, so a test can prove which folders were never touched.
for cmd in find du stat; do
    real="$(PATH=/usr/bin:/bin command -v "$cmd")"
    # With a find-fail marker, every date walk (-mtime) fails, as when a huge folder times out.
    printf '#!/bin/sh\necho "%s $*" >> "%s/reads.log"\ncase "$*" in *-mtime*) [ -f "%s/find-fail" ] && exit 5;; esac\nexec %s "$@"\n' \
        "$cmd" "$SANDBOX" "$SANDBOX" "$real" > "$SANDBOX/stubs/$cmd"
    chmod +x "$SANDBOX/stubs/$cmd"
done
# git may only answer ls-files, and says "tracked" for a folder that holds a .tracked marker.
cat > "$SANDBOX/stubs/git" << STUB
#!/bin/sh
dir=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        -C) dir="\$2"; shift ;;
        ls-files) [ -f "\$dir/.tracked" ] && echo "\$dir/.tracked"; exit 0 ;;
    esac
    shift
done
echo "git \$*" >> "$SANDBOX/stub-calls.log"
exit 1
STUB
chmod +x "$SANDBOX/stubs/git"
# lsof lists the caller's own working folder (as the real one always does) and whatever the test puts in
# lsof-out, in the -F format: p<pid> / fcwd / n<path>. With an lsof-fail marker it fails like a broken lsof.
cat > "$SANDBOX/stubs/lsof" << STUB
#!/bin/sh
echo "lsof \$*" >> "$SANDBOX/reads.log"
[ -f "$SANDBOX/lsof-fail" ] && exit 1
printf 'p1\nfcwd\nn%s\n' "\$(pwd -P)"
[ -f "$SANDBOX/lsof-out" ] && cat "$SANDBOX/lsof-out"
exit 0
STUB
chmod +x "$SANDBOX/stubs/lsof"

old() { touch -t 202601010000 "$@"; }
mkproj() { # name: a project folder with an old manifest and old build folders
    mkdir -p "$H/$1/src" "$H/$1/node_modules/pkg"
    echo '{}' > "$H/$1/package.json"
    echo code > "$H/$1/src/app.js"
    dd if=/dev/zero of="$H/$1/node_modules/pkg/big.bin" bs=1024 count=300 2> /dev/null
    old "$H/$1/package.json" "$H/$1/src/app.js" "$H/$1/src" "$H/$1/node_modules/pkg/big.bin" "$H/$1/node_modules/pkg" "$H/$1/node_modules" "$H/$1"
}

mkproj old-app                                             # all old: listed and ticked
mkproj busy-app; touch "$H/busy-app/src/app.js"            # source changed just now, build folder old
mkproj run-app                                             # old, but a program runs inside it
mkproj mixed-app
mkdir -p "$H/mixed-app/dist" "$H/mixed-app/.venv"
echo out > "$H/mixed-app/dist/bundle.js"; echo home = x > "$H/mixed-app/.venv/pyvenv.cfg"
old "$H/mixed-app/dist/bundle.js" "$H/mixed-app/dist" "$H/mixed-app/.venv/pyvenv.cfg" "$H/mixed-app/.venv" "$H/mixed-app"
mkproj tracked-app
mkdir -p "$H/tracked-app/build"; echo source > "$H/tracked-app/build/Main.java"; touch "$H/tracked-app/build/.tracked"
mkdir -p "$H/tracked-app/.git"
old "$H/tracked-app/build/Main.java" "$H/tracked-app/build/.tracked" "$H/tracked-app/build" "$H/tracked-app"
mkproj wt-app
mkdir -p "$H/wt-app/.claude/worktrees/w1/node_modules/x" "$H/wt-app/.codex/worktrees/w2/node_modules/x"
echo '{}' > "$H/wt-app/.claude/worktrees/w1/package.json"
# folders the scan must never read, or skip
for d in Documents Desktop Downloads; do mkproj "$d/in-$d"; echo '{}' > "$H/$d/package.json"; done
mkdir -p "$SANDBOX/cloud/proj/node_modules/p"; echo '{}' > "$SANDBOX/cloud/proj/package.json"
ln -s "$SANDBOX/cloud" "$H/linked-cloud"
mkdir -p "$H/Library/CloudStorage/Dropbox/proj/node_modules/p"; echo '{}' > "$H/Library/CloudStorage/Dropbox/proj/package.json"
printf 'p4242\nfcwd\nn%s\n' "$H/run-app/src" > "$SANDBOX/lsof-out"

SCAN_ERR=0
/bin/bash "$PROJECTS" --plan-out "$SANDBOX/plan.bin" > "$SANDBOX/scan.log" 2>&1 < /dev/null || SCAN_ERR=$?
check "exits cleanly" test "$SCAN_ERR" -eq 0
check "writes the plan and its meta file" test -s "$SANDBOX/plan.bin" -a -s "$SANDBOX/plan.bin.meta"

plan_text() { tr '\0' '\n' < "$SANDBOX/plan.bin"; }
listed() { plan_text | grep -qxF "$1"; }
# meta record fields: path, last change (epoch), state, project folder, ticked yes/no
meta() { # path field-number
    tr '\0' '\n' < "$SANDBOX/plan.bin.meta" | awk -v p="$1" -v n="$2" '{ i = (NR - 1) % 5 + 1; f[i] = $0 } i == 5 && f[1] == p { print f[n] }'
}

echo "what it lists:"
check "an old node_modules, with its section name" grep -qaF "Project folders" "$SANDBOX/plan.bin"
check "old-app/node_modules is listed" listed "$H/old-app/node_modules"
check "its size is the real size in KB" test "$(plan_text | awk -v p="$H/old-app/node_modules" '$0==p{getline;print;exit}')" -ge 300
check "old-app/node_modules is old" test "$(meta "$H/old-app/node_modules" 3)" = old
check "its project folder is old-app" test "$(meta "$H/old-app/node_modules" 4)" = "$H/old-app"
check "its last change is the folder's date" test "$(meta "$H/old-app/node_modules" 2)" -lt "$(($(date +%s) - 86400 * 30))"
check "it is ticked (node_modules, package.json beside it, old)" test "$(meta "$H/old-app/node_modules" 5)" = yes
check ".venv with pyvenv.cfg is listed and ticked" test "$(meta "$H/mixed-app/.venv" 5)" = yes
check "a generic dist is listed but not ticked" test "$(meta "$H/mixed-app/dist" 5)" = no
check "dist is old, so only the name keeps it unticked" test "$(meta "$H/mixed-app/dist" 3)" = old

echo "in use lately:"
check "busy-app/node_modules is listed" listed "$H/busy-app/node_modules"
check "a build folder is recent when the project's files changed lately" test "$(meta "$H/busy-app/node_modules" 3)" = recent
check "recent folders are not ticked" test "$(meta "$H/busy-app/node_modules" 5)" = no
check "a program running inside the project says running" test "$(meta "$H/run-app/node_modules" 3)" = running
check "a running project is not ticked" test "$(meta "$H/run-app/node_modules" 5)" = no

echo "what it leaves out:"
check_not "a build folder holding tracked files" listed "$H/tracked-app/build"
check_not "a worktree's node_modules (.claude)" listed "$H/wt-app/.claude/worktrees/w1/node_modules"
check_not "a worktree's node_modules (.codex)" listed "$H/wt-app/.codex/worktrees/w2/node_modules"
check_not "Documents" listed "$H/Documents/in-Documents/node_modules"
check_not "Desktop" listed "$H/Desktop/in-Desktop/node_modules"
check_not "Downloads" listed "$H/Downloads/in-Downloads/node_modules"
check_not "a linked folder that points at cloud storage" listed "$H/linked-cloud/proj/node_modules"
check_not "Library/CloudStorage" listed "$H/Library/CloudStorage/Dropbox/proj/node_modules"
check "the read log works: it saw the scan read old-app" grep -qsF "old-app" "$SANDBOX/reads.log"
check_not "never read Documents, Desktop or Downloads" grep -qsE "$H/(Documents|Desktop|Downloads)" "$SANDBOX/reads.log"
check_not "never read through the link" grep -qsE "linked-cloud|$SANDBOX/cloud" "$SANDBOX/reads.log"
check_not "never read Library" grep -qsE "$H/Library" "$SANDBOX/reads.log"

echo "deletes nothing, asks for nothing:"
check "old-app/node_modules is still there" test -e "$H/old-app/node_modules/pkg/big.bin"
check "mixed-app/dist is still there" test -e "$H/mixed-app/dist/bundle.js"
check_not "never called sudo or osascript" grep -qsE '^(sudo|osascript)' "$SANDBOX/stub-calls.log"
check_not "never ran git except ls-files" grep -qsE '^git ' "$SANDBOX/stub-calls.log"
check_not "never tried rm outside the sandbox" grep -qsE '^rm ' "$SANDBOX/stub-calls.log"
check "did not write Mole's purge config" test ! -e "$H/.config/mole/purge_paths"

echo "a folder named on the command line:"
mkproj ".hidden-code/named"
/bin/bash "$PROJECTS" --plan-out "$SANDBOX/plan.bin" > "$SANDBOX/scan.log" 2>&1 < /dev/null
check_not "a dot folder is not looked in by itself" listed "$H/.hidden-code/named/node_modules"
/bin/bash "$PROJECTS" --plan-out "$SANDBOX/plan.bin" --root "$H/.hidden-code" > "$SANDBOX/scan.log" 2>&1 < /dev/null
check "--root reads a folder the user names" listed "$H/.hidden-code/named/node_modules"

echo "a named folder that must be refused:"
mkproj ".vscode/ext/x"                                     # what a root of ~ itself would find
mkdir -p "$H/Documents/GitHub/p/node_modules/q" "$SANDBOX/cloud2/sub/proj/node_modules/q" "$H/Library/Foo/p/node_modules/q"
echo '{}' > "$H/Documents/GitHub/p/package.json"; echo '{}' > "$SANDBOX/cloud2/sub/proj/package.json"; echo '{}' > "$H/Library/Foo/p/package.json"
ln -s "$SANDBOX/cloud2" "$H/linkdir"
: > "$SANDBOX/reads.log"
for bad in "$H/." "$H/old-app/.." "$H" "$H/Documents" "$H/Documents/GitHub" "$H/Library/Foo" "$H/linkdir/sub" "$H/linked-cloud" "$SANDBOX/cloud2/sub"; do
    /bin/bash "$PROJECTS" --plan-out "$SANDBOX/plan.bin" --root "$bad" > "$SANDBOX/scan.log" 2>&1 < /dev/null
    check_not "--root ${bad#"$SANDBOX"/} lists a hidden-folder project of the home folder" listed "$H/.vscode/ext/x/node_modules"
    check_not "--root ${bad#"$SANDBOX"/} lists Documents/GitHub" listed "$H/Documents/GitHub/p/node_modules"
    check_not "--root ${bad#"$SANDBOX"/} lists through a link" listed "$H/linkdir/sub/proj/node_modules"
done
check_not "none of them read Documents, Desktop or Downloads" grep -qsE "$H/(Documents|Desktop|Downloads)" "$SANDBOX/reads.log"
check_not "none of them read through a link" grep -qsE "linkdir|cloud2" "$SANDBOX/reads.log"
check_not "none of them read Library" grep -qsE "$H/Library" "$SANDBOX/reads.log"

echo "when something cannot be told, it is never 'in use lately' (which the user could override):"
touch "$SANDBOX/lsof-fail"
/bin/bash "$PROJECTS" --plan-out "$SANDBOX/plan.bin" > "$SANDBOX/scan.log" 2>&1 < /dev/null
check "a failing lsof leaves old-app/node_modules listed" listed "$H/old-app/node_modules"
check "and unverified" test "$(meta "$H/old-app/node_modules" 3)" = unverified
check "and unticked" test "$(meta "$H/old-app/node_modules" 5)" = no
check "even an lsof that cannot list its caller counts as failing" grep -qF "could not see which programs are running" "$SANDBOX/scan.log"
rm -f "$SANDBOX/lsof-fail"
touch "$SANDBOX/find-fail"
/bin/bash "$PROJECTS" --plan-out "$SANDBOX/plan.bin" > "$SANDBOX/scan.log" 2>&1 < /dev/null
check "a date walk that fails leaves old-app/node_modules unverified, not recent" test "$(meta "$H/old-app/node_modules" 3)" = unverified
check "and unticked" test "$(meta "$H/old-app/node_modules" 5)" = no
rm -f "$SANDBOX/find-fail"

echo "the project's files, at any depth, and git's index:"
mkproj deep-app; mkdir -p "$H/deep-app/src/a/b/c/d"; echo x > "$H/deep-app/src/a/b/c/d/x.tsx"
old "$H/deep-app/src/a/b/c/d/x.tsx" "$H/deep-app/src/a/b/c/d" "$H/deep-app/src/a/b/c" "$H/deep-app/src/a/b" "$H/deep-app/src/a" "$H/deep-app/src" "$H/deep-app"
mkproj idx-app; mkdir -p "$H/idx-app/.git"; echo idx > "$H/idx-app/.git/index"
old "$H/idx-app/package.json" "$H/idx-app/src/app.js" "$H/idx-app/src" "$H/idx-app"
touch "$H/deep-app/src/a/b/c/d/x.tsx"                      # edited five folders down, just now
/bin/bash "$PROJECTS" --plan-out "$SANDBOX/plan.bin" > "$SANDBOX/scan.log" 2>&1 < /dev/null
check "an edit five folders down makes the project recent" test "$(meta "$H/deep-app/node_modules" 3)" = recent
check "a git index written lately makes the project recent" test "$(meta "$H/idx-app/node_modules" 3)" = recent

echo "cloud-sync folders, the Trash, build folders, duplicates:"
mkproj "Dropbox (Personal)/proj"; mkproj "Creative Cloud Files x/proj"; mkproj "Box Sync/proj"
mkdir -p "$H/.Trash/p/node_modules/q"; echo '{}' > "$H/.Trash/p/package.json"
echo '{}' > "$H/old-app/node_modules/pkg/package.json"; mkdir -p "$H/old-app/node_modules/pkg/dist"
/bin/bash "$PROJECTS" --plan-out "$SANDBOX/plan.bin" --root "$H/.TRASH" --root "$H/old-app/node_modules/pkg" --root "$H/old-app" > "$SANDBOX/scan.log" 2>&1 < /dev/null
check_not "a Dropbox folder is not looked in" listed "$H/Dropbox (Personal)/proj/node_modules"
check_not "an Adobe Creative Cloud folder is not looked in" listed "$H/Creative Cloud Files x/proj/node_modules"
check_not "a Box Sync folder is not looked in" listed "$H/Box Sync/proj/node_modules"
check_not "a named .TRASH (any capitals) is refused" listed "$H/.Trash/p/node_modules"
check_not "a named folder inside a build folder is refused" listed "$H/old-app/node_modules/pkg/dist"
check "a folder named twice (named and found) is listed once" test "$(plan_text | grep -cxF "$H/old-app/node_modules")" -eq 1

echo "a plan that cannot be trusted:"
check "--plan-out needs an absolute path" bash -c "! /bin/bash '$PROJECTS' --plan-out relative.bin > /dev/null 2>&1 < /dev/null"
[[ $T_FAILS -eq 0 ]] || { echo "--- scan.log"; tail -25 "$SANDBOX/scan.log"; }
finish
