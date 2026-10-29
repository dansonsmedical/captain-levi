#!/bin/bash
# No outside network: signed local fixtures served only on IPv4 loopback.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/levi-updater-test.XXXXXX")"
server_pid=''
cleanup() {
    [[ -z "$server_pid" ]] || { kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; }
    /bin/rm -rf "$scratch"
}
trap cleanup EXIT
export TMPDIR="$scratch"
mkdir -p "$scratch/fixtures"
cd "$REPO_ROOT/app"
swift build -c release
binary="$(swift build -c release --show-bin-path)/MacCleaner"
# A real ad-hoc signed app, rather than skipping the production signature check.
for kind in good symlink wrong-id same older unsigned; do
    app="$scratch/$kind/Captain Levi.app"
    mkdir -p "$app/Contents/MacOS"
    cp /usr/bin/true "$app/Contents/MacOS/fixture"
    version=1.1.0
    id=app.captainlevi.cleaner
    case "$kind" in wrong-id) id=org.fixture.wrong ;; same) version=1.0.0 ;; older) version=0.9.0 ;; esac
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$id</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleExecutable</key><string>fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
    if [[ "$kind" == symlink ]]; then ln -s fixture "$app/Contents/MacOS/link"; fi
    /usr/bin/codesign --force --sign - "$app"
    if [[ "$kind" == unsigned ]]; then /usr/bin/codesign --remove-signature "$app/Contents/MacOS/fixture"; fi
    /usr/bin/ditto -c -k --keepParent "$app" "$scratch/fixtures/$kind.zip"
    printf fixture > "$scratch/$kind/Start here.png"
    /usr/bin/zip -q -j "$scratch/fixtures/$kind.zip" "$scratch/$kind/Start here.png"
done
# Prove the archived link fixture is validly signed after extraction, independently
# of the updater's link guards. A codesign refusal must never count as link coverage.
/usr/bin/ditto -x -k "$scratch/fixtures/symlink.zip" "$scratch/symlink-extracted"
/usr/bin/codesign --verify --deep --strict "$scratch/symlink-extracted/Captain Levi.app"
printf 'PASS extracted symlink fixture strict codesign\n'
printf '{}' > "$scratch/fixtures/check.json"
port="$(/usr/bin/python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
cd "$scratch/fixtures"
/usr/bin/python3 -I -c '
import http.server, json, os, sys, threading, time
records = []
lock = threading.Lock()
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        with lock:
            records.append(dict({"path": self.path}, **{k.lower(): v for k, v in self.headers.items()}))
            with open("headers.json.new", "w") as output:
                json.dump(records, output)
            os.replace("headers.json.new", "headers.json")
        redirects = {"/redirect.zip": "/good.zip", "/outside.zip": "http://127.0.0.1:%d/good.zip" % alternate.server_port,
                     "/file.zip": "file://" + os.path.abspath("good.zip")}
        if self.path in redirects:
            self.send_response(302)
            self.send_header("Location", redirects[self.path])
            self.end_headers()
        elif self.path == "/slow.zip":
            self.send_response(200)
            self.send_header("Content-Length", "1000000")
            self.end_headers()
            try:
                for _ in range(1000):
                    self.wfile.write(b"x" * 1000)
                    self.wfile.flush()
                    time.sleep(0.05)
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            super().do_GET()
primary = http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler)
alternate = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=alternate.serve_forever, daemon=True).start()
primary.serve_forever()
' "$port" > "$scratch/server.log" 2>&1 &
server_pid=$!
/usr/bin/python3 -I -c '
import socket, sys, time
for attempt in range(100):
    try:
        with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=0.1):
            sys.exit(0)
    except OSError:
        time.sleep(0.05)
sys.exit("FAIL loopback server startup")
' "$port"
kill -0 "$server_pid"
"$binary" --updater-selftest "http://127.0.0.1:$port/" "$scratch/fixtures"
