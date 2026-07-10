# fade-margin sweep — Phase 2 evidence + rule verdict

Open item #6 (fade margin for the aggressive vis-range tier), Phase 2 sweep. SEAT-local evidence;
nothing here lands in the framework. Phase 1 parameterised the fade knobs on branch
`feat/vis-fade-margin`: `ed99442` (vis pass extracted into `tools/lib/twin_vis_range.gd`) + `4552f22`
(`--vis-fade-margin=<m>` / `--vis-fade-mode=self|deps`, fail-loud validation, report echoes
`vis_fade_margin` + `vis_fade_mode`). This sweep TEMP-OVERLAID **both** branch files
(`optimize_scene.gd` + `tools/lib/twin_vis_range.gd`) into house-twin for the optimize stage and
RESTORED after (the lib is new to the seat, so restore DELETES it — no overlay left behind). A
one-shot `--import` after overlay registers the new `TwinVisRange` global class (a fresh `class_name`
is absent from `.godot/global_script_class_cache.cfg` until a scan — the overlay fails to parse
without it).

## VERIFIED Phase 1 semantics carried into this sweep (unchanged, not re-litigated)

- Fade band = `[end, end+margin]`; a positive margin is REQUIRED for any fade (zero-width band never
  fades). `self` fades the object's own alpha; `deps` fades its `visibility_parent` LOD deps.
- **RENDERER CAVEAT (headline, regardless of sweep outcome): fade renders ONLY under Forward+. The
  Mobile / Compatibility renderer — which the WEB EXPORT uses — treats `SELF`/`DEPENDENCIES` as
  DISABLED, so the hard pop RETURNS on web.** house-twin renders `forward_plus`
  (`project.godot: renderer/rendering_method="forward_plus"`), so the fade is LIVE in every number
  below; the web caveat is renderer-level, not sweep-measurable here, and the recipe must carry it
  verbatim.

## Machine / methodology (reused from vis-range-sweep / occluder-sweep)

Apple M3 Pro, macOS, Metal / Forward+, Godot 4.6.3, 1280x720 window, vsync OFF, shadows OFF, warmup
2 s / measure 8 s (repeat cells 1.5 / 6 s). ucity vantages byte-identical to those runs
(street `139.5,1.7,135:139.5,1.7,0`, aerial `-65,260,-65:135,15,135`). Documented noise floor
**~0.03 ms cpu** (within-session). Scene: **ucity** only (`house-twin`, `city_before.scn` optimised
`--min-instances=100000` → `groups_instanced==0`, all 28,600 meshes individual; `vis_ranges_set==18000`
for every vis config — matches vis-range-sweep). Duplex / c2 are out of scope (vis-range-sweep already
proved them no-op / trivial for the vis pass).

**SESSION NOTE — presentation was 120 Hz DISPLAY-CAPPED this run** (`frame_ms` 8.33 flat, `fps` 120.0
everywhere), like the occluder-sweep session and UNLIKE the (uncapped) vis-range-sweep session. With
render load ~1–2 ms out of the 8.33 ms budget, the CPU idles ~6 ms/frame and the measured render-time
cpu is noisy. The **single sequential street pass drifted NON-PHYSICALLY** — fade configs read LOWER
cpu than their no-fade base despite rendering MORE objects (physically impossible for the same scene).
Raw evidence of the drift is kept in `json/ucity_street.json` (superseded). **Street cpu is therefore
taken from INTERLEAVED REPEAT arrays** (`json/repeat/<cfg>.json`): each config benched once per cycle,
cycles interleaved, which cancels the monotonic thermal drift and restores the physical ordering
(base < fade5 < fade12). The two families ran in separate thermal blocks, so **each family's retention
uses its own same-block OFF** (`off.json` rows 0–3 = aggressive block, 4–7 = coarser block).
`objects_rendered` / `draw_calls` / `primitives` are DETERMINISTIC per-frame counts (identical every
run) and are the backbone metric; cpu corroborates within its noisy limits. Aerial (below) is stable
and taken from the single pass.

