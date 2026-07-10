# occluder sweep — Phase 2 evidence + per-config notes

Open item #5 (benched occluder recipe), Phase 2 sweep. SEAT-local evidence; nothing here lands in
the framework. Phase 1 parameterized `optimize_scene.gd` (`feat/occluder-bench`, commit `554b074`:
`--occluder-min-volume=` with loud validation; report echoes `occluder_min_volume` +
`occluders_added`) — this sweep temp-overlaid that branch version into each seat project for the
optimize stage and restored the materialized (main) version after (no overlay left behind).

## Machine / methodology (reused from twin-optimizer-benchmark-2026-07-08 + vis-range-sweep)

Apple M3 Pro, macOS, Metal / Forward+, Godot 4.6.3, 1280x720 window, vsync OFF, shadows OFF,
warmup 2 s / measure 8 s. City vantages byte-identical to the 2026-07-08 + vis-sweep runs
(street `139.5,1.7,135:139.5,1.7,0`, aerial `-65,260,-65:135,15,135`); duplex vantages AABB-derived
(street = walk the long Z axis at 1.7 m — interior partitions sit between camera and far rooms, the
live occluder cell; aerial `-40,55,-35:...` high oblique). Documented noise floor: **~0.03 ms cpu**
(within-session). Metric order (plan): cpu_ms -> sub-cap fps -> objects_rendered -> draw_calls.

**Session note — fps WAS display-capped this run** (120.0 flat almost everywhere; only ucity/aerial
dipped to 116.8-119.9 under load), unlike the vis-sweep session. So **cpu_ms is the differentiator**
(per plan) and fps carries no signal here except marginally at ucity/aerial. `gpu_ms` reads 0.0
(unsupported on this Metal setup, as in prior runs).

