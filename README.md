# twindemo

A from-scratch reproduction of the **Xenodot Forge digital-twin viewer**: a live, scrubbable twin
of the standard Duplex_A BIM model — real IFC geometry, real streaming telemetry, colored walls,
deterministic playback, a green end-to-end gate.

```
twindemo/
├── xenodot-forge/   the framework (a clone of the xenodot-forge repo)
├── house/           the viewer project the framework scaffolds (its own git repo)
├── downloads/       the source IFC model (Duplex_A_20110907.ifc)
├── TUTORIAL.md      ← START HERE: the complete step-by-step walkthrough
└── README.md        this file
```

The framework and the project are **two repos on purpose**: the framework points at an external
project, reads it in place, and never contains twin content of its own.

**Start at [`TUTORIAL.md`](TUTORIAL.md)** — it walks the whole pipeline (clone → scaffold → IFC
import → bindings → record → gate → run), with the exact commands, the expected output, the
wrinkles a stranger hits, how to drive it from the web UI, and a troubleshooting section.

Proof captures: `house/docs/shots/live.png` (LIVE, heat-mapped walls) and
`house/docs/shots/playback.png` (PLAYBACK, timeline scrub).
