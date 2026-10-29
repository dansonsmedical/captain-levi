#!/bin/bash
# Made-up app, made-up use, preview, tick, Trash, and look again. Never launches an app.
source "$(dirname "$0")/lib.sh"
make_sandbox
uninstall_cleanup() {
    [[ ! -d "$HOME/Library/Application Support/Unreadable" ]] || chmod 700 "$HOME/Library/Application Support/Unreadable"
    [[ ! -d "$HOME/Applications/Unreadable" ]] || chmod 700 "$HOME/Applications/Unreadable"
    cleanup_sandbox
}
trap uninstall_cleanup EXIT
H="$HOME"
STAGE="$SANDBOX/engine"
mkdir -p "$STAGE/bin" "$STAGE/engine" "$STAGE/scratch" "$H/Applications" "$H/.Trash" "$SANDBOX/extra"
cp -R "$REPO_ROOT/lib" "$STAGE/lib"
cp "$REPO_ROOT/engine/apply.sh" "$REPO_ROOT/engine/uninstall_lib.sh" "$STAGE/engine/"
cp "$REPO_ROOT/bin/uninstall_scan.sh" "$STAGE/bin/"
check 'fixed roots and pure app root checks' /bin/bash -c '
    ENGINE_ROOT="$1"; source "$1/engine/uninstall_lib.sh"
    roots=$(mc_u_apps_roots)
    grep -qxF /Applications <<< "$roots" &&
    grep -qxF "$HOME/Applications" <<< "$roots" &&
    mc_u_app_root /Applications/X.app && ! mc_u_app_root /tmp/X.app
' bash "$STAGE"
# Exercise the real policy against fixture-relative paths: an outer agent
# worktree must not turn every made-up path into protected agent state.
# Both HOME and the tool root are translated too, preserving all deny rules.
cat >> "$STAGE/lib/core/never_delete.sh" <<'STUB'
eval "$(declare -f mac_cleaner_never_delete_path | sed '1s/mac_cleaner_never_delete_path/mc_fixture_never_delete/')"
mac_cleaner_never_delete_path() (
    local fixture_prefix="${HOME%/home}"
    HOME="/fixture/home"
    MAC_CLEANER_ROOT="/fixture/engine"
    mc_fixture_never_delete "/fixture${1#"$fixture_prefix"}"
)
STUB
cat >> "$STAGE/engine/uninstall_lib.sh" <<'STUB'
# The test inventory is entirely inside this sandbox.
mc_u_apps_roots() { printf '%s\n' "$HOME/Applications"; }
STUB
export TMPDIR="$STAGE/scratch"
# Only the staged discovery's system half is replaced. User discovery and all guards are real.
cat >> "$STAGE/lib/core/app_protection.sh" <<'STUB'
find_app_system_files() { cat "$HOME/system-fixtures"; }
find_app_receipt_files() { cat "$HOME/receipt-fixtures"; }
STUB
cat >> "$STAGE/lib/core/app_protection.sh" <<'STUB'
find_app_system_files() { cat "$HOME/system-fixtures"; [[ ! -f "$HOME/optional-fail" ]]; }
find_app_receipt_files() { cat "$HOME/receipt-fixtures"; [[ ! -f "$HOME/optional-fail" ]]; }
find_vendor_nested_app_paths() { echo called >> "$HOME/vendor-calls"; }
STUB
cat > "$SANDBOX/stubs/pgrep" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/pgrep-calls"
[ ! -f "$HOME/helper-running" ] || case "$*" in *'/Contents/MacOS/'*) exit 1;; *) exit 0;; esac
[ -f "$HOME/running" ] && exit 0
exit 1
STUB
cat > "$SANDBOX/stubs/lsof" <<'STUB'
#!/bin/sh
[ ! -f "$HOME/lsof-unknown" ] || exit 2
printf 'p1\nfcwd\nn%s\n' "$(pwd -P)"
STUB
cat > "$SANDBOX/stubs/du" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/du-calls"
exec /usr/bin/du "$@"
STUB
chmod +x "$SANDBOX/stubs/du"
chmod +x "$SANDBOX/stubs/pgrep" "$SANDBOX/stubs/lsof"
# The restricted host cannot run Apple's Perl timeout backend. These tiny,
# finite fixture probes need no watchdog (and never spawn a killer process).
cat > "$SANDBOX/stubs/gtimeout" <<'STUB'
#!/bin/sh
shift
printf '%s\n' "$*" >> "$HOME/timeout-calls"
case "$1" in find|lsof|plutil|ps) exec "$@";; *) exit 125;; esac
STUB
chmod +x "$SANDBOX/stubs/gtimeout"
cat > "$SANDBOX/stubs/ps" <<'STUB'
#!/bin/sh
case "$*" in
    *pid,ppid,comm,args*) printf 'PID PPID COMM ARGS\n1 0 fixture fixture\n';;
    *) printf '1 fixture\n';;
