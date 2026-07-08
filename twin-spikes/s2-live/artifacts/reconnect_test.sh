#!/bin/sh
# Reconnect choreography: viewer runs 30s; sim killed at t=8s, restarted at t=14s.
ROOT=/Users/arthurnunes/Library/MRHEWBUC-LOCAL/mercenary/twin-spikes/s2-live
cp "$ROOT/artifacts/report.json" "$ROOT/artifacts/run1-report.json"
cp "$ROOT/artifacts/screenshot.png" "$ROOT/artifacts/run1-screenshot.png"

/Applications/Godot.app/Contents/MacOS/Godot --path "$ROOT/viewer" > "$ROOT/artifacts/viewer2.log" 2>&1 &
GPID=$!
sleep 8
pkill -f "node server.js"
echo "[test] sim killed at t=8s"
sleep 6
cd "$ROOT/sim" && node server.js --seed 99 > "$ROOT/artifacts/sim2.log" 2>&1 &
SIMPID=$!
echo "[test] sim restarted at t=14s"
wait $GPID
kill $SIMPID 2>/dev/null
mv "$ROOT/artifacts/report.json" "$ROOT/artifacts/run2-report.json"
mv "$ROOT/artifacts/screenshot.png" "$ROOT/artifacts/run2-screenshot.png"
cp "$ROOT/artifacts/run1-report.json" "$ROOT/artifacts/report.json"
cp "$ROOT/artifacts/run1-screenshot.png" "$ROOT/artifacts/screenshot.png"
echo "[test] done"