## Configs (optimize flags; ucity, `--min-instances=100000`)

| config | small/med diag | small/med end | fade |
|--------|----------------|---------------|------|
| off | — (no `--vis-ranges`) | — | — |
| aggressive | 1.0 / 4.0 | **20 / 60** | none |
| aggressive_fade5 | 1.0 / 4.0 | 20 / 60 | `--vis-fade-margin=5 --vis-fade-mode=self` |
| aggressive_fade12 | 1.0 / 4.0 | 20 / 60 | `--vis-fade-margin=12 --vis-fade-mode=self` |
| coarser | 1.0 / 4.0 | 40 / 120 | none |
| coarser_fade5 | 1.0 / 4.0 | 40 / 120 | `--vis-fade-margin=5 --vis-fade-mode=self` |
| coarser_fade12 | 1.0 / 4.0 | 40 / 120 | `--vis-fade-margin=12 --vis-fade-mode=self` |

## STREET results (interleaved-repeat, per-family own OFF) — DECISIVE

Retention = (OFF − fade) / (OFF − no-fade-base). Fade cost = fade − base (median). Δobj vs base.

**aggressive tier** — OFF cpu median 1.61 / min 1.51 ms:

| config | cpu med | cpu min | objects | Δobj | draws | fade cost (med) | retention med | retention min | verdict |
|--------|---------|---------|---------|------|-------|-----------------|---------------|---------------|---------|
| aggressive | 0.84 | 0.83 | 4854 | — | 906 | — | 100% | 100% | no-fade base |
| aggressive_fade5 | 0.87 | 0.86 | 5016 | **+162 (+3.3%)** | 1303 | **+0.025 (≤ noise)** | **97%** | **96%** | **PASS ≥80%** |
| aggressive_fade12 | 1.08 | 0.96 | 5282 | **+428 (+8.8%)** | 1630 | +0.235 | **69%** | **81%** | **BORDERLINE** |

**coarser tier** — OFF cpu median 1.77 / min 1.73 ms:

| config | cpu med | cpu min | objects | Δobj | draws | fade cost (med) | retention med | retention min | verdict |
|--------|---------|---------|---------|------|-------|-----------------|---------------|---------------|---------|
| coarser | 1.28 | 1.21 | 7944 | — | 1325 | — | 100% | 100% | no-fade base |
| coarser_fade5 | 1.46 | 1.35 | 8262 | +318 (+4.0%) | 1816 | +0.170 | 65% | 73% | FAIL <80% |
| coarser_fade12 | 1.58 | 1.53 | 8726 | +782 (+9.8%) | 2452 | +0.295 | 39% | 38% | FAIL <80% |

