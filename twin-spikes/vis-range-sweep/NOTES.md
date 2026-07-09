# vis-range sweep — Phase 2 evidence + per-config notes

Roadmap Must-Have #4 (benched vis-range recipe), Phase 2 sweep. SEAT-local evidence; nothing here
lands in the framework. Phase 1 parameterized `optimize_scene.gd` (`feat/vis-range-recipe`, commit
`5853234`) — this sweep temp-overlaid that branch version into each seat project for the optimize
stage and restored the materialized (main) version after.

## Machine / methodology (reused from twin-optimizer-benchmark-2026-07-08 + CITY.md)

Apple M3 Pro, macOS, Metal / Forward+, Godot 4.6.3, 1280x720 window, vsync OFF, shadows OFF,
warmup 2 s / measure 8 s. City vantages byte-identical to the 2026-07-08 run
(street `139.5,1.7,135:139.5,1.7,0`, aerial `-65,260,-65:135,15,135`). Documented noise floor:
**~0.03 ms cpu, ~0.5% fps** (within-session). Metric order (plan): cpu_ms -> sub-cap fps ->
objects_rendered delta -> primitives.

**Session note — fps was NOT display-capped this run** (duplex 1500-1900 fps, city 160-1000 fps;
the 120 Hz ProMotion cap never engaged, same as the CITY.md session, unlike the findings-file
session). So both cpu_ms AND fps are honest differentiators here. cpu_ms still leads per the plan.

## Scenes

1. **duplex** (`twin-build-validate`, `Duplex_A_20110907.glb` optimized at defaults) — 286 meshes,
   3 groups instanced (30 instances), **256 individual leftover MeshInstance3Ds** get the vis pass.
   Size classes (default 0.5/2.0 m): **0 small, 47 medium**. Coarser (1.0/4.0 m): 150 ranges set.
   Duplex vantages are AABB-derived (a 9x11x27 m building cannot use 270 m city coords — deviation
   logged): street = walk the long axis at 1.7 m; aerial = high oblique ~81 m so the default medium
   end (120) is IN range while tight ends (60) fall OUT.
2. **ucity** (unique-mesh city, `house-twin`, `city_before.scn` optimized `--min-instances=100000`)
   — **groups_instanced == 0 asserted** (nothing instanced; all 28,600 meshes stay individual):
   the synthetic stand-in for heterogeneous many-unique-mesh scenes (real plants have unique
   fittings; here uniqueness is a threshold trick — honest label). 0 small, 7700 medium (default);
   18000 ranges at coarser (1.0/4.0).
3. **c2** (negative control, `house-twin`, `city_before.scn` optimized `--chunks=2`, normal
   instancing) — **`vis_ranges_set == 0` asserted for BOTH off and default** (re-proves the no-op
   finding under the parameterized pass; the instancing pass consumes every repeated mesh, leaving
   nothing for the vis pass to touch). Plan reduced this cell to OFF + defaults — sufficient.

## Configs (optimize flags)

| config | small/med diag (m) | small/med end (m) |
|--------|--------------------|-------------------|
| off | — (no `--vis-ranges`) | — |
| default | 0.5 / 2.0 | 40 / 120 |
| dist_half | 0.5 / 2.0 | 20 / 60 |
| dist_double | 0.5 / 2.0 | 80 / 240 |
| coarser | 1.0 / 4.0 | 40 / 120 |
| aggressive | 1.0 / 4.0 | 20 / 60 |

## Headline results (deltas vs OFF; full numbers in summary.json)

- **duplex/street:** flat. cpu 0.16 ms every config; objects 343 every config (aggressive 342).
  Nothing culls at walkthrough distance (0 small meshes; all 47 medium within the tightest 60 m
  end). WITHIN NOISE — no effect.
- **duplex/aerial (~81 m):** only tight configs cull. dist_half objects 343->282 (cpu 0.15->0.14,
  within noise); aggressive objects 343->135 (-61%), cpu 0.15->0.11 (**-0.04 ms, only marginally
  beyond the 0.03 floor**), fps +21%. Real but trivially small — the whole scene is a 0.15 ms
  baseline.
- **ucity/street:** REAL, scales with aggressiveness. default cpu 0.99->0.90 (-9%), aggressive
  0.99->0.54 (**-45%**, -0.45 ms, far beyond noise), objects 11829->4854, fps +72%. dist_double is
  a no-op / slightly worse (end 240 culls nothing at street, +overhead).
- **ucity/aerial (~374 m):** DECISIVE. default/dist_half/dist_double all cpu 4.13->~2.82 (**-32%**,
  -1.3 ms — everything past even the 240 end culls, so all three classify the same 7700 meshes);
  coarser/aggressive cpu 4.13->~1.20 (**-71%**, -2.9 ms), objects 40500->12700, **fps 163->530
  (+225%)**. Classifies 18000 meshes at the 4.0 m diag threshold.
- **c2 (negative control):** off vs default cpu 0.28 vs 0.29 (street), 0.49 vs 0.52 (aerial) —
  at/within the noise floor; objects byte-identical (542 / 1084); `vis_ranges_set == 0`. Proven
  no-op. (Objects match the 2026-07-08 c2 numbers exactly, 542/1084; cpu lower this session because
  the run was uncapped — cross-session cpu drift, within-session off-vs-default is the real proof.)

## Perceptual pass (frame-reviewed, PENDING HUMAN FLY-THROUGH)

Street near->far screenshot series, OFF + every config, both scenes (`shots/`). The vis pass sets
`visibility_range_end` only — **no fade, hard pop at the cutoff.**

- **duplex — all configs:** pixel-identical to OFF at every street position (nothing culls). No
  popping possible. CLEAN.
- **ucity/default + dist_double:** indistinguishable from OFF at street — far-corridor detail
  persists to the vanishing point. CLEAN.
- **ucity/dist_half + coarser:** mild thinning of the deepest far-corridor small fixtures; near/mid
  field intact. Acceptable.
- **ucity/aggressive:** visibly thins distant small fixtures (windows, green roof caps) in the
  far-mid corridor at the bench vantage; near/mid field fully intact. In a live walk-through these
  would hard-pop in at the ~60 m boundary — noticeable in the mid-far field, foreground clean.
  Borderline; a fade margin would remove the pop if this cutoff is adopted.

## Provisional outcome: SCOPED WIN

`--vis-ranges` delivers a large, well-beyond-noise win **only on many-unique-mesh scenes** (the
unique-city: -32% to -71% cpu / +225% fps at aerial, -9% to -45% cpu at street, scaling with mesh
count and aggressiveness). On a realistic **single building (duplex) it buys essentially nothing**
(cpu flat at street; ≤0.04 ms at aerial only with the most aggressive cutoff on a 0.15 ms scene),
and it is a **proven no-op on fully-instanced repeated-geometry scenes** (negative control,
vis_ranges_set == 0, within noise). Recipe should ship **scoped to many-unique-mesh scenes** (heavy
heterogeneous clutter / plant-fitting regime); duplex-scale single-building guidance is "skip the
flag." `default` (40/120) is perceptually clean and already wins big at city scale, so it is the
safe recommended cutoff; `coarser`/`aggressive` win more but introduce visible far-field pop —
adopt only with a fade margin. Matches the plan's third outcome exactly.

## Reproduce

`bash bench_vis_sweep.sh optimize|restore|bench|shots` (overlay is managed by the `overlay`/
`restore` stages; the sweep here overlaid manually then ran optimize -> restore -> bench -> shots).
`python3 merge.py` regenerates `summary.json` + the delta tables.