esac
STUB
chmod +x "$SANDBOX/stubs/ps"
mkapp() {
    mkdir -p "$1/Contents/MacOS"
    cat > "$1/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleDisplayName</key><string>$3</string>
<key>CFBundleShortVersionString</key><string>1.2.3</string>
<key>CFBundleExecutable</key><string>FixtureBinary</string>
</dict></plist>
PLIST
    echo 'plain fixture, never executed' > "$1/Contents/MacOS/FixtureBinary"
}
APP="$H/Applications/Orchard Beta.app"
ID=org.fixture.orchard.beta
mkapp "$APP" "$ID" 'Orchard Beta'
mkapp "$H/Applications/Apple.app" com.apple.fixture Apple
mkapp "$H/Applications/Captain Levi.app" app.captainlevi.cleaner 'Captain Levi'
mkapp "$H/Applications/Eligible.app" org.fixture.eligible Eligible
mkapp "$SANDBOX/extra/Other.app" org.fixture.other Other
mkapp "$H/Applications/Nested/Hidden.app" org.fixture.hidden Hidden
SCAN="$STAGE/bin/uninstall_scan.sh"
APPLY="$STAGE/engine/apply.sh"
PLAN="$SANDBOX/plan.bin"
APPROVED="$SANDBOX/approved.bin"
scan() { /bin/bash "$SCAN" --apps-root "$H/Applications" --apps-root "$SANDBOX/extra" "$@"; }
preview() { scan --app "$APP" --plan-out "$PLAN" > "$SANDBOX/preview.json"; }
apply() { /bin/bash "$APPLY" --uninstall --plan "$PLAN" --approved "$APPROVED" --jail "$H" --log "$SANDBOX/history" "$@" > "$SANDBOX/apply.out" 2>&1; }
said() { grep -qF "$1" "$SANDBOX/apply.out"; }
record() { printf '%s\0%s\0%s\0%s\0%s\0%s\0' "$1" "$2" 4 1 true '' >> "$PLAN"; }
approve() { : > "$APPROVED"; local p; for p in "$@"; do printf '%s\0' "$p" >> "$APPROVED"; done; }
plan_has() { tr '\0' '\n' < "$PLAN" | grep -qxF "$1"; }
section_is() {
    local section path size count known ancestor
    while IFS= read -r -d '' section && IFS= read -r -d '' path &&
        IFS= read -r -d '' size && IFS= read -r -d '' count &&
        IFS= read -r -d '' known && IFS= read -r -d '' ancestor; do
        [[ "$path" != "$1" ]] || { [[ "$section" == "$2" ]]; return; }
    done < "$PLAN"
    return 1
}
fixtures_intact() {
    local p
    while IFS= read -r p; do
        case "$p" in
            */LaunchAgents/*) grep -qF "$APP/Contents/MacOS/FixtureBinary" "$p" || return 1;;
            *.plist) grep -qx used "$p" || return 1;;
            *) grep -qx used "$p/data" || return 1;;
        esac
    done < "$SANDBOX/tied"
}
json_valid() { plutil -convert json -o /dev/null -- "$1"; }
scan --list > "$SANDBOX/list.json"
check 'lists sandbox apps' json_valid "$SANDBOX/list.json"
check 'listing uses one array line' test "$(wc -l < "$SANDBOX/list.json" | tr -d ' ')" = 1
check 'listing contains app identity and version' grep -qF '"version":"1.2.3"' "$SANDBOX/list.json"
check 'repeated roots replace defaults' grep -qF 'org.fixture.other' "$SANDBOX/list.json"
check_not 'excludes Apple, itself and nested bundles' grep -qE 'com.apple.fixture|app.captainlevi.cleaner|org.fixture.hidden' "$SANDBOX/list.json"
# Represent using the app by writing only plain made-up data.
: > "$SANDBOX/tied"
for sub in 'Application Support' Caches Logs Preferences 'Saved Application State' Containers 'Group Containers' HTTPStorages WebKit LaunchAgents; do
    p="$H/Library/$sub/$ID"
    case "$sub" in Preferences | LaunchAgents) p="$p.plist";; 'Saved Application State') p="$p.savedState";; esac
    if [[ "$p" == *.plist ]]; then
        mkdir -p "${p%/*}"
        if [[ "$sub" == LaunchAgents ]]; then
            printf '<plist version="1.0"><dict><key>Label</key><string>%s</string><key>Program</key><string>%s</string></dict></plist>\n' "$ID" "$APP/Contents/MacOS/FixtureBinary" > "$p"
        else echo used > "$p"; fi
    else mkdir -p "$p"; echo used > "$p/data"; fi
    echo "$p" >> "$SANDBOX/tied"
done
mkdir -p "$H/Library/Application Support/Orchard" "$H/Library/Application Support/Orchard Beta" "$H/Library/Caches/unrelated"
echo shared > "$H/Library/Application Support/Orchard/data"
echo similar > "$H/Library/Application Support/Orchard Beta/data"
echo unrelated > "$H/Library/Caches/unrelated/data"
printf '/Library/LaunchDaemons/%s.plist\n/Library/PrivilegedHelperTools/%s\n/usr/local/lib/%s\n' "$ID" "$ID" "$ID" > "$H/system-fixtures"
printf '/private/var/db/receipts/%s.bom\n' "$ID" > "$H/receipt-fixtures"
check 'preview succeeds' preview
check 'preview is JSON' json_valid "$SANDBOX/preview.json"
all_tied() { local p; while IFS= read -r p; do plan_has "$p" || return 1; done < "$SANDBOX/tied"; }
check 'plans every tied fixture' all_tied
while IFS= read -r p; do
    case "$p" in
        */Preferences/* | */Saved\ Application\ State/*) expected='Settings and saved state';;
        */Caches/* | */Logs/*) expected='Caches and logs';;
        */LaunchAgents/*) expected='Helpers and launch agents';;
        *) expected='Its data';;
    esac
    check "classifies $p" section_is "$p" "$expected"
done < "$SANDBOX/tied"
check 'classifies app' section_is "$APP" 'The app'
cp "$PLAN" "$SANDBOX/hostile-original"
record 'Caches and logs' "$H/Library/Caches/unrelated"
approve "$H/Library/Caches/unrelated"; apply --dry-run
check 'relabelled untied cache reason' said 'not tied exclusively'
scan --check "$ID" > "$SANDBOX/hostile-check.json"
check_not 'forged plan path never saved as tied' grep -qF "$H/Library/Caches/unrelated" "$SANDBOX/hostile-check.json"
cp "$SANDBOX/hostile-original" "$PLAN"
for hostile in "$H/Applications/Parent.app/Contents/Library/LoginItems/Helper.app" "$H/Tools/Loose.app"; do
    mkapp "$hostile" org.fixture.hostile Hostile
    for hostile_root in "$H" ''; do
        /bin/bash "$SCAN" --apps-root "$hostile_root" --app "$hostile" --plan-out "$PLAN" > "$SANDBOX/hostile.json"
        approve "$hostile"; apply --dry-run
        check "app root refusal reason: $hostile ($hostile_root)" said 'protected or outside uninstall roots'
        check "hostile bundle survives: $hostile ($hostile_root)" test -f "$hostile/Contents/Info.plist"
        check_not "hostile bundle never approved: $hostile ($hostile_root)" said 'would-trash'
    done
done
cp "$SANDBOX/hostile-original" "$PLAN"
cat >> "$STAGE/lib/core/app_protection.sh" <<'STUB'
eval "$(declare -f find_app_files | sed '1s/find_app_files/mc_fixture_find_app_files/')"
find_app_files() { [[ ! -f "$HOME/required-fail" ]] || return 5; mc_fixture_find_app_files "$@"; }
STUB
# The hostile parent has no identity; keep it outside subsequent app inventories.
mv "$H/Applications/Parent.app" "$SANDBOX/hostile-parent.app"
touch "$H/required-fail"
state_token=$(printf '%s' "$APP" | cksum | awk '{print $1}')
cp "$TMPDIR/mac-cleaner-uninstall/$state_token.plan" "$SANDBOX/saved-before-failure"
cp "$TMPDIR/mac-cleaner-uninstall/$state_token.state" "$SANDBOX/state-before-failure"
approve "$APP" "$H/Library/Caches/$ID"; apply --dry-run
check 'apply discovery failure reason' said 'user discovery incomplete'
check_not 'failed discovery permits no movement' said 'would-trash'
check 'failed discovery preserves cache' test -f "$H/Library/Caches/$ID/data"
approve "$APP"; apply
check 'failed real discovery preserves saved plan' cmp "$SANDBOX/saved-before-failure" "$TMPDIR/mac-cleaner-uninstall/$state_token.plan"
check 'failed discovery preserves saved identity' cmp "$SANDBOX/state-before-failure" "$TMPDIR/mac-cleaner-uninstall/$state_token.state"
rm "$H/required-fail"
mkdir -p "$H/Applications/Unreadable"
chmod 000 "$H/Applications/Unreadable"
check 'unreadable inventory folder permits preview' preview
approve "$APP"; apply --dry-run
check 'unreadable inventory folder permits apply' said 'would-trash'
chmod 700 "$H/Applications/Unreadable"
newline_path="$H/Library/Caches/$ID"$'\n'"unusual"
mkdir -p "$newline_path"
preview
check 'newline leftover reported as uninspected' grep -qF 'uninspected path:' "$SANDBOX/preview.json"
rmdir "$newline_path"
odd_path="$H/Library/Caches/odd"$'\001\t'
mkdir "$odd_path"
check 'control character scan succeeds' preview
json_valid() {
    # Apple's lint rejects JSON, and XML plists cannot represent JSON null.
    # JSON conversion parses the complete input while preserving null values.
    plutil -convert json -o /dev/null "$SANDBOX/preview.json"
}
check 'control character output is valid JSON' json_valid
check 'control character scan retains ordinary items' section_is "$H/Library/Caches/$ID" 'Caches and logs'
rmdir "$odd_path"
check_not 'custom roots require test switch' env MOLE_TEST_NO_AUTH= /bin/bash "$SCAN" --apps-root "$H/Applications" --list > "$SANDBOX/no-switch.out" 2>&1
check 'custom roots refusal explains switch' grep -qF 'test-only' "$SANDBOX/no-switch.out"
preview
# Every uninstall section must be gated even when the item is otherwise deletable.
cp "$PLAN" "$SANDBOX/section-plan"
for sec in 'The app' 'Settings and saved state' 'Caches and logs' 'Its data' 'Helpers and launch agents' 'Not tied to this app'; do
    : > "$PLAN"; record "$sec" "$H/Library/Caches/$ID"
    approve "$H/Library/Caches/$ID"
    /bin/bash "$APPLY" --plan "$PLAN" --approved "$APPROVED" --jail "$H" > "$SANDBOX/apply.out"
    check "section gate: $sec" said 'uninstall items are moved to the Trash only from the Uninstall pane'
    check "section survives: $sec" test -f "$H/Library/Caches/$ID/data"
done
cp "$SANDBOX/section-plan" "$PLAN"
container_unknown() {
    local sec p kb count known ancestor
    while IFS= read -r -d '' sec && IFS= read -r -d '' p && IFS= read -r -d '' kb &&
        IFS= read -r -d '' count && IFS= read -r -d '' known && IFS= read -r -d '' ancestor; do
        [[ "$p" != "$H/Library/Containers/$ID" ]] || { [[ "$known" == false && "$kb" == 0 ]]; return; }
    done < "$PLAN"
    return 1
}
check 'container size stays unknown' container_unknown
check_not 'du never enters containers' grep -E '/Library/(Containers|Group Containers)/' "$H/du-calls"
# Unknown identities are reported without demoting unrelated apps' data.
mkdir -p "$H/Applications/Unknown.app"
mkdir -p "$H/Library/Containers/$ID.unknown"
check 'unknown wrapper does not block preview' preview
check 'unknown bundle demotes shared prefix' section_is "$H/Library/Containers/$ID.unknown" 'Not tied to this app'
check 'unknown wrapper identifies culprit' grep -qF "$H/Applications/Unknown.app" "$SANDBOX/preview.json"
approve "$APP"; apply --dry-run
check 'unknown wrapper does not block apply' said 'would-trash'
rmdir "$H/Applications/Unknown.app"
rmdir "$H/Library/Containers/$ID.unknown"
mkapp "$H/Applications/Unreadable.app" "$ID.hidden" Hidden
chmod 000 "$H/Applications/Unreadable.app/Contents/Info.plist"
mkdir -p "$H/Library/Containers/$ID.hidden"
check 'unreadable bundle permits preview' preview
check 'unreadable bundle demotes shared prefix' section_is "$H/Library/Containers/$ID.hidden" 'Not tied to this app'
chmod 600 "$H/Applications/Unreadable.app/Contents/Info.plist"
mv "$H/Applications/Unreadable.app" "$SANDBOX/Unreadable.app"
rmdir "$H/Library/Containers/$ID.hidden"
mkapp "$H/Applications/iPad.app/Wrapper/Inside.app" org.fixture.ipad iPad
mv "$H/Applications/iPad.app/Wrapper/Inside.app/Contents/Info.plist" "$H/Applications/iPad.app/Wrapper/Inside.app/Info.plist"
preview
check 'wrapper ID inspection preserves exclusive ties' section_is "$H/Library/Caches/$ID" 'Caches and logs'
touch "$H/optional-fail"
check 'optional failures permit preview' preview
check 'optional failures remain visible in JSON' grep -qF 'system discovery incomplete' "$SANDBOX/preview.json"
check 'optional errors are separate JSON items' grep -qF '"system discovery incomplete","receipt discovery incomplete"' "$SANDBOX/preview.json"
approve "$APP"; apply --dry-run
check 'optional failures permit apply' said 'would-trash'
rm "$H/optional-fail"
preview
# Another product's ID must dominate the shorter target ID in all derived roots.
mkapp "$H/Applications/Chrome.app" org.fixture.chrome Chrome
mkapp "$H/Applications/Utilities/Canary.app" org.fixture.chrome.canary Canary
mkapp "$H/Applications/cask/version/Deep.app" org.fixture.chrome.deep Deep
mkdir -p "$H/Library/Containers/org.fixture.chrome.deep"
for sub in Containers 'Group Containers' 'Application Scripts'; do
    mkdir -p "$H/Library/$sub/org.fixture.chrome.canary"
done
cp "$PLAN" "$SANDBOX/before-chrome"
scan --app "$H/Applications/Chrome.app" --plan-out "$PLAN" > "$SANDBOX/chrome.json"
check 'depth three longer ID demotes data' section_is "$H/Library/Containers/org.fixture.chrome.deep" 'Not tied to this app'
mkapp "$H/Applications/cask/version/Copy.app" org.fixture.chrome Chrome
scan --app "$H/Applications/Chrome.app" --plan-out "$PLAN" > "$SANDBOX/deep-copy.json"
check 'depth three same ID copy is seen' grep -q '"tied":1,' "$SANDBOX/deep-copy.json"
mv "$H/Applications/cask/version/Copy.app" "$SANDBOX/deep-copy.app"
for sub in Containers 'Group Containers' 'Application Scripts'; do
    check "other installed ID demoted: $sub" section_is "$H/Library/$sub/org.fixture.chrome.canary" 'Not tied to this app'
done
scan --app "$H/Applications/Utilities/Canary.app" --plan-out "$PLAN" > "$SANDBOX/canary.json"
for sub in Containers 'Group Containers' 'Application Scripts'; do
    check "longest own ID stays tied: $sub" section_is "$H/Library/$sub/org.fixture.chrome.canary" 'Its data'
done
cp "$SANDBOX/before-chrome" "$PLAN"
# The policy functions consume their normal data inputs, with uninstall mode unset.
sed 's/readonly OFFICIAL_UNINSTALLER_RULES=(/readonly OFFICIAL_UNINSTALLER_RULES=( "Fixture Security|org.fixture.security|fixture-security"/' \
    "$STAGE/lib/core/app_protection_data.sh" > "$SANDBOX/protection-data"
cp "$SANDBOX/protection-data" "$STAGE/lib/core/app_protection_data.sh"
mkapp "$H/Applications/Security.app" org.fixture.security Security
check_not 'vendor uninstaller refuses preview' scan --app "$H/Applications/Security.app" --plan-out "$SANDBOX/security-plan" > "$SANDBOX/security.out" 2>&1
check 'vendor refusal reason' grep -qF "use the vendor's own uninstaller" "$SANDBOX/security.out"
cp "$PLAN" "$SANDBOX/pre-security-plan"
: > "$PLAN"; record 'The app' "$H/Applications/Security.app"
mkdir -p "$H/Library/Caches/org.fixture.security"
record 'Caches and logs' "$H/Library/Caches/org.fixture.security"
approve "$H/Library/Caches/org.fixture.security"; apply
check 'vendor app refuses apply' said "use the vendor's own uninstaller"
cp "$SANDBOX/pre-security-plan" "$PLAN"
scan --list > "$SANDBOX/vendor-list"
check_not 'vendor app excluded from list' grep -qF org.fixture.security "$SANDBOX/vendor-list"
# Real permission errors in optional name discovery must not poison required IDs.
cat >> "$STAGE/lib/core/app_protection.sh" <<'STUB'
eval "$(declare -f should_protect_from_uninstall | sed '1s/should_protect_from_uninstall/mc_fixture_should_protect/')"
should_protect_from_uninstall() {
    [[ "$1" != org.fixture.protected ]] || return 0
    mc_fixture_should_protect "$@"
}
STUB
mkapp "$H/Applications/Protected.app" org.fixture.protected Protected
check_not 'should_protect app refuses preview' scan --app "$H/Applications/Protected.app" --plan-out "$SANDBOX/protected-plan" > "$SANDBOX/protected.out" 2>&1
check 'should_protect refusal gives protected app reason' grep -qF 'protected app' "$SANDBOX/protected.out"
mkdir -p "$H/Library/Application Support/Unreadable"
chmod 000 "$H/Library/Application Support/Unreadable"
check 'unreadable optional folder permits preview' preview
approve "$APP"; apply --dry-run
check 'unreadable optional folder permits apply' said 'would-trash'
chmod 700 "$H/Library/Application Support/Unreadable"
# A missing lsof view keeps SQLite caches without invoking sudo.
touch "$H/Library/Caches/$ID/Cache.db" "$H/lsof-unknown"
approve "$H/Library/Caches/$ID"; MOLE_TEST_NO_AUTH= apply --dry-run
check 'unknown SQLite handle keeps cache with reason' said 'protected or outside uninstall roots'
check 'unknown SQLite handle explains uncertainty' said 'could not be proved closed'
check 'unknown SQLite cache remains' test -f "$H/Library/Caches/$ID/Cache.db"
rm "$H/lsof-unknown" "$H/Library/Caches/$ID/Cache.db"
mv "$H/Library/Containers/$ID/data" "$SANDBOX/container-data"
mkdir -p "$H/Library/Containers/$ID/Data/Library/Caches"
touch "$H/Library/Containers/$ID/Data/Library/Caches/Cache.db" "$H/lsof-unknown"
cp "$PLAN" "$SANDBOX/container-plan"
record 'Caches and logs' "$H/Library/Containers/$ID/Data/Library/Caches"
approve "$H/Library/Containers/$ID/Data/Library/Caches"; MOLE_TEST_NO_AUTH= apply --dry-run
check 'container SQLite handle uncertainty reason' said 'could not be proved closed'
check 'container SQLite cache survives uncertainty' test -f "$H/Library/Containers/$ID/Data/Library/Caches/Cache.db"
rm "$H/lsof-unknown" "$H/Library/Containers/$ID/Data/Library/Caches/Cache.db"
rmdir "$H/Library/Containers/$ID/Data/Library/Caches" "$H/Library/Containers/$ID/Data/Library" "$H/Library/Containers/$ID/Data"
mv "$SANDBOX/container-data" "$H/Library/Containers/$ID/data"
cp "$SANDBOX/container-plan" "$PLAN"
check_not 'uninstall never asks sudo for lsof' grep -qs '^sudo ' "$SANDBOX/stub-calls.log"
check_not 'timeout never receives sudo' grep -qs 'sudo' "$H/timeout-calls"
check 'state accepts TMPDIR outside engine' env TMPDIR="$SANDBOX/tmp" /bin/bash "$SCAN" --apps-root "$H/Applications" --app "$APP" --plan-out "$SANDBOX/external-plan" > "$SANDBOX/external.json"
mkdir "$SANDBOX/unsafe-tmp"; chmod 777 "$SANDBOX/unsafe-tmp"
check_not 'state refuses world writable TMPDIR' env TMPDIR="$SANDBOX/unsafe-tmp" /bin/bash "$SCAN" --apps-root "$H/Applications" --app "$APP" --plan-out "$SANDBOX/unsafe-plan" > "$SANDBOX/unsafe.json"
for name in Orchard 'Orchard Beta'; do
    check "classifies name-only $name" section_is "$H/Library/Application Support/$name" 'Not tied to this app'
done
# Empty-name discovery must not authorize vendor-wide heuristic leftovers.
mkapp "$H/Applications/DevEco.app" org.fixture.huawei.deveco DevEco
mkdir -p "$H/Library/Caches/Huawei"
echo shared-vendor > "$H/Library/Caches/Huawei/data"
scan --app "$H/Applications/DevEco.app" --plan-out "$SANDBOX/vendor-plan" > "$SANDBOX/vendor.json"
cp "$PLAN" "$SANDBOX/orchard-plan"; cp "$SANDBOX/vendor-plan" "$PLAN"
check 'vendor heuristic stays name-only' section_is "$H/Library/Caches/Huawei" 'Not tied to this app'
cp "$SANDBOX/orchard-plan" "$PLAN"
plan_shape() {
    tr '\0' '\n' < "$PLAN" | awk 'NR%6==2 {if(seen[$0]++) exit 1} END {if(NR%6) exit 1}'
}
check 'six fields and no duplicate paths' plan_shape
check 'separates name-only and shared paths' plan_has 'Not tied to this app'
check 'includes shortened vendor folder only for review' plan_has "$H/Library/Application Support/Orchard"
check 'lists system remnants without approving them' grep -qF '/Library/LaunchDaemons/' "$SANDBOX/preview.json"
check 'reports receipts' grep -qF '/private/var/db/receipts/' "$SANDBOX/preview.json"
check_not 'system paths never enter removable plan' plan_has "/usr/local/lib/$ID"
# Another installed copy demotes its shared data. Remove only the fixture copy after checking.
mkapp "$H/Applications/Copy.app" "$ID" 'Orchard Copy'
check 'shared-copy preview succeeds' preview
check 'shared-copy data starts unticked' grep -q '"tied":1,' "$SANDBOX/preview.json"
cp "$H/Applications/Copy.app/Contents/MacOS/FixtureBinary" "$SANDBOX/copy-before"
cp -R "$H/Applications/Copy.app" "$SANDBOX/copy-preserved.app"
approve "$H/Library/Caches/$ID" "$APP"
check 'attempts uninstall while second copy remains installed' apply
check 'uninstalls selected app while second copy remains' test ! -e "$APP"
check 'second copy preserves shared fixtures' fixtures_intact
check 'second copy remains installed' cmp "$SANDBOX/copy-before" "$H/Applications/Copy.app/Contents/MacOS/FixtureBinary"
mkapp "$APP" "$ID" 'Orchard Beta'
# Move this fixture out of the installed inventory; do not uninstall it.
mv "$H/Applications/Copy.app" "$SANDBOX/Copy.app"
preview
cp "$PLAN" "$SANDBOX/original-plan"
# Unapproved and protected tied paths must stay visible in rescan.
mkdir -p "$H/Library/Mail/$ID"
echo protected > "$H/Library/Mail/$ID/data"
record 'Its data' "$H/Library/Mail/$ID"
approve "$APP" "$H/Library/Mail/$ID"
while IFS= read -r p; do printf '%s\0' "$p" >> "$APPROVED"; done < "$SANDBOX/tied"
echo old > "$H/.Trash/$ID"
cp "$TMPDIR/mac-cleaner-uninstall/$state_token.plan" "$SANDBOX/saved-before-dry"
cp "$TMPDIR/mac-cleaner-uninstall/$state_token.state" "$SANDBOX/state-before-dry"
check 'dry run changes nothing' apply --dry-run
check 'dry run preserves saved plan' cmp "$SANDBOX/saved-before-dry" "$TMPDIR/mac-cleaner-uninstall/$state_token.plan"
check 'dry run preserves saved identity' cmp "$SANDBOX/state-before-dry" "$TMPDIR/mac-cleaner-uninstall/$state_token.state"
check 'Mail refused at apply with reason' said 'on the never-delete list'
check 'Mail never enters MC_TIED' /bin/bash -c '
    ENGINE_ROOT="$1"; source "$1/engine/uninstall_lib.sh"
    plan_file="$2"; mc_u_state; mc_u_identity "$3"
    MC_APPS_ROOTS=("$HOME/Applications"); mc_u_discover
    ! grep -qxF "$HOME/Library/Mail/$MC_ID" <<< "$MC_TIED"
' bash "$STAGE" "$PLAN" "$APP"
check 'dry run retains app' test -f "$APP/Contents/Info.plist"
check 'dry run retains fixtures' all_tied
check 'dry run preserves fixture contents' fixtures_intact
check 'dry run preserves executable contents' grep -qx 'plain fixture, never executed' "$APP/Contents/MacOS/FixtureBinary"
check 'dry run emits would-trash history' grep -q 'would-trash' "$SANDBOX/history"
check 'dry run preserves existing Trash content' grep -qx old "$H/.Trash/$ID"
# Put the app record last and prove preflight refuses before the first data movement.
tr '\0' '\n' < "$PLAN" | tail -n +7 | tr '\n' '\0' > "$SANDBOX/reordered"
record_app_last() { printf '%s\0%s\0%s\0%s\0%s\0%s\0' 'The app' "$APP" 4 1 true '' >> "$SANDBOX/reordered"; }
record_app_last
cp "$PLAN" "$SANDBOX/before-reorder"; cp "$SANDBOX/reordered" "$PLAN"
approve "$H/Library/Caches/$ID" "$APP"
touch "$H/running"
apply
check 'refuses running apps before moving anything' said 'quit it first'
check 'running app data stays' test -f "$H/Library/Caches/$ID/data"
check 'running refusal preserves all fixture contents' fixtures_intact
check 'checks the bundle executable' grep -qF 'Orchard Beta\.app/' "$H/pgrep-calls"
rm "$H/running"; cp "$SANDBOX/before-reorder" "$PLAN"
touch "$H/helper-running"
apply
check 'login item stops movement' said 'quit it first'
check 'login item preserves data' test -f "$H/Library/Caches/$ID/data"
rm "$H/helper-running"
# These paths are ID-tied; refusal must come from root/protection checks.
cp "$PLAN" "$SANDBOX/guard-plan"
mv "$H/Library/Application Support/$ID" "$SANDBOX/support"
ln -s "$SANDBOX/support" "$H/Library/Application Support/$ID"
approve "$H/Library/Application Support/$ID"; apply
check 'tied leaf symlink reason' said 'protected or outside uninstall roots'
check 'leaf link guard is reached' said 'symbolic link'
check 'leaf target survives' test -f "$SANDBOX/support/data"
rm "$H/Library/Application Support/$ID"
mv "$SANDBOX/support" "$H/Library/Application Support/$ID"
mv "$H/Library/Application Support" "$SANDBOX/support-parent"
ln -s "$SANDBOX/support-parent" "$H/Library/Application Support"
approve "$H/Library/Application Support/$ID"; apply
check 'tied linked parent reason' said 'protected or outside uninstall roots'
check 'ancestor link guard is reached' said 'linked ancestor'
rm "$H/Library/Application Support"
mv "$SANDBOX/support-parent" "$H/Library/Application Support"
approve "$H/Library/Mail/$ID"; MOLE_UNINSTALL_MODE=1 apply
check 'tied never-delete reason despite uninstall environment' said 'protected or outside uninstall roots'
check 'never-delete guard is reached' said 'on the never-delete list'
cp "$SANDBOX/guard-plan" "$PLAN"
cp "$PLAN" "$SANDBOX/pre-system-plan"
: > "$PLAN"; record 'The app' "$H/Applications/Apple.app"
mkdir -p "$H/Library/Caches/com.apple.fixture"
record 'Caches and logs' "$H/Library/Caches/com.apple.fixture"
approve "$H/Library/Caches/com.apple.fixture"; apply
check 'system app with its own tied cache refusal reason' said 'app identity is unavailable or protected'
check 'system tied cache survives' test -d "$H/Library/Caches/com.apple.fixture"
cp "$SANDBOX/pre-system-plan" "$PLAN"
mkapp "$H/Applications/Password Fixture.app" com.bitwarden.fixture 'Password Fixture'
mkdir -p "$H/Library/Application Support/com.bitwarden.fixture"
cp "$PLAN" "$SANDBOX/pre-data-plan"
scan --app "$H/Applications/Password Fixture.app" --plan-out "$PLAN" > "$SANDBOX/data.json"
check 'data-protected fixture is ID tied' section_is "$H/Library/Application Support/com.bitwarden.fixture" 'Its data'
approve "$H/Library/Application Support/com.bitwarden.fixture"
MOLE_UNINSTALL_MODE=1 apply
check 'environment cannot bypass data protection' said 'protected or outside uninstall roots'
check 'protected data survives inherited uninstall mode' test -d "$H/Library/Application Support/com.bitwarden.fixture"
cp "$SANDBOX/pre-data-plan" "$PLAN"
check_not 'rejects uninstall with trash' apply --trash
check_not 'rejects uninstall with projects' apply --projects
# Forbidden paths are each planned and approved, and all must survive.
mkdir -p "$SANDBOX/outside/data" "$H/Library/Caches/ancestor"
echo precious > "$SANDBOX/outside/data/file"
ln -s "$SANDBOX/outside/data" "$H/Library/Caches/escape"
ln -s "$SANDBOX/outside" "$H/Library/Caches/ancestor/link"
for p in "$SANDBOX/outside/data" "$H/Library/Caches" "$H/Library/Caches/../Mail/$ID" "$H/Library/Caches/escape" "$H/Library/Caches/ancestor/link/data" "$H/Library/Mail/$ID" "$H/Applications/Apple.app" "$APP/Contents"; do
    record 'Its data' "$p"; approve "$p"; MOLE_UNINSTALL_MODE=1 apply
    check "refuses forbidden or protected path: ${p#$SANDBOX/}" test -e "$p"
done
approve "$H/Library/Caches/not-in-plan"; apply
check 'requires plan membership' said 'not in the plan'
cp "$PLAN" "$SANDBOX/with-refusals"
for id in com.apple.fixture app.captainlevi.cleaner; do
    : > "$PLAN"; record 'The app' "$H/Applications/Apple.app"
    if [[ "$id" == app.captainlevi.cleaner ]]; then : > "$PLAN"; record 'The app' "$H/Applications/Captain Levi.app"; fi
    record 'Caches and logs' "$H/Library/Caches/$ID"
    approve "$H/Library/Caches/$ID"; apply
    check "refuses protected app $id" test -d "$H/Library/Caches/$ID"
done
# Directly exercise System refusal without inspecting any real System path.
check 'refuses System apps' /bin/bash -c 'ENGINE_ROOT="$1"; source "$1/engine/uninstall_lib.sh"; MC_ID=org.fixture.system; MC_APP=/System/Fixture.app; ! mc_u_allowed' bash "$STAGE"
cp "$SANDBOX/with-refusals" "$PLAN"
record 'Its data' "$H/Applications/Eligible.app"
approve "$H/Applications/Apple.app" "$H/Applications/Eligible.app" "$APP/Contents"; apply
check 'requires the exact planned app' test -f "$H/Applications/Apple.app/Contents/Info.plist"
check 'eligible unplanned app receives no exception' grep -qx 'plain fixture, never executed' "$H/Applications/Eligible.app/Contents/MacOS/FixtureBinary"
check 'bundle descendants gain no exception' test -f "$APP/Contents/Info.plist"
# Leave WebKit unticked for the first actual removal.
approve "$APP" "$H/Library/Mail/$ID"
while IFS= read -r p; do [[ "$p" == "$H/Library/WebKit/"* ]] || printf '%s\0' "$p" >> "$APPROVED"; done < "$SANDBOX/tied"
mkdir -p "$SANDBOX/expected-trash" "$SANDBOX/snapshots"
cp -R "$H/.Trash/." "$SANDBOX/expected-trash/"
: > "$SANDBOX/movements"
index=0
while IFS= read -r -d '' p; do
    [[ "$p" != "$H/Library/Mail/$ID" ]] || continue
    name="${p##*/}"; dest="$name"; n=1
    while [[ -e "$SANDBOX/expected-trash/$dest" ]]; do
        dest="${name%.*} $n.${name##*.}"; n=$((n + 1))
    done
    mkdir "$SANDBOX/expected-trash/$dest"
    cp -R "$p" "$SANDBOX/snapshots/$index"
    printf '%s\0%s\0%s\0' "$p" "$dest" "$index" >> "$SANDBOX/movements"
    index=$((index + 1))
