#!/usr/bin/env bash
# bench_fade_sweep.sh — seat-local driver for Phase 2 of open item #6 (fade margin for the aggressive
# vis-range tier). Sweeps the --vis-fade-margin fade band over ucity (the many-unique-mesh scene) at
# street (decisive) + aerial (context), for the aggressive (1.0/4.0->20/60) and coarser (1.0/4.0->
# 40/120) size-class configs, each x fade OFF / margin 5 (self) / margin 12 (self), plus a true OFF
# (no --vis-ranges) baseline re-benched THIS SESSION for a fair same-session retention denominator.
#
# Uses the framework's feat/vis-fade-margin optimize_scene.gd + tools/lib/twin_vis_range.gd (the vis
# pass moved into the lib in ed99442; fade knobs added in 4552f22). The seat's MATERIALIZED
# tools/optimize_scene.gd is framework main (inline vis pass, NO fade, NO TwinVisRange lib), so this
# script TEMP-OVERLAYS BOTH branch files into house-twin for the optimize stage and RESTORES after
# (the original optimize is backed up; the lib is NEW to the seat so restore DELETES it — no overlay
# left behind). A one-shot `--import` is run after overlay so Godot registers the new TwinVisRange
# global class (a fresh class_name is not in .godot/global_script_class_cache.cfg until a scan).
#
# Stages (arg 1): overlay | optimize | restore | bench | merge | all
# VERIFIED Phase 1 semantics carried: fade band = [end, end+margin]; margin REQUIRED; Forward+ ONLY
# (house-twin renders forward_plus, so the fade is LIVE here) -- the Mobile/Compatibility renderer
# (web export) treats fade as DISABLED and the pop RETURNS. That caveat is renderer-level, not
# sweep-measurable here, and the recipe must carry it verbatim.
#
# Methodology reused verbatim from vis-range-sweep / occluder-sweep: 1280x720 window, vsync OFF,
# shadows OFF, warmup 2 s / measure 8 s, city vantages byte-identical to those runs. Noise floor
# ~0.03 ms cpu (within-session). Evidence (raw JSON, reports) lands under this dir; committed to SEAT.
set -euo pipefail

G=/Applications/Godot.app/Contents/MacOS/Godot
FW=/Users/arthurnunes/Library/MRHEWBUC-LOCAL/xenodot-twin/plugin-twin/tools
SEAT=/Users/arthurnunes/Library/MRHEWBUC-LOCAL/twindemo
HT=$SEAT/house-twin
EV=$SEAT/twin-spikes/fade-sweep

STREET_C="139.5,1.7,135:139.5,1.7,0"
AERIAL_C="-65,260,-65:135,15,135"

# config-name -> extra optimize flags. "off" omits --vis-ranges (the retention denominator baseline).
# aggressive = coarser diag thresholds (1.0/4.0) AND tight ends (20/60); coarser = same thresholds,
# default ends (40/120). Each base config x {no fade, margin 5 self, margin 12 self}.
CONFIGS=(off aggressive aggressive_fade5 aggressive_fade12 coarser coarser_fade5 coarser_fade12)
AGG="--vis-ranges --vis-small-diag=1.0 --vis-medium-diag=4.0 --vis-small-end=20 --vis-medium-end=60"
CRS="--vis-ranges --vis-small-diag=1.0 --vis-medium-diag=4.0"
cfg_flags() {
  case "$1" in
    off)                echo "" ;;
    aggressive)         echo "$AGG" ;;
    aggressive_fade5)   echo "$AGG --vis-fade-margin=5 --vis-fade-mode=self" ;;
    aggressive_fade12)  echo "$AGG --vis-fade-margin=12 --vis-fade-mode=self" ;;
    coarser)            echo "$CRS" ;;
    coarser_fade5)      echo "$CRS --vis-fade-margin=5 --vis-fade-mode=self" ;;
    coarser_fade12)     echo "$CRS --vis-fade-margin=12 --vis-fade-mode=self" ;;
  esac
}

overlay() {
  cp "$HT/tools/optimize_scene.gd" "$HT/tools/optimize_scene.gd.ORIG_BAK"
  cp "$FW/optimize_scene.gd" "$HT/tools/optimize_scene.gd"
  cp "$FW/lib/twin_vis_range.gd" "$HT/tools/lib/twin_vis_range.gd"
  touch "$HT/tools/lib/twin_vis_range.gd.OVERLAY_MARK"
  # register the new TwinVisRange global class so --script resolves the class_name
  ( cd "$HT" && $G --headless --path . --import 2>&1 | grep -iE "DONE|error" | tail -1 ) || true
  echo "overlaid branch optimize + twin_vis_range lib into house-twin (+ class scan)"
}
restore() {
  [ -f "$HT/tools/optimize_scene.gd.ORIG_BAK" ] && mv "$HT/tools/optimize_scene.gd.ORIG_BAK" "$HT/tools/optimize_scene.gd"
  if [ -f "$HT/tools/lib/twin_vis_range.gd.OVERLAY_MARK" ]; then
    rm -f "$HT/tools/lib/twin_vis_range.gd" "$HT/tools/lib/twin_vis_range.gd.uid" "$HT/tools/lib/twin_vis_range.gd.OVERLAY_MARK"
  fi
  ( cd "$HT" && $G --headless --path . --import 2>&1 | grep -iE "DONE" | tail -1 ) || true
  echo "restored materialized optimize; removed overlaid lib"
}