**Cost mechanism, quantified (the rule's ask):** the fade band `[end, end+margin]` extends draw
distance — objects that would hard-cull at `end` instead RENDER (with alpha) out to `end+margin`. So
`objects_rendered` RISES with margin exactly as predicted (+3.3% / +8.8% aggressive; +4.0% / +9.8%
coarser), and `draw_calls` rise even harder (aggressive 906→1303→1630; coarser 1325→1816→2452 — each
faded object still submits a draw). cpu tracks the object rise. **coarser's fade is proportionally far
costlier** because its cull radius sits at 40/120 m where much more geometry lies in the band (+782
objects at margin 12) AND its no-fade win is smaller (0.49 vs 0.77 ms), so the same-magnitude fade
cost eats a bigger fraction of a smaller win.

## AERIAL results (single-pass; context) — fade is FREE

| config | objects | cpu_ms |
|--------|---------|--------|
| off | 40500 | 3.94 |
| any vis config (aggressive/coarser × any fade) | **12700** (identical) | 2.13–2.17 (flat, within noise) |

From 374 m up, the whole scene is past even `end+margin` (72 m ≪ 374 m), so the fade band contains
NOTHING: every vis config renders an IDENTICAL 12700 objects and cpu is flat within noise. **Fade
costs nothing at aerial** — the cost materialises only where objects sit inside the band, i.e. at
street. Clean context confirmation.

## POP-SERIES proxy (rule clause (a)) — FRAME-REVIEWED, PENDING HUMAN CONFIRMATION

Dense scripted approach down the street axis (`pop_series.gd`, ONE windowed process per config):
camera at `(139.5, 1.7, z)` looking at `(139.5, 1.7, z−60)` — pure forward translation — stepping
z 126→30 in **3 m** steps (32 frames), crossing the aggressive 60 m medium cutoff. Frames in
`frames/<config>/`; metrics in `pop_metrics.json` (`pop_analyze.py`).

**Adjacent-frame diff (within a config) is DOMINATED by camera motion, not the pop.** 3 m of forward
travel down a dense street shifts the whole frame (parallax), giving adjacent-frame SSIM ~0.83 and a
periodic ydelta (peaks every ~24 m = the repeating city-block geometry). The aggressive (no-fade) and
fade12 temporal profiles are IDENTICAL to 3 sig figs (peak ydelta 21.67 vs 21.63) — motion swamps any
per-object fade signal at this step granularity. So the adjacent-frame metric alone cannot isolate the
pop here.

**Matched-position config diff (motion cancelled) is the real signal.** Diffing aggressive vs fade
frame at the SAME camera pose isolates exactly the pixels the fade changes:

| pair | peak ydelta (of 255) | mean ydelta | min SSIM | reading |
|------|----------------------|-------------|----------|---------|
| aggressive vs fade12 | 0.164 (at z=99) | 0.033 | 0.9962 | fade active; localised to block-boundary rows z≈99/69/39 |
| aggressive vs fade5 | 0.056 | 0.008 | — | narrower 5 m band → ~⅓ the faded geometry of fade12 |

The 20×-amplified difference image (`shots/z99_diff_amplified20x.png`) shows the fade IS genuinely
active under Forward+: the changed pixels are WINDOWS, wall panels and green roof caps at the
cull-boundary distances that fade12 renders (faded) and aggressive drops entirely — exactly the
"distant small fixtures" vis-range-sweep flagged. **At 1× the configs are near-indistinguishable
(SSIM 0.996).** WHY the pop is small at this vantage: the aggressive cutoff only ranges sub-4 m-diag
clutter (buildings, being large, are NEVER ranged — they always draw), and at 60 m that clutter is
tiny in screen space. So BOTH the hard-pop and its fade-fix are perceptually minor here; the fade
demonstrably REPLACES the hard appearance with a gradual alpha ramp over the band (mechanism proven by
the +162/+428 object rise and the amplified diff), but the magnitude is subtle. **Frame-reviewed;
a human fly-through is still needed to rule on perceptual pop elimination — flagged pending.**

## BONUS — Compatibility renderer at runtime (the Forward+-only caveat) — INCONCLUSIVE at runtime

Rendered fade12 + no-fade under `--rendering-method gl_compatibility` (CLI override, NO project edit
— non-disruptive) at the peak-fade pose (z=99). Same-renderer fade-vs-no-fade SSIM = **0.9982** under
Compatibility vs **0.9962** under Forward+ (i.e. the fade's already-tiny effect is even WEAKER under
Compatibility) — directionally consistent with fade being disabled there, but NOT a clean binary:
cross-renderer frame SSIM is confounded by whole-renderer shading differences (compat-vs-forward ~0.83
regardless of fade), and the fade signal at this vantage (~0.002 SSIM) sits near renderer noise, so a
runtime image test cannot cleanly resolve it. **The authoritative proof of the caveat is Phase 1's
serialization-level analysis (Compatibility treats `SELF`/`DEPENDENCIES` as DISABLED); it stands.**
Shots: `shots/z99_*_COMPAT.png`.

## RULE APPLIED (pre-declared, unadjusted)

Rule: a fade config earns adoption into the aggressive tier iff, on ucity STREET, it (a) eliminates
the visible hard-pop AND (b) retains ≥80% of that config's cpu win vs OFF.

- **aggressive_fade5 (margin 5, self):** (b) **PASS** — 97% median / 96% min retention; fade cost
  **+0.025 ms, at/below the 0.03 ms noise floor = effectively FREE**; +162 objects (+3.3%). (a)
  softens the pop (alpha ramp replaces hard appearance; matched-diff confirms fade active) — the pop
  at this vantage is small to begin with. Provisional: **clears both, pending human pop confirmation
  of the narrower 5 m band.**
- **aggressive_fade12 (margin 12, self):** (a) **best** pop smoothing (widest 12 m band, smoothest
  ramp) but (b) **BORDERLINE-FAIL** — 69% median / 81% min retention; fade cost +0.235 ms eats ~⅓ of
  the win on the robust median estimator. This is the config that **came CLOSEST on the pop but misses
  the retention bar.**
- **coarser tier (context):** fade FAILS retention at BOTH margins (65%/39%) — not adoptable with
  fade; its wider cull radius drops far more geometry into the band.

## Provisional outcome

**The aggressive tier is adoptable WITH `--vis-fade-margin=5 --vis-fade-mode=self`** — margin 5
retains 97% of the aggressive cpu win (cost within noise, i.e. the fade is essentially free at street
because only 162 distant fixtures re-enter the band) and replaces the hard pop with an alpha ramp;
margin 12 removes the pop most thoroughly but eats ~⅓ of the win (borderline-fail on retention).
Aerial fade is free (band empty). **Web-export caveat carried verbatim: the fade renders under
Forward+ ONLY — on the Compatibility renderer (web) it is DISABLED and the pop returns.** Final
adoption is gated on a human fly-through confirming margin 5 perceptually kills the (small) pop; if a
human judges the 5 m ramp too quick, margin 12 is the pop-optimal fallback but it does not clear the
80% retention bar and would ship as "aggressive-tier fade costs ~⅓ of the win."

## Reproduce

```
bash bench_fade_sweep.sh overlay      # overlay branch optimize + twin_vis_range lib + class scan
bash bench_fade_sweep.sh optimize     # build 7 ucity configs -> models/fadesweep/, reports/
bash bench_fade_sweep.sh restore      # restore materialized optimize, delete overlaid lib
bash bench_fade_sweep.sh bench        # single sequential pass (aerial reliable; street superseded)
CYCLES=4 bash bench_fade_sweep.sh repeat aggressive   # interleaved street cpu (authoritative)
CYCLES=4 bash bench_fade_sweep.sh repeat coarser
bash bench_fade_sweep.sh pop          # pop-series frames + pop_analyze.py
bash bench_fade_sweep.sh compat       # bonus: Compatibility-renderer shots
python3 merge.py                      # summary.json + retention tables
```
SSIM / pixel-delta: `ffmpeg -i a.png -i b.png -lavfi ssim -f null -` and
`ffmpeg -i a -i b -lavfi "blend=all_mode=difference,format=gray,signalstats,metadata=print:file=-" -f null -`.

## Promoted to core (2026-07-10, xenodot-twin `feat/seat-promotions`)

The pop-series pair here was promoted to the framework as the **bench_sweep perceptual mode**:
`pop_series.gd` → `plugin-twin/tools/bench/pop_series.gd` (arg-ified — the street coords above are the
header's worked example, no longer baked constants) and `pop_analyze.py` →
`plugin-twin/tools/bench/pop_analyze.py` (arg-ified frames-dir pairs; both adjacent-frame and
matched-position modes; ffmpeg preflighted). Parity proven against this spike's recorded numbers
(aggressive vs fade12 peak ydelta 0.164 @ z=99 / min SSIM 0.9962). These seat originals stay as
evidence. (The scale scene generator `house-twin/scripts/gen_city.gd` was promoted the same run to
`plugin-twin/examples/gen_city.gd`.)