**Godot occlusion-culling project setting (verified):** both bench/viewer projects (`house-twin`,
`twin-build-validate`) ship with `rendering/occlusion_culling/use_occlusion_culling=true`, committed
at workspace init (`f41f93e`) with an explicit comment ("Twin scenes rely on occlusion culling;
enabled at the project level so per-scene OccluderInstance3D nodes work the moment they land"). So
the occluders `--occluders` adds ARE live at runtime — no experiment-setup change was needed and
these numbers reflect real runtime occlusion. NOT the "flag adds dead occluders" risk in the twin
template; a hand-rolled project with the setting OFF would render the OccluderInstance3D nodes inert
(Phase-3 recipe note).

## Scenes + configs

- **duplex** (`twin-build-validate`, `Duplex_A_20110907.glb` optimized at defaults) — 286 meshes, 3
  groups instanced (30 inst), 256 leftover meshes feed the occluder pass. Single realistic building.
- **ucity** (`house-twin`, `city_before.scn` optimized `--min-instances=100000`) — 28,600 meshes,
  0 instanced (all leftover): the many-unique-mesh stand-in where occlusion can actually show.
- **c2** (`house-twin`, `city_before.scn` optimized `--chunks=2`) — fully instanced negative control.

The `--occluders` volume gate is a floor: a **lower** `--occluder-min-volume=` lets **smaller** meshes
clear it, so aggressive(2) adds the most occluders, double(20) the fewest. Configs: off (no flag),
default (10 m³, the shipped default via bare `--occluders`), half (5), double (20), aggressive (2).

### occluders_added per scene/config (from the optimize reports — self-describing)

| scene  | off | default (10) | half (5) | double (20) | aggressive (2) |
|--------|-----|--------------|----------|-------------|----------------|
| duplex | 0   | 31           | 39       | 21          | 74             |
| ucity  | 0   | 3100         | 3900     | 2100        | 7400           |
| c2     | 0   | **0**        | **0**    | **0**       | **0**          |

**c2 adds 0 occluders at EVERY gate** — fully instanced, the instancing pass consumes every mesh and
the occluder pass only touches leftover un-instanced meshes (same no-op the vis pass showed). The 5
c2 configs produce byte-identical scenes; benched OFF once as the representative (a data point, not
re-run hoping). Matches the 2026-07-08 "occluders are a no-op on fully-instanced scenes" finding.

## Results (deltas vs OFF; full self-describing rows in summary.json)

### duplex/street — NET-NEGATIVE
| config | occ | cpu_ms | Δcpu | objects | draw_calls | verdict |
|--------|-----|--------|------|---------|-----------|---------|
| off | 0 | 0.70 | — | 343 | 282 | baseline |
| default | 31 | 0.91 | **+0.21** | 105 | 101 | cpu REGRESSION |
| half | 39 | 0.89 | +0.19 | 105 | 101 | cpu REGRESSION |
| double | 21 | 0.86 | +0.16 | 269 | 234 | cpu REGRESSION |
| aggressive | 74 | 0.87 | +0.17 | 93 | 90 | cpu REGRESSION |

Occlusion culls objects hard (343→93-105) but cpu **regresses +0.16..+0.21 ms** (all beyond noise):
on a 0.7 ms scene the box-occluder depth rasterization + cull test costs more than the handful of
draw submits it saves. Net-negative at every gate.

### duplex/aerial — NET-NEGATIVE
| config | occ | cpu_ms | Δcpu | objects | draws | verdict |
|--------|-----|--------|------|---------|-------|---------|
| off | 0 | 0.61 | — | 343 | 284 | baseline |
| default | 31 | 0.78 | +0.17 | 321 | 273 | cpu REGRESSION |
| half | 39 | 0.81 | +0.20 | 317 | 271 | cpu REGRESSION |
| double | 21 | 0.81 | +0.20 | 321 | 273 | cpu REGRESSION |
| aggressive | 74 | 0.86 | +0.25 | 313 | 269 | cpu REGRESSION |

Aerial barely culls (343→313-321 — little sits behind anything from oblique above) and cpu regresses
**+0.17..+0.25 ms**. Net-negative.

### ucity/street — REAL WIN
| config | occ | cpu_ms | Δcpu | objects | Δobj | draws | verdict |
|--------|-----|--------|------|---------|------|-------|---------|
| off | 0 | 1.67 | — | 11829 | — | 1828 | baseline |
| default | 3100 | 1.52 | **-0.15** | 3990 | -66% | 757 | cpu-win ≥0.10 |
| half | 3900 | 1.52 | **-0.15** | 3650 | -69% | 714 | cpu-win ≥0.10 |
| double | 2100 | 1.64 | -0.03 | 5326 | -55% | 950 | within noise |
| aggressive | 7400 | 1.55 | -0.12 | 3169 | -73% | 655 | cpu-win ≥0.10 |

**Real, beyond-noise cpu win of -0.12..-0.15 ms (-9%)** at default/half/aggressive (double
under-covers at only -0.03, within noise); objects_rendered -55%..-73%, draw_calls -48%..-64%. Near
buildings occlude far ones down the street corridor — the live occluder cell. fps capped (120), no
fps signal. **Gate sweet spot: default (10) ties half (5) for best cpu; aggressive(2) adds 2.4× the
occluders (7400 vs 3100) for no extra cpu benefit; double(20) leaves too much uncovered.**

### ucity/aerial — NO-OP (objects flat) + measurement noise
| config | occ | cpu_ms | Δcpu | objects | Δobj | draws | fps |
|--------|-----|--------|------|---------|------|-------|-----|
| off | 0 | 5.45 | — | 40500 | 0 | 5579 | 117.5 |
| default | 3100 | 5.58 | +0.13 | 40500 | **0** | 5579 | 116.8 |
| half | 3900 | 4.71 | -0.74 | 40500 | **0** | 5579 | 119.5 |
| double | 2100 | 4.40 | -1.05 | 40500 | **0** | 5579 | 119.9 |
| aggressive | 7400 | 4.36 | -1.09 | 40500 | **0** | 5579 | 119.9 |

**objects_rendered is byte-identical (40500), draw_calls identical (5579), primitives identical
across ALL configs → occlusion culls NOTHING from aerial** (nothing sits between an overhead camera
and the block). The large cpu_ms spread (4.36-5.58) is **NON-MONOTONIC in occluder count**
(default=3100 occ reads the WORST at +0.13; double=2100 occ reads near-best at -1.05) — it is
thermal/session drift on a heavy 5 ms scene, **NOT an occlusion win** (there is no rendering-work
difference to produce one). Do not read the merge.py mechanical "cpu-win" label here — it is blind to
Δobj=0. Confirms the plan's prediction: aerial is the geometric no-op / negative control.

### c2/street + c2/aerial — PROVEN NO-OP
| vantage | cpu_ms | objects | draws | note |
|---------|--------|---------|-------|------|
| street | 0.91 | 542 | 542 | 0 occluders (all configs identical) |
| aerial | 0.96 | 1084 | 1084 | 0 occluders (all configs identical) |

Objects match the 2026-07-08 c2 numbers (542/1084) exactly. Fully-instanced scenes get 0 occluders —
skip the flag.

## Perceptual / artifact pass (frame-reviewed, PENDING HUMAN CONFIRMATION)

Street near→mid→far series (p0/p1/p2) + one aerial frame (p3), OFF + every config, both scenes with
occluders (`shots/`). All 4 non-OFF configs are **pixel-identical to each other** at every position
(md5) — even aggressive(2) never over-culls relative to default(10); the only comparison that matters
is OFF vs any occluder config. SSIM (1.000 = identical):

| position | duplex | ucity | reading |
|----------|--------|-------|---------|
| p0 (street near) | 1.000000 | 0.999967 | clean |
| p1 (interior/mid) | **0.983231** | 0.999900 | duplex INTERIOR artifact; ucity clean |
| p2 (street far) | 1.000000 | 0.999900 | clean |
| p3 (aerial) | 1.000000 | 1.000000 | no-op, identical |

- **ucity — CLEAN.** SSIM ≥0.99990 at every street position; the amplified diff is flat except one
  sub-pixel speck at the vanishing point — the 55-73% objects cut is all deep-corridor geometry
  genuinely hidden behind nearer buildings. No foreground holes. Visually lossless.
- **duplex — INTERIOR ARTIFACT at p1.** From a walkthrough corridor (p0) and far positions the
  frame is pixel-identical, but from **inside a room looking down the interior length (p1)** SSIM
  drops to 0.983 — the auto box-occluders (0.9× AABB of large leftover meshes, some of whose AABBs
  bracket the camera) over-cull genuinely-visible interior geometry. A visible change, not lossless.
  Compounds duplex's net-negative cpu: do not enable occluders on single-building interiors.
- c2 not shot (0 occluders — nothing to compare).

## Decision rule applied (PRE-DECLARED, unadjusted)

Rule: `--occluders` earns default-on for a scene class **only if ≥0.10 ms cpu_ms win at BOTH vantages
with zero artifacts**; else opt-in with measured guidance; net-negative published as such.

- **duplex** → cpu NET-NEGATIVE at both vantages (+0.16..+0.25 ms) **and** an interior over-cull
  artifact (SSIM 0.983). Fails hard. **Publish net-negative.**
- **ucity** → street: clean ≥0.10 win (-0.15 ms, SSIM ≥0.9999) ✓. aerial: **no occlusion effect**
  (Δobjects=0; the cpu spread is noise, not a win). Fails the "BOTH vantages" bar. **Does NOT earn
  default-on → opt-in with street-scoped guidance.**
- **c2 (instanced)** → 0 occluders, proven no-op. **Skip the flag.**

Because occlusion structurally needs occluders between camera and geometry, the aerial vantage is a
geometric no-op for every scene, so the "win at BOTH vantages" bar cannot be met by an occlusion
feature — the pre-declared rule (unadjusted) therefore yields **opt-in** for the one scene that wins
anywhere (ucity/street).

## Provisional outcome: STAYS OPT-IN WITH MEASURED GUIDANCE

No scene class earns default-on. Measured guidance for the Phase-3 recipe:

- **Use `--occluders` only on many-unique-mesh scenes viewed at street/interior level** (heavy
  heterogeneous clutter): ucity/street cut objects_rendered -55..-73%, draw_calls -48..-64%, cpu
  -0.15 ms (-9%), visually lossless.
- **The shipped 10 m³ default gate is already the sweet spot** — smaller gates (5, 2) only add
  occluder count with no extra cpu payoff; 20 under-covers. No reason to lower the default.
- **Skip it on single-building scenes** (duplex): net-negative cpu at both vantages (the depth-raster
  + cull overhead exceeds the few submits saved on a sub-1 ms scene) **and** it over-culls visible
  interior geometry.
- **No-op on fully-instanced scenes** (c2: 0 occluders) **and from aerial vantages** (objects flat).
- Requires `rendering/occlusion_culling/use_occlusion_culling=true` (twin template ships it ON).

Matches the plan's "stays opt-in with measured guidance" outcome (with a net-negative sub-result for
duplex published with numbers).

## Reproduce

`bash bench_occluder_sweep.sh overlay|optimize|restore|bench|shots` (overlay/restore manage the temp
framework-optimize overlay; the sweep ran overlay → optimize → restore → bench → shots). c2 bench
collapsed to OFF via `C2_CFGS="off"` (all configs byte-identical, 0 occluders). `python3 merge.py`
regenerates `summary.json` + the delta tables. SSIM: `ffmpeg -i off.png -i cfg.png -lavfi ssim -f null -`.
