#!/usr/bin/env python3
"""merge.py — join the raw bench rows with the optimize reports into ONE self-describing table.

Each bench row records scene/vantage/metrics but NOT the four effective vis-* distances (bench does
not know them). The matching optimize report echoes them (vis_ranges_set + the four values). This
joins them by config so every output row carries: scene, config, the four effective vis distances,
vis_ranges_set, and the measured metrics — nothing needs "which config was this file" archaeology.
"""
import json
import os

EV = os.path.dirname(os.path.abspath(__file__))
SEAT = os.path.abspath(os.path.join(EV, "..", ".."))
JSON_DIR = os.path.join(EV, "json")
REPORTS = {
    "duplex": os.path.join(SEAT, "twin-build-validate", "reports", "vissweep"),
    "ucity": os.path.join(SEAT, "house-twin", "reports", "vissweep"),
    "c2": os.path.join(SEAT, "house-twin", "reports", "vissweep"),
}
CONFIGS = ["off", "default", "dist_half", "dist_double", "coarser", "aggressive"]


def load_report(scene, config):
    prefix = {"duplex": "duplex", "ucity": "ucity", "c2": "c2"}[scene]
    path = os.path.join(REPORTS[scene], f"{prefix}_{config}.json")
    r = json.load(open(path))
    return {
        "vis_ranges_set": r["vis_ranges_set"],
        "vis_small_diag": r["vis_small_diag"],
        "vis_medium_diag": r["vis_medium_diag"],
        "vis_small_end": r["vis_small_end"],
        "vis_medium_end": r["vis_medium_end"],
        "groups_instanced": r["groups_instanced"],
    }


def main():
    out = []
    for scene, configs in [("duplex", CONFIGS), ("ucity", CONFIGS), ("c2", ["off", "default"])]:
        for vantage in ["street", "aerial"]:
            bench_path = os.path.join(JSON_DIR, f"{scene}_{vantage}.json")
            rows = json.load(open(bench_path))
            for i, config in enumerate(configs):
                row = rows[i]
                rpt = load_report(scene, config)
                out.append({
                    "scene": scene, "config": config, "vantage": vantage,
                    **rpt,
                    "cpu_ms": row["cpu_ms"], "fps": row["fps"],
                    "objects_rendered": row["objects_rendered"],
                    "draw_calls": row["draw_calls"], "primitives": row["primitives"],
                })
    json.dump(out, open(os.path.join(EV, "summary.json"), "w"), indent=2)
    # console table with deltas vs OFF per (scene, vantage)
    NOISE_CPU, NOISE_FPS = 0.03, 0.5  # documented floor: 0.03 ms cpu, 0.5% fps
    by = {}
    for r in out:
        by.setdefault((r["scene"], r["vantage"]), []).append(r)
    for (scene, vantage), rows in by.items():
        off = next(r for r in rows if r["config"] == "off")
        print(f"\n=== {scene} / {vantage}  (OFF cpu={off['cpu_ms']}ms fps={off['fps']} obj={off['objects_rendered']}) ===")
        print(f"{'config':12} {'ends(s/m)':10} {'set':>6} {'cpu_ms':>7} {'dcpu%':>7} {'fps':>8} {'dfps%':>7} {'objects':>8} {'dobj':>7} {'verdict':>10}")
        for r in rows:
            dcpu = (r["cpu_ms"] - off["cpu_ms"]) / off["cpu_ms"] * 100 if off["cpu_ms"] else 0
            dfps = (r["fps"] - off["fps"]) / off["fps"] * 100 if off["fps"] else 0
            dobj = r["objects_rendered"] - off["objects_rendered"]
            within = abs(r["cpu_ms"] - off["cpu_ms"]) <= NOISE_CPU and abs(dfps) <= NOISE_FPS
            verdict = "NOISE" if (r["config"] != "off" and within) else ("" if r["config"] == "off" else "real")
            ends = f"{r['vis_small_end']:.0f}/{r['vis_medium_end']:.0f}"
            print(f"{r['config']:12} {ends:10} {r['vis_ranges_set']:6} {r['cpu_ms']:7.2f} {dcpu:7.1f} {r['fps']:8.1f} {dfps:7.1f} {r['objects_rendered']:8} {dobj:7} {verdict:>10}")


if __name__ == "__main__":
    main()
