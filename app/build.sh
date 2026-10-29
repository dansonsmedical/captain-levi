#!/bin/bash
# Builds the self-contained Captain Levi app using SwiftPM.
# Usage: app/build.sh [ENGINE_ROOT] [--install] [--release]
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd .. && pwd -P)"
ENGINE_ROOT="$REPO_ROOT"
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --release) : ;;
        --*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) ENGINE_ROOT="$(cd "$arg" && pwd -P)" ;;
    esac
done
APP_NAME="${APP_NAME:-Captain Levi}"
BUNDLE_ID="${BUNDLE_ID:-app.captainlevi.cleaner}"
APP_VERSION="${APP_VERSION:-$(cat "$REPO_ROOT/VERSION")}"
case "${LEVI_ICON:-a}" in
    a|b|c) ;;
    *) echo 'Invalid LEVI_ICON: expected a, b, or c' >&2; exit 1 ;;
esac
# These values become both filenames and XML. Refuse unsafe spellings before removing build output.
[[ "$APP_NAME" != .* && "$APP_NAME" != *[!a-zA-Z0-9\ ._-]* ]] || { echo 'Invalid APP_NAME' >&2; exit 1; }
[[ "$BUNDLE_ID" == *.* && "$BUNDLE_ID" != *[!a-zA-Z0-9.-]* ]] || { echo 'Invalid BUNDLE_ID' >&2; exit 1; }
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid APP_VERSION' >&2; exit 1; }
[[ -f "$ENGINE_ROOT/bin/clean.sh" && -f "$ENGINE_ROOT/engine/apply.sh" ]] || { echo "No cleaner at $ENGINE_ROOT" >&2; exit 1; }

BUILD_FLAGS=()
# Keep local source paths out of the distributed executable, including Swift's #file strings.
BUILD_FLAGS=(-Xswiftc -file-prefix-map -Xswiftc "$REPO_ROOT=/captain-levi"
    -Xswiftc -file-prefix-map -Xswiftc "$HOME=/home"
    -Xswiftc -debug-prefix-map -Xswiftc "$REPO_ROOT=/captain-levi"
    -Xswiftc -debug-prefix-map -Xswiftc "$HOME=/home")
# Bash 3.2 treats an empty array as unset under nounset.
swift build -c release --product MacCleaner ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"}
BIN="$(swift build -c release --show-bin-path)/MacCleaner"
[[ -x "$BIN" ]] || { echo 'Build failed' >&2; exit 1; }

APP="build/$APP_NAME.app"
/bin/rm -rf "$APP" build/icon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/icon.iconset
cp "$BIN" "$APP/Contents/MacOS/MacCleaner"
strip -x "$APP/Contents/MacOS/MacCleaner"
DEST="$APP/Contents/Resources/engine"
mkdir -p "$DEST/engine"
for entry in mole bin lib LICENSE TRADEMARK.md; do
    cp -R "$ENGINE_ROOT/$entry" "$DEST/"
done
for entry in "$ENGINE_ROOT/engine/"*; do
    [[ "${entry##*/}" == tests ]] && continue
    cp -R "$entry" "$DEST/engine/"
done
# Do not ship links that could lead outside the allowlist.
[[ -z "$(find "$DEST" -type l -print)" ]] || { echo 'Engine contains symbolic links' >&2; exit 1; }

# Icon: drawn in-process by the app itself, then cut to the standard sizes.
"$BIN" --render-icon build/icon-1024.png --levi "${LEVI_ICON:-a}" > /dev/null
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" build/icon-1024.png --out "build/icon.iconset/icon_${size}x${size}.png" > /dev/null
    sips -z $((size * 2)) $((size * 2)) build/icon-1024.png --out "build/icon.iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns build/icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
/bin/rm -rf build/icon.iconset build/icon-1024.png

COMMIT_COUNT=1
if [[ -e "$REPO_ROOT/.git" ]]; then
    if count="$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null)" && [[ "$count" =~ ^[0-9]+$ ]]; then
        COMMIT_COUNT="$count"
    fi
fi
cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>MacCleaner</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
    <key>CFBundleVersion</key><string>$COMMIT_COUNT</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSDownloadsFolderUsageDescription</key><string>$APP_NAME lists old installer files in Downloads when you ask it to.</string>
    <key>NSDesktopFolderUsageDescription</key><string>$APP_NAME lists old installer files on your Desktop when you ask it to.</string>
    <key>NSHumanReadableCopyright</key><string>Made from Mole (GPL-3.0).</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
/bin/rm -rf .build
echo "Built $PWD/$APP"
if [[ "$INSTALL" == true ]]; then
    mkdir -p "$HOME/Applications"
    /bin/rm -rf "$HOME/Applications/$APP_NAME.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "Installed $HOME/Applications/$APP_NAME.app"
fi
