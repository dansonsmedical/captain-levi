#!/bin/bash
# apply.sh --projects deletes a ticked "Project folders" item only after checking it again: still a
# build folder, still under a project root, not tracked or hand-made, not in a worktree, nothing
# running in the project, and not changed lately (unless the user ticked an "in use lately" row on
# purpose, which is --allow-recent). Without --projects it never deletes one.
source "$(dirname "$0")/lib.sh"
make_sandbox
trap cleanup_sandbox EXIT

H="$HOME"
APPLY="$REPO_ROOT/engine/apply.sh"

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
cat > "$SANDBOX/stubs/lsof" << STUB
#!/bin/sh
[ -f "$SANDBOX/lsof-fail" ] && exit 1
printf 'p1\nfcwd\nn%s\n' "\$(pwd -P)"
[ -f "$SANDBOX/lsof-out" ] && cat "$SANDBOX/lsof-out"
exit 0
STUB
chmod +x "$SANDBOX/stubs/lsof"
# With a find-fail marker every date walk (-mtime) fails, as when a huge folder times out.
cat > "$SANDBOX/stubs/find" << STUB
#!/bin/sh
case "\$*" in *-mtime*) [ -f "$SANDBOX/find-fail" ] && exit 5;; esac
exec /usr/bin/find "\$@"
STUB
chmod +x "$SANDBOX/stubs/find"

old() { touch -t 202601010000 "$@"; }
mkproj() {
    mkdir -p "$H/$1/src" "$H/$1/node_modules/pkg"
    echo '{}' > "$H/$1/package.json"; echo code > "$H/$1/src/app.js"; echo x > "$H/$1/node_modules/pkg/f"
    old "$H/$1/package.json" "$H/$1/src/app.js" "$H/$1/src" "$H/$1/node_modules/pkg/f" "$H/$1/node_modules/pkg" "$H/$1/node_modules" "$H/$1"
}
for p in good busy running late dryrun other asplan; do mkproj "$p"; done
touch "$H/busy/src/app.js"                                   # the project's files changed just now
mkdir -p "$H/tracked/build" "$H/tracked/.git"; echo '{}' > "$H/tracked/package.json"
echo s > "$H/tracked/build/Main.java"; touch "$H/tracked/build/.tracked"
old "$H/tracked/package.json" "$H/tracked/build/Main.java" "$H/tracked/build/.tracked" "$H/tracked/build" "$H/tracked"
mkdir -p "$H/wt/.claude/worktrees/w1/node_modules/x" "$H/wt/.codex/worktrees/w2/node_modules/x"
echo '{}' > "$H/wt/package.json"
mkdir -p "$H/Documents/docproj/node_modules/x"; echo '{}' > "$H/Documents/docproj/package.json"
mkdir -p "$SANDBOX/elsewhere/data"; echo keep > "$SANDBOX/elsewhere/data/f"
mkdir -p "$H/linked"; echo '{}' > "$H/linked/package.json"; ln -s "$SANDBOX/elsewhere" "$H/linked/node_modules"
printf 'p4242\nfcwd\nn%s\n' "$H/running/src" > "$SANDBOX/lsof-out"

plan_record() { printf '%s\0%s\0%s\0%s\0%s\0%s\0' "Project folders" "$1" 4 1 true "" >> "$SANDBOX/plan.bin"; }
for p in good busy running late dryrun other; do plan_record "$H/$p/node_modules"; done
plan_record "$H/good/src"                                      # not a build folder
plan_record "$H/tracked/build"
plan_record "$H/wt/.claude/worktrees/w1/node_modules"
plan_record "$H/wt/.codex/worktrees/w2/node_modules"
plan_record "$H/Documents/docproj/node_modules"
plan_record "$H/linked/node_modules"
printf '%s\0%s\0%s\0%s\0%s\0%s\0' "App caches" "$H/asplan/node_modules" 4 1 true "" >> "$SANDBOX/plan.bin"
# a sidecar that claims a path the plan does not list changes nothing
printf '%s\0%s\0%s\0%s\0%s\0' "$H/other/src" 0 old "$H/other" yes > "$SANDBOX/plan.bin.meta"

