#!/bin/bash
# Runs the landing page's camera mode against a synthetic webcam feed and prints what it saw.
# Needs the site served on :8765 (python3 -m http.server 8765 from site/).
set -e
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
"$CHROME" --headless=new --disable-gpu --virtual-time-budget=60000 --dump-dom "http://localhost:8765/dev/fake-camera.html" 2>/dev/null > "$WORK/dom.html"
python3 - "$WORK" <<'PY'
import sys, re, base64
work = sys.argv[1]
frames = re.search(r'<pre id="out">(.*?)</pre>', open(work + "/dom.html").read(), re.S).group(1).split()
with open(work + "/feed.mjpeg", "wb") as feed:
    for frame in frames:
        feed.write(base64.b64decode(frame) * 1)
        feed.write(base64.b64decode(frame))          # source is 15 fps, Chrome plays MJPEG at 30
print(len(frames), "frames")
PY
"$CHROME" --headless=new --use-fake-device-for-media-stream --use-fake-ui-for-media-stream --use-file-for-fake-video-capture="$WORK/feed.mjpeg" \
  --enable-logging=stderr --v=0 --user-data-dir="$WORK/profile" "http://localhost:8765/index.html?camera&trace" 2> "$WORK/log.txt" &
PID=$!; sleep "${1:-24}"; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true
grep -o 'TRACE {.*}' "$WORK/log.txt" | sed 's/\\"/"/g; s/^TRACE //' > "$WORK/trace.jsonl" || true
grep -iE 'CONSOLE.*(error|uncaught)' "$WORK/log.txt" | grep -v TRACE | head -5 || true
python3 - "$WORK/trace.jsonl" <<'PY'
import sys, json
rows = []
for line in open(sys.argv[1]):
    line = line.strip().rstrip('",')
    line = line[:line.rindex("}") + 1]
    try: rows.append(json.loads(line))
    except Exception: pass
print(len(rows), "trace samples")
for i, r in enumerate(rows):
    if i % 5 == 0: print(f'{i/10:5.1f}s {r["mode"]:7} yaw {r["yaw"]:6.1f} pitch {r["pitch"]:6.1f} level {r["level"]:.2f} {r["reason"]:9} toward {str(r.get("toward")):15} {r["faces"]:8} {r["status"]}')
PY
