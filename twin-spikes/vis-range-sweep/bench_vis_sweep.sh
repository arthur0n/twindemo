#!/usr/bin/env bash
# bench_vis_sweep.sh — seat-local driver for Phase 2 of Must-Have #4 (benched vis-range recipe).
#
# Sweeps the --vis-ranges size-class distances over 3 scenes x 2 vantages x 6 configs, using the
# framework's PARAMETERIZED optimize_scene.gd (feat/vis-range-recipe, --vis-small-diag / -medium-diag
# / -small-end / -medium-end). The seat's materialized tools/optimize_scene.gd is from framework main
# and lacks those flags, so this script TEMP-OVERLAYS the branch version into each project's tools/
# for the optimize stage and RESTORES it after (never leaves an overlay).
#
# Stages (arg 1): overlay | optimize | restore | bench | shots | merge | all
# Everything is windowed (bench/shots SKIP or blank under --headless) — run on a machine with a
# display. Evidence (raw JSON, shots, merged summary) lands under this dir; committed to the SEAT.
#
# Methodology reused verbatim from twin-optimizer-benchmark-2026-07-08 / CITY.md: 1280x720 window,
# vsync off, shadows off, warmup 2 s / measure 8 s, city vantages identical to that run.
set -euo pipefail

G=/Applications/Godot.app/Contents/MacOS/Godot
FW=/Users/arthurnunes/Library/MRHEWBUC-LOCAL/xenodot-twin/plugin-twin/tools/optimize_scene.gd
SEAT=/Users/arthurnunes/Library/MRHEWBUC-LOCAL/twindemo
TBV=$SEAT/twin-build-validate
HT=$SEAT/house-twin
EV=$SEAT/twin-spikes/vis-range-sweep

# City vantages — byte-identical to the 2026-07-08 run for comparability.
STREET_C="139.5,1.7,135:139.5,1.7,0"
AERIAL_C="-65,260,-65:135,15,135"
# Duplex vantages — a single ~9x11x27 m building cannot use 270 m city coords; derived from its AABB
# (pos -0.24,-1.55,-4.38 size 9.28,10.55,26.57 center 4.4,3.73,8.9). Street = walk the long (Z) axis
# at eye height; aerial = high oblique at ~81 m so the medium class (default end 120) is IN range and
# the tighter ends (60) fall OUT — i.e. the vantage actually discriminates the configs.
STREET_D="4.4,1.7,-12:4.4,1.7,24"
AERIAL_D="-40,55,-35:4.4,3.7,8.9"

# config-name -> extra optimize flags (beyond --vis-ranges). "off" omits --vis-ranges entirely.
CONFIGS=(off default dist_half dist_double coarser aggressive)
cfg_flags() {
  case "$1" in
    off)         echo "" ;;
    default)     echo "--vis-ranges" ;;
    dist_half)   echo "--vis-ranges --vis-small-end=20 --vis-medium-end=60" ;;
    dist_double) echo "--vis-ranges --vis-small-end=80 --vis-medium-end=240" ;;
    coarser)     echo "--vis-ranges --vis-small-diag=1.0 --vis-medium-diag=4.0" ;;
    aggressive)  echo "--vis-ranges --vis-small-diag=1.0 --vis-medium-diag=4.0 --vis-small-end=20 --vis-medium-end=60" ;;
  esac
}

overlay() { for P in "$TBV" "$HT"; do cp "$P/tools/optimize_scene.gd" "$P/tools/optimize_scene.gd.ORIG_BAK"; cp "$FW" "$P/tools/optimize_scene.gd"; done; echo "overlaid framework optimize into both projects"; }
restore() { for P in "$TBV" "$HT"; do [ -f "$P/tools/optimize_scene.gd.ORIG_BAK" ] && mv "$P/tools/optimize_scene.gd.ORIG_BAK" "$P/tools/optimize_scene.gd"; done; echo "restored original optimize in both projects"; }

# optimize one (project, src, out-ext, base-flags, config)
opt_one() {
  local proj=$1 src=$2 ext=$3 base=$4 name=$5 out=$6
  ( cd "$proj" && $G --headless --path . --script tools/optimize_scene.gd -- \
      --in="$src" --out="res://models/vissweep/${out}.${ext}" \
      --report="reports/vissweep/${out}.json" $base $(cfg_flags "$name") 2>&1 | grep -E "OPTIMIZE: OK|FAIL|SCRIPT ERROR" | tail -1 )
}