approve() { : > "$SANDBOX/approved.bin"; local p; for p in "$@"; do printf '%s\0' "$p" >> "$SANDBOX/approved.bin"; done; }
allow() { : > "$SANDBOX/allow.bin"; local p; for p in "$@"; do printf '%s\0' "$p" >> "$SANDBOX/allow.bin"; done; }
run_apply() { /bin/bash "$APPLY" --plan "$SANDBOX/plan.bin" --approved "$SANDBOX/approved.bin" \
    --log "$SANDBOX/history.tsv" --jail "$H" "$@" > "$SANDBOX/apply.out" 2>&1 < /dev/null; }
said() { grep -qF "$1" "$SANDBOX/apply.out"; }
said_for() { grep -F "$1" "$SANDBOX/apply.out" | grep -qF "$2"; }

echo "without --projects:"
approve "$H/good/node_modules"
check "exits cleanly" run_apply
check "a Project folders item is not deleted by a plain apply" test -e "$H/good/node_modules/pkg/f"
check "and it says why" said_for "$H/good/node_modules" "Project folders"

echo "--projects, dry run:"
check "exits cleanly" run_apply --projects --dry-run
check "deletes nothing" test -e "$H/good/node_modules/pkg/f"
check "says it would delete" said "would-delete"

echo "--projects, a good one:"
allow
approve "$H/good/node_modules" "$H/dryrun/node_modules"
check "exits cleanly" run_apply --projects --allow-recent "$SANDBOX/allow.bin"
check "deletes an old node_modules" test ! -e "$H/good/node_modules"
check "leaves the project's own files" test -e "$H/good/src/app.js"
check "writes a history line" grep -qF "$H/good/node_modules" "$SANDBOX/history.tsv"

echo "--projects, the re-checks:"
approve "$H/busy/node_modules" "$H/running/node_modules" "$H/good/src" "$H/tracked/build" \
    "$H/wt/.claude/worktrees/w1/node_modules" "$H/wt/.codex/worktrees/w2/node_modules" \
    "$H/Documents/docproj/node_modules" "$H/linked/node_modules" "$H/other/src"
allow
check "exits cleanly" run_apply --projects --allow-recent "$SANDBOX/allow.bin"
check "keeps a project changed lately" test -e "$H/busy/node_modules/pkg/f"
check "says it is in use lately" said_for "$H/busy/node_modules" "in use lately"
check "keeps a project with a program running in it" test -e "$H/running/node_modules/pkg/f"
check "keeps a folder that is not a build folder" test -e "$H/good/src/app.js"
check "keeps a build folder that holds tracked files" test -e "$H/tracked/build/Main.java"
check "keeps a .claude worktree's node_modules" test -e "$H/wt/.claude/worktrees/w1/node_modules/x"
check "keeps a .codex worktree's node_modules" test -e "$H/wt/.codex/worktrees/w2/node_modules/x"
check "keeps a project in Documents" test -e "$H/Documents/docproj/node_modules/x"
check "keeps a linked node_modules and its target" test -e "$SANDBOX/elsewhere/data/f"
check "says why for tracked files" said_for "$H/tracked/build" "tracked by git"
check "says why for a worktree" said_for "$H/wt/.claude/worktrees/w1/node_modules" "agent worktree"
check "says why for a link" said_for "$H/linked/node_modules" "not a plain folder"
check "says why for a name that is not a build folder" said_for "$H/good/src" "not a build folder"
check "refuses a path only the sidecar names" said_for "$H/other/src" "not in the plan"

echo "--allow-recent:"
approve "$H/busy/node_modules" "$H/running/node_modules"
allow "$H/busy/node_modules" "$H/running/node_modules" "$H/other/node_modules"
check "exits cleanly" run_apply --projects --allow-recent "$SANDBOX/allow.bin"
check "deletes a recent one the user ticked on purpose" test ! -e "$H/busy/node_modules"
check "never deletes one with a program running in it" test -e "$H/running/node_modules/pkg/f"
check "says a program is running there" said_for "$H/running/node_modules" "running"
check "an allowed path that was not ticked is left alone" test -e "$H/other/node_modules/pkg/f"