optimize() {
  mkdir -p "$HT/models/fadesweep" "$EV/reports"
  for c in "${CONFIGS[@]}"; do
    echo "== ucity $c =="
    ( cd "$HT" && $G --headless --path . --script tools/optimize_scene.gd -- \
        --in="res://models/city_before.scn" --out="res://models/fadesweep/ucity_$c.scn" \
        --report="$EV/reports/ucity_$c.json" --min-instances=100000 $(cfg_flags "$c") 2>&1 \
        | grep -E "OPTIMIZE: OK|FAIL|SCRIPT ERROR" | tail -1 )
  done
}

bench_one() {
  local scene=$1 v=$2 out=$3
  ( cd "$HT" && $G --path . -s tools/bench_scene.gd -- "$scene" \
      --vantage "$v" --warmup 2 --measure 8 --out "$out" 2>&1 | grep -E "BENCH:" | tail -2 )
}

bench() {
  mkdir -p "$EV/json"
  rm -f "$EV/json/ucity_street.json" "$EV/json/ucity_aerial.json"
  for c in "${CONFIGS[@]}"; do
    echo "-- bench ucity/$c --"
    bench_one "res://models/fadesweep/ucity_$c.scn" "$STREET_C" "$EV/json/ucity_street.json"
    bench_one "res://models/fadesweep/ucity_$c.scn" "$AERIAL_C" "$EV/json/ucity_aerial.json"
  done
}

# repeat: interleaved-across-cycles street cpu for ONE family (cancels monotonic thermal drift the
# single sequential pass suffers under the 120 Hz cap). Usage: repeat <fam> where fam=aggressive|coarser
# -> benches off + the family's 3 configs, CYCLES times, appending each config to json/repeat/<cfg>.json.
CYCLES="${CYCLES:-4}"
repeat() {
  local fam="${1:-aggressive}"; local RD="$EV/json/repeat"; mkdir -p "$RD"
  local cfgs; case "$fam" in
    aggressive) cfgs="off aggressive aggressive_fade5 aggressive_fade12" ;;
    coarser)    cfgs="off coarser coarser_fade5 coarser_fade12" ;;
    *) echo "repeat: fam must be aggressive|coarser"; exit 1 ;;
  esac
  for cyc in $(seq 1 "$CYCLES"); do
    for c in $cfgs; do
      bench_one "res://models/fadesweep/ucity_$c.scn" "$STREET_C" "$RD/$c.json" | sed "s/^/cyc$cyc $c /"
    done
  done
}

# pop: dense scripted street-approach frame series (single windowed process per config) for the
# POP-SERIES proxy. pop_series.gd is staged into house-twin/scripts and removed after.
POP_CFGS="${POP_CFGS:-aggressive aggressive_fade12}"
pop() {
  cp "$EV/pop_series.gd" "$HT/scripts/pop_series.gd"
  for c in $POP_CFGS; do
    rm -rf "$EV/frames/$c"; mkdir -p "$EV/frames/$c"
    ( cd "$HT" && $G --path . --resolution 1280x720 -s scripts/pop_series.gd -- \
        "res://models/fadesweep/ucity_$c.scn" --out-dir "$EV/frames/$c" \
        --x 139.5 --y 1.7 --start-z 126 --end-z 30 --step 3 --look-ahead 60 --settle 6 2>&1 \
        | grep -E "POP: (DONE|FAIL)" | tail -1 )
  done
  rm -f "$HT/scripts/pop_series.gd" "$HT/scripts/pop_series.gd.uid"
  python3 "$EV/pop_analyze.py" $POP_CFGS
}

# compat: BONUS — render fade12 + no-fade under gl_compatibility (CLI override, no project edit) at the
# peak-fade pose; same-renderer diff isolates the fade (Forward+-only caveat validated at runtime).
compat() {
  local V="139.5,1.7,99:139.5,1.7,39"
  for c in aggressive aggressive_fade12; do
    ( cd "$HT" && $G --rendering-method gl_compatibility --path . --resolution 1280x720 \
        -s scripts/shot_city.gd -- "res://models/fadesweep/ucity_$c.scn" --vantage "$V" \
        --out "$EV/shots/z99_${c}_COMPAT.png" 2>&1 | grep -E "SHOT: OK" | tail -1 )
  done
}

case "${1:-all}" in
  overlay) overlay ;;
  optimize) optimize ;;
  restore) restore ;;
  bench) bench ;;
  repeat) repeat "${2:-aggressive}" ;;
  pop) pop ;;
  compat) compat ;;
  merge) python3 "$EV/merge.py" ;;
  all) overlay; optimize; restore; bench; repeat aggressive; repeat coarser; pop; compat; python3 "$EV/merge.py" ;;
  *) echo "usage: $0 overlay|optimize|restore|bench|repeat <fam>|pop|compat|merge|all"; exit 1 ;;
esac
