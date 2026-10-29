#!/bin/bash
# Tiny standalone test harness for the engine.
# Every test runs inside a throwaway sandbox: a fake HOME, its own TMPDIR, and stubs that make
# osascript, sudo, mdfind, open, launchctl, tmutil, pkill and killall fail, so a test can never
# prompt, gain admin rights, search the real disk, or touch the user's real files.

T_PASSES=0
T_FAILS=0
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

make_sandbox() {
    SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/captain-levi-test.XXXXXX")"
    mkdir -p "$SANDBOX/home" "$SANDBOX/stubs" "$SANDBOX/tmp"
    local cmd
    for cmd in osascript sudo mdfind open launchctl tmutil pkill killall shortcuts curl wget git brew; do
        printf '#!/bin/sh\necho "%s $*" >> "%s/stub-calls.log"\necho "test stub: %s is blocked" >&2\nexit 1\n' \
            "$cmd" "$SANDBOX" "$cmd" > "$SANDBOX/stubs/$cmd"
        chmod +x "$SANDBOX/stubs/$cmd"
    done
    # rm itself only works inside the sandbox (Mole calls it as `command rm`, which this catches).
    cat > "$SANDBOX/stubs/rm" << STUB
#!/bin/sh
for arg in "\$@"; do
    case "\$arg" in
        -*) ;;
        "$SANDBOX"/*) ;;
        *) echo "rm \$*" >> "$SANDBOX/stub-calls.log"; echo "test stub: rm outside the sandbox refused" >&2; exit 1 ;;
    esac
done
exec /bin/rm "\$@"
STUB
    chmod +x "$SANDBOX/stubs/rm"
    export HOME="$SANDBOX/home"
    export TMPDIR="$SANDBOX/tmp"
    export PATH="$SANDBOX/stubs:/usr/bin:/bin:/usr/sbin:/sbin"
    export MOLE_TEST_NO_AUTH=1 NO_COLOR=1
    unset SUDO_USER MOLE_DRY_RUN
}

cleanup_sandbox() {
    case "${SANDBOX:-}" in
        */captain-levi-test.*) /bin/rm -rf "$SANDBOX" ;;
    esac
}

ok() {
    T_PASSES=$((T_PASSES + 1))
    printf '  ok    %s\n' "$1"
}

fail() {
    T_FAILS=$((T_FAILS + 1))
    printf '  FAIL  %s\n' "$1"
}

check() {
    # check "description" command...: passes when the command succeeds
    local what="$1"
    shift
    if "$@"; then ok "$what"; else fail "$what"; fi
}

check_not() {
    local what="$1"
    shift
    if "$@"; then fail "$what"; else ok "$what"; fi
}

finish() {
    printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$T_PASSES" "$T_FAILS"
    [[ $T_FAILS -eq 0 ]]
}
