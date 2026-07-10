#!/usr/bin/env python3
"""merge.py — join the occluder-sweep bench rows with the optimize reports and emit summary.json.

Each bench row (json/<scene>_<vantage>.json, an array in CONFIG order) is joined to its optimize
report (reports/<scene>_<config>.json) so every row is self-describing: config, occluder_min_volume,
occluders_added folded in beside cpu_ms/fps/objects_rendered/draw_calls/primitives. Deltas are
computed vs the OFF baseline of the same scene/vantage. NOISE_MS is the documented within-session
cpu floor; a |delta| <= NOISE_MS is flagged not-a-win.
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIGS = ["off", "default", "half", "double", "aggressive"]
C2_CONFIGS = ["off"]  # c2 collapsed: occluders_added==0 for all 5, scenes byte-identical
NOISE_MS = 0.03

SCENES = {
    "duplex": {"vantages": ["street", "aerial"], "configs": CONFIGS},
    "ucity":  {"vantages": ["street", "aerial"], "configs": CONFIGS},
    "c2":     {"vantages": ["street", "aerial"], "configs": C2_CONFIGS},
}


def report_for(scene, config):
    p = os.path.join(HERE, "reports", f"{scene}_{config}.json")
    with open(p) as f:
        r = json.load(f)
    return {"occluders_added": r["occluders_added"], "occluder_min_volume": r["occluder_min_volume"]}


def main():
    summary = {"noise_floor_ms": NOISE_MS, "scenes": {}}
    for scene, meta in SCENES.items():
        summary["scenes"][scene] = {}
        for vantage in meta["vantages"]:
            rows = json.load(open(os.path.join(HERE, "json", f"{scene}_{vantage}.json")))
            configs = meta["configs"]
            assert len(rows) == len(configs), f"{scene}_{vantage}: {len(rows)} rows vs {len(configs)} configs"
            base = None
            out = []
            for cfg, row in zip(configs, rows):
                rep = report_for(scene, cfg)
                rec = {
                    "config": cfg,
                    "occluder_min_volume": rep["occluder_min_volume"],
                    "occluders_added": rep["occluders_added"],
                    "cpu_ms": row["cpu_ms"],
                    "fps": row["fps"],
                    "objects_rendered": row["objects_rendered"],
                    "draw_calls": row["draw_calls"],
                    "primitives": row["primitives"],
                }
                if cfg == "off":
                    base = rec
                    rec["d_cpu_ms"] = 0.0
                    rec["d_objects"] = 0
                    rec["win"] = "baseline"
                else:
                    d = round(rec["cpu_ms"] - base["cpu_ms"], 3)
                    rec["d_cpu_ms"] = d
                    rec["d_objects"] = rec["objects_rendered"] - base["objects_rendered"]
                    if d <= -NOISE_MS - 1e-9 and abs(d) >= 0.10:
                        rec["win"] = "cpu-win>=0.10"
                    elif d <= -NOISE_MS - 1e-9:
                        rec["win"] = "cpu-win-below-0.10"
                    elif abs(d) <= NOISE_MS:
                        rec["win"] = "within-noise"
                    else:
                        rec["win"] = "cpu-REGRESSION"
                out.append(rec)
            summary["scenes"][scene][vantage] = out
    with open(os.path.join(HERE, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    # console tables
    for scene, vmap in summary["scenes"].items():
        for vantage, rows in vmap.items():
            print(f"\n== {scene}/{vantage} ==")
            print(f"{'config':<11}{'occ':>6}{'vol':>6}{'cpu_ms':>8}{'Δcpu':>8}{'fps':>7}{'objects':>9}{'Δobj':>8}{'draws':>7}  {'verdict'}")
            for r in rows:
                print(f"{r['config']:<11}{r['occluders_added']:>6}{r['occluder_min_volume']:>6.0f}"
                      f"{r['cpu_ms']:>8.2f}{r['d_cpu_ms']:>8.2f}{r['fps']:>7.1f}"
                      f"{r['objects_rendered']:>9}{r['d_objects']:>8}{r['draw_calls']:>7}  {r['win']}")
    print("\nwrote summary.json")


if __name__ == "__main__":
    main()
