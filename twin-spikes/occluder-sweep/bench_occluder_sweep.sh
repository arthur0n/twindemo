#!/usr/bin/env bash
# bench_occluder_sweep.sh — seat-local driver for Phase 2 of open item #5 (benched occluder recipe).
#
# Sweeps the --occluders volume gate (--occluder-min-volume=) over 3 scenes x 2 vantages x 5 configs,
# using the framework's PARAMETERIZED optimize_scene.gd (feat/occluder-bench @ 554b074:
# --occluder-min-volume=, report echoes occluder_min_volume + occluders_added). The seat's
# materialized tools/optimize_scene.gd is framework main and lacks --occluder-min-volume=, so this
# script TEMP-OVERLAYS the branch version into each project's tools/ for the optimize stage and
# RESTORES it after (never leaves an overlay). Mirrors bench_vis_sweep.sh exactly.
#
# Stages (arg 1): overlay | optimize | restore | bench | shots | all
# Everything windowed (bench/shots SKIP under --headless) — run on a machine with a display.
# Evidence (raw JSON, reports, shots) lands under this dir; committed to the SEAT.
#
# Methodology reused verbatim from twin-optimizer-benchmark-2026-07-08 + vis-range-sweep:
# 1280x720 window, vsync OFF, shadows OFF, warmup 2 s / measure 8 s, vantages identical to those
# runs. Occlusion culling ships ON in both projects (project.godot
# rendering/occlusion_culling/use_occlusion_culling=true) so the OccluderInstance3D nodes are live.
set -euo pipefail

G=/Applications/Godot.app/Contents/MacOS/Godot
FW=/Users/arthurnunes/Library/MRHEWBUC-LOCAL/xenodot-twin/plugin-twin/tools/optimize_scene.gd
SEAT=/Users/arthurnunes/Library/MRHEWBUC-LOCAL/twindemo
TBV=$SEAT/twin-build-validate
HT=$SEAT/house-twin
EV=$SEAT/twin-spikes/occluder-sweep

# City vantages — byte-identical to the 2026-07-08 + vis-sweep runs for comparability.
STREET_C="139.5,1.7,135:139.5,1.7,0"
AERIAL_C="-65,260,-65:135,15,135"
# Duplex vantages — AABB-derived (same as vis-sweep): street = walk the long (Z) axis at eye height
# (interior walls sit between camera and far rooms — the live occluder cell); aerial = high oblique.
STREET_D="4.4,1.7,-12:4.4,1.7,24"
AERIAL_D="-40,55,-35:4.4,3.7,8.9"

# config-name -> extra optimize flags. "off" omits --occluders. LOWER volume gate = MORE occluders
# (a smaller mesh clears a smaller gate), so aggressive(2) adds the most, double(20) the fewest.
CONFIGS=(off default half double aggressive)
cfg_flags() {
  case "$1" in
    off)        echo "" ;;
    default)    echo "--occluders" ;;                          # shipped default gate = 10 m^3
    half)       echo "--occluders --occluder-min-volume=5" ;;
    double)     echo "--occluders --occluder-min-volume=20" ;;
    aggressive) echo "--occluders --occluder-min-volume=2" ;;
  esac
}

overlay() { for P in "$TBV" "$HT"; do cp "$P/tools/optimize_scene.gd" "$P/tools/optimize_scene.gd.ORIG_BAK"; cp "$FW" "$P/tools/optimize_scene.gd"; done; echo "overlaid framework optimize into both projects"; }
restore() { for P in "$TBV" "$HT"; do [ -f "$P/tools/optimize_scene.gd.ORIG_BAK" ] && mv "$P/tools/optimize_scene.gd.ORIG_BAK" "$P/tools/optimize_scene.gd"; done; echo "restored original optimize in both projects"; }

# optimize one (project, src, out-ext, base-flags, config, out-basename)
opt_one() {
  local proj=$1 src=$2 ext=$3 base=$4 name=$5 out=$6
  ( cd "$proj" && $G --headless --path . --script tools/optimize_scene.gd -- \
      --in="$src" --out="res://models/occsweep/${out}.${ext}" \
      --report="reports/occsweep/${out}.json" $base $(cfg_flags "$name") 2>&1 \
      | grep -E "OPTIMIZE: OK|FAIL|SCRIPT ERROR" | tail -1 )
}