done < "$APPROVED"
check 'moves exactly approved paths to Trash' apply
while IFS= read -r -d '' p && IFS= read -r -d '' dest && IFS= read -r -d '' index; do
    check "exact Trash contents: $dest" diff -r "$SANDBOX/snapshots/$index" "$H/.Trash/$dest"
done < "$SANDBOX/movements"
while IFS= read -r p; do
    if [[ "$p" == "$H/Library/WebKit/"* ]]; then
        check "unticked source survives: $p" grep -qx used "$p/data"
        continue
    fi
    check "approved source moved: $p" test ! -e "$p"
done < "$SANDBOX/tied"
check 'app is gone' test ! -e "$APP"
check 'Trash retains app contents' grep -qF 'never executed' "$H/.Trash/Orchard Beta.app/Contents/MacOS/FixtureBinary"
check 'numbers Trash collisions' test -d "$H/.Trash/${ID%.*} 1.${ID##*.}"
check 'old Trash item survives' grep -qx old "$H/.Trash/$ID"
check 'unapproved path stays' test -f "$H/Library/WebKit/$ID/data"
check 'keeps never-delete protections' grep -qx protected "$H/Library/Mail/$ID/data"
check 'emits trashed history' grep -q 'trashed' "$SANDBOX/history"
scan --check "$ID" > "$SANDBOX/left.json"
check 'reports remnants that stayed' grep -qF "$H/Library/WebKit/$ID" "$SANDBOX/left.json"
check 'reports protected tied remnant' grep -qF "$H/Library/Mail/$ID" "$SANDBOX/left.json"
check 'reports system remnants that stayed' grep -qF '/Library/PrivilegedHelperTools/' "$SANDBOX/left.json"
# Saved identity permits an approved leftover without reinstalling the bundle.
check 'can plan leftovers after bundle removal' preview
check_not 'leftover plan omits app section' plan_has 'The app'
approve "$H/Library/WebKit/$ID"; apply
check 'leftover moves using saved identity' test ! -e "$H/Library/WebKit/$ID"
# Finish the same fixture using a reinstalled identity, then rescan its former path.
mkapp "$APP" "$ID" 'Orchard Beta'
preview; approve "$APP" "$H/Library/WebKit/$ID"; apply
: > "$H/system-fixtures"; : > "$H/receipt-fixtures"
check 'rescans after the app is gone' scan --check "$APP" > "$SANDBOX/check.out"
scan --check "$APP" > "$SANDBOX/left.json"
check 'empty tied leftovers after approved removal' grep -qF '"left":[]' "$SANDBOX/left.json"
check 'still reports surviving name-only candidates' grep -qF "$H/Library/Application Support/Orchard" "$SANDBOX/left.json"
check 'accounts for uninspected login items and receipts' grep -qF 'complete receipt inventory' "$SANDBOX/left.json"
check 'preserves unrelated data' grep -qx unrelated "$H/Library/Caches/unrelated/data"
check 'preserves shared data' grep -qx shared "$H/Library/Application Support/Orchard/data"
check 'preserves full-name candidate contents' grep -qx similar "$H/Library/Application Support/Orchard Beta/data"
check 'preserves shared vendor contents' grep -qx shared-vendor "$H/Library/Caches/Huawei/data"
check 'preserves another installed copy byte for byte' cmp "$SANDBOX/copy-before" "$SANDBOX/Copy.app/Contents/MacOS/FixtureBinary"
# Failure must be visible in both status and JSON, never an empty success.
cat >> "$STAGE/lib/core/app_protection.sh" <<'STUB'
find_app_files() { return 5; }
STUB
check_not 'incomplete discovery fails visibly' scan --check "$APP" > "$SANDBOX/incomplete.out"
scan --check "$APP" > "$SANDBOX/incomplete.json"
check 'incomplete discovery reports its error' grep -qF 'discovery incomplete' "$SANDBOX/incomplete.json"
check_not 'never invokes forbidden actions' grep -qsE '^(sudo|osascript|mdfind|curl|wget|brew|launchctl|pkill|killall|rm )' "$SANDBOX/stub-calls.log"
check_not 'vendor nesting never called at scan or apply' test -e "$H/vendor-calls"
finish