optimize() {
  mkdir -p "$TBV/models/vissweep" "$TBV/reports/vissweep" "$HT/models/vissweep" "$HT/reports/vissweep"
  for c in "${CONFIGS[@]}"; do
    echo "== duplex $c =="; opt_one "$TBV" "res://models/Duplex_A_20110907.glb" tscn "" "$c" "duplex_$c"
    echo "== ucity  $c =="; opt_one "$HT" "res://models/city_before.scn" scn "--min-instances=100000" "$c" "ucity_$c"
  done
  # negative control: normal instancing (chunks=2) + vis-ranges default; expect vis_ranges_set==0
  echo "== c2 off =="; opt_one "$HT" "res://models/city_before.scn" scn "--chunks=2" "off" "c2_off"
  echo "== c2 default =="; opt_one "$HT" "res://models/city_before.scn" scn "--chunks=2" "default" "c2_default"
}

# bench one (project, scene-res-path, vantage, out-json)
bench_one() {
  local proj=$1 scene=$2 v=$3 out=$4
  ( cd "$proj" && $G --path . -s tools/bench_scene.gd -- "$scene" \
      --vantage "$v" --warmup 2 --measure 8 --out "$out" 2>&1 | grep -E "BENCH:" | tail -2 )
}

bench() {
  local JD="$EV/json"; mkdir -p "$JD"
  for c in "${CONFIGS[@]}"; do
    bench_one "$TBV" "res://models/vissweep/duplex_$c.tscn" "$STREET_D" "$JD/duplex_street.json"
    bench_one "$TBV" "res://models/vissweep/duplex_$c.tscn" "$AERIAL_D" "$JD/duplex_aerial.json"
    bench_one "$HT" "res://models/vissweep/ucity_$c.scn" "$STREET_C" "$JD/ucity_street.json"
    bench_one "$HT" "res://models/vissweep/ucity_$c.scn" "$AERIAL_C" "$JD/ucity_aerial.json"
  done
  for c in off default; do
    bench_one "$HT" "res://models/vissweep/c2_$c.scn" "$STREET_C" "$JD/c2_street.json"
    bench_one "$HT" "res://models/vissweep/c2_$c.scn" "$AERIAL_C" "$JD/c2_aerial.json"
  done
}

# perceptual screenshot series: street vantage, near->far path, OFF + each non-OFF config.
shots() {
  local SD="$EV/shots"; mkdir -p "$SD"
  # shot_city.gd ships in house-twin/scripts; the duplex project (twin-build-validate) has no gen
  # scripts, so stage a scratch copy there for the duplex shots (removed by the caller/cleanup).
  mkdir -p "$TBV/scripts" && cp "$HT/scripts/shot_city.gd" "$TBV/scripts/shot_city.gd"
  # duplex path down the long axis (near/mid/far) at eye height
  local DPATH=("4.4,1.7,-12:4.4,1.7,24" "4.4,1.7,4:4.4,1.7,30" "4.4,1.7,-30:4.4,1.7,24")
  # city path down a street inside the block
  local CPATH=("139.5,1.7,135:139.5,1.7,0" "139.5,1.7,200:139.5,1.7,0" "139.5,1.7,260:139.5,1.7,0")
  for c in "${CONFIGS[@]}"; do
    for i in 0 1 2; do
      ( cd "$TBV" && $G --path . --resolution 1280x720 -s scripts/shot_city.gd -- \
          res://models/vissweep/duplex_$c.tscn --vantage "${DPATH[$i]}" --out "$SD/duplex_${c}_p$i.png" 2>&1 | grep -E "SHOT:" | tail -1 ) || true
      ( cd "$HT" && $G --path . --resolution 1280x720 -s scripts/shot_city.gd -- \
          res://models/vissweep/ucity_$c.scn --vantage "${CPATH[$i]}" --out "$SD/ucity_${c}_p$i.png" 2>&1 | grep -E "SHOT:" | tail -1 ) || true
    done
  done
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