optimize() {
  mkdir -p "$TBV/models/occsweep" "$TBV/reports/occsweep" "$HT/models/occsweep" "$HT/reports/occsweep"
  for c in "${CONFIGS[@]}"; do
    echo "== duplex $c =="; opt_one "$TBV" "res://models/Duplex_A_20110907.glb" tscn "" "$c" "duplex_$c"
    echo "== ucity  $c =="; opt_one "$HT" "res://models/city_before.scn" scn "--min-instances=100000" "$c" "ucity_$c"
    echo "== c2     $c =="; opt_one "$HT" "res://models/city_before.scn" scn "--chunks=2" "$c" "c2_$c"
  done
}

# bench one (project, scene-res-path, vantage, out-json)
bench_one() {
  local proj=$1 scene=$2 v=$3 out=$4
  ( cd "$proj" && $G --path . -s tools/bench_scene.gd -- "$scene" \
      --vantage "$v" --warmup 2 --measure 8 --out "$out" 2>&1 | grep -E "BENCH:" | tail -2 )
}

# CONFIGS to bench per scene are passed in (c2 collapses to a subset when occluders_added==0).
bench() {
  local JD="$EV/json"; mkdir -p "$JD"
  local DUP_CFGS="${DUP_CFGS:-off default half double aggressive}"
  local UCITY_CFGS="${UCITY_CFGS:-off default half double aggressive}"
  local C2_CFGS="${C2_CFGS:-off}"
  for c in $DUP_CFGS; do
    echo "-- bench duplex/$c --"
    bench_one "$TBV" "res://models/occsweep/duplex_$c.tscn" "$STREET_D" "$JD/duplex_street.json"
    bench_one "$TBV" "res://models/occsweep/duplex_$c.tscn" "$AERIAL_D" "$JD/duplex_aerial.json"
  done
  for c in $UCITY_CFGS; do
    echo "-- bench ucity/$c --"
    bench_one "$HT" "res://models/occsweep/ucity_$c.scn" "$STREET_C" "$JD/ucity_street.json"
    bench_one "$HT" "res://models/occsweep/ucity_$c.scn" "$AERIAL_C" "$JD/ucity_aerial.json"
  done
  for c in $C2_CFGS; do
    echo "-- bench c2/$c --"
    bench_one "$HT" "res://models/occsweep/c2_$c.scn" "$STREET_C" "$JD/c2_street.json"
    bench_one "$HT" "res://models/occsweep/c2_$c.scn" "$AERIAL_C" "$JD/c2_aerial.json"
  done
}

# perceptual screenshot series: street near->mid->far path + one aerial frame, OFF + each non-OFF
# config that added occluders. Occluder artifacts show as missing/popping geometry.
shots() {
  local SD="$EV/shots"; mkdir -p "$SD"
  local DUP_CFGS="${DUP_CFGS:-off default half double aggressive}"
  local UCITY_CFGS="${UCITY_CFGS:-off default half double aggressive}"
  mkdir -p "$TBV/scripts" && cp "$HT/scripts/shot_city.gd" "$TBV/scripts/shot_city.gd"
  # duplex path down the long axis (near/mid/far) at eye height + one aerial
  local DPATH=("4.4,1.7,-12:4.4,1.7,24" "4.4,1.7,4:4.4,1.7,30" "4.4,1.7,-30:4.4,1.7,24" "-40,55,-35:4.4,3.7,8.9")
  # city path down a street inside the block + one aerial
  local CPATH=("139.5,1.7,135:139.5,1.7,0" "139.5,1.7,200:139.5,1.7,0" "139.5,1.7,260:139.5,1.7,0" "-65,260,-65:135,15,135")
  for c in $DUP_CFGS; do
    for i in 0 1 2 3; do
      ( cd "$TBV" && $G --path . --resolution 1280x720 -s scripts/shot_city.gd -- \
          res://models/occsweep/duplex_$c.tscn --vantage "${DPATH[$i]}" --out "$SD/duplex_${c}_p$i.png" 2>&1 | grep -E "SHOT:" | tail -1 ) || true
    done
  done
  for c in $UCITY_CFGS; do
    for i in 0 1 2 3; do
      ( cd "$HT" && $G --path . --resolution 1280x720 -s scripts/shot_city.gd -- \
          res://models/occsweep/ucity_$c.scn --vantage "${CPATH[$i]}" --out "$SD/ucity_${c}_p$i.png" 2>&1 | grep -E "SHOT:" | tail -1 ) || true
    done
  done
  rm -f "$TBV/scripts/shot_city.gd"
}

case "${1:-all}" in
  overlay) overlay ;;
  optimize) optimize ;;
  restore) restore ;;
  bench) bench ;;
  shots) shots ;;
  all) overlay; optimize; restore; bench; shots ;;
  *) echo "usage: $0 overlay|optimize|restore|bench|shots|all"; exit 1 ;;
esac