echo "changed after the scan:"
approve "$H/late/node_modules"
allow
touch "$H/late/node_modules/pkg/f"                             # an install ran after the dry run
check "exits cleanly" run_apply --projects --allow-recent "$SANDBOX/allow.bin"
check "refuses a folder that became recent" test -e "$H/late/node_modules/pkg/f"

echo "when something cannot be told, --allow-recent does not override it:"
for p in lsofcase findcase; do mkproj "$p"; plan_record "$H/$p/node_modules"; done
approve "$H/lsofcase/node_modules"
allow "$H/lsofcase/node_modules"
touch "$SANDBOX/lsof-fail"
check "exits cleanly" run_apply --projects --allow-recent "$SANDBOX/allow.bin"
rm -f "$SANDBOX/lsof-fail"
check "a failing lsof keeps the folder" test -e "$H/lsofcase/node_modules/pkg/f"
check "and says it could not tell" said_for "$H/lsofcase/node_modules" "could not tell"
approve "$H/findcase/node_modules"
allow "$H/findcase/node_modules"
touch "$SANDBOX/find-fail"
check "exits cleanly" run_apply --projects --allow-recent "$SANDBOX/allow.bin"
rm -f "$SANDBOX/find-fail"
check "a date walk that fails keeps the folder" test -e "$H/findcase/node_modules/pkg/f"
check "and says it could not tell" said_for "$H/findcase/node_modules" "could not tell"

echo "the project's files, at any depth, and git's index:"
mkproj deepcase; mkdir -p "$H/deepcase/src/a/b/c/d"; echo x > "$H/deepcase/src/a/b/c/d/x.tsx"
mkproj idxcase; mkdir -p "$H/idxcase/.git"; echo idx > "$H/idxcase/.git/index"
old "$H/deepcase/src/a/b/c/d" "$H/deepcase/src/a/b/c" "$H/deepcase/src/a/b" "$H/deepcase/src/a" "$H/deepcase/src" "$H/deepcase" \
    "$H/idxcase/src/app.js" "$H/idxcase/src" "$H/idxcase"
touch "$H/deepcase/src/a/b/c/d/x.tsx"
plan_record "$H/deepcase/node_modules"; plan_record "$H/idxcase/node_modules"
approve "$H/deepcase/node_modules" "$H/idxcase/node_modules"
allow
check "exits cleanly" run_apply --projects --allow-recent "$SANDBOX/allow.bin"
check "an edit five folders down keeps the folder" test -e "$H/deepcase/node_modules/pkg/f"
check "a git index written lately keeps the folder" test -e "$H/idxcase/node_modules/pkg/f"

echo "the project-folder check on its own (no jail to fall back on):"
mkdir -p "$SANDBOX/outside-proj/node_modules/x"; echo '{}' > "$SANDBOX/outside-proj/package.json"
plan_record "$SANDBOX/outside-proj/node_modules"
approve "$SANDBOX/outside-proj/node_modules"
allow
/bin/bash "$APPLY" --plan "$SANDBOX/plan.bin" --approved "$SANDBOX/approved.bin" --projects --allow-recent "$SANDBOX/allow.bin" > "$SANDBOX/apply.out" 2>&1 < /dev/null
check "a project outside every root is kept" test -e "$SANDBOX/outside-proj/node_modules/x"
check "and says it is not inside a project folder" said_for "$SANDBOX/outside-proj/node_modules" "not inside a project folder"

echo "a plan from the Clean pane:"
approve "$H/asplan/node_modules"
check "exits cleanly" run_apply --projects
check "--projects refuses a record from another section" test -e "$H/asplan/node_modules/pkg/f"

echo "no prompts, no admin rights:"
check_not "never called sudo or osascript" grep -qsE '^(sudo|osascript)' "$SANDBOX/stub-calls.log"
check_not "never ran git except ls-files" grep -qsE '^git ' "$SANDBOX/stub-calls.log"
check_not "never tried rm outside the sandbox" grep -qsE '^rm ' "$SANDBOX/stub-calls.log"
[[ $T_FAILS -eq 0 ]] || { echo "--- apply.out"; tail -30 "$SANDBOX/apply.out"; }
finish
