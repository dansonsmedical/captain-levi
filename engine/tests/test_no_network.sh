#!/bin/bash
# this copy never updates itself or calls the internet, and its risky commands are switched off.
source "$(dirname "$0")/lib.sh"
make_sandbox
trap cleanup_sandbox EXIT

mole() { /bin/bash "$REPO_ROOT/mole" "$@" > "$SANDBOX/mole.out" 2>&1 < /dev/null; }

echo "no menu, no update check:"
check "plain mole shows help and exits" mole
check "its output is the help text" grep -qi "usage\|clean" "$SANDBOX/mole.out"

echo "switched-off commands:"
for cmd in update remove completion touchid optimize uninstall installer purge; do
    check_not "mole $cmd refuses" mole "$cmd"
done
check "the refusal says why" grep -q "switched off in this copy" "$SANDBOX/mole.out"

echo "nothing reached the network:"
check_not "no curl, wget, git or brew call" grep -qsE '^(curl|wget|git|brew) ' "$SANDBOX/stub-calls.log"
finish
