#!/usr/bin/env python3
"""pop_analyze.py — consecutive-frame diff metric for the POP-SERIES proxy (open item #6, rule (a)).

For each config's approach frame series (frames/<config>/f_NNN_z*.png), compute between every ADJACENT
pair (i, i+1):
  ydelta = mean absolute luma difference of the two frames (ffmpeg blend=difference -> signalstats
           YAVG, 0..255) — "how much of the frame changed this 3 m step"
  ssim   = structural similarity (ffmpeg ssim All), 1.0 = identical
A HARD POP = a sharp SPIKE in ydelta (dip in ssim) at the step where a chunky object crosses the cull
shell — the object appears at full opacity in one 3 m step. A WORKING FADE spreads that same
appearance as an alpha ramp over the [end, end+margin] band, so the per-step ydelta is LOWER and
SMEARED across several steps (lower peak, higher baseline, smaller peak/mean ratio).

Emits pop_metrics.json + a per-step table + summary stats (peak ydelta, peak/mean ratio, #steps whose
ydelta exceeds 2x the series mean = "pop-like" steps). Reads only PNGs this run produced. Requires ffmpeg.
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIGS = sys.argv[1:] or ["aggressive", "aggressive_fade12"]


def frames(cfg):
    d = os.path.join(HERE, "frames", cfg)
    fs = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    return [os.path.join(d, f) for f in fs]


def ydelta(a, b):
    out = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", a, "-i", b, "-lavfi",
         "blend=all_mode=difference,format=gray,signalstats,metadata=print:file=-",
         "-f", "null", "-"], capture_output=True, text=True)
    m = re.findall(r"YAVG=([0-9.]+)", out.stdout + out.stderr)
    return float(m[-1]) if m else float("nan")


def ssim(a, b):
    out = subprocess.run(["ffmpeg", "-i", a, "-i", b, "-lavfi", "ssim", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    m = re.findall(r"All:([0-9.]+)", out)
    return float(m[-1]) if m else float("nan")


def zval(path):
    m = re.search(r"z(\d+)\.png$", path)
    return int(m.group(1)) if m else -1


def main():
    result = {}
    for cfg in CONFIGS:
        fs = frames(cfg)
        steps = []
        for i in range(len(fs) - 1):
            yd = ydelta(fs[i], fs[i + 1])
            ss = ssim(fs[i], fs[i + 1])
            steps.append({"i": i, "z_from": zval(fs[i]), "z_to": zval(fs[i + 1]),
                          "ydelta": round(yd, 3), "ssim": round(ss, 5)})
        yds = [s["ydelta"] for s in steps]
        mean = sum(yds) / len(yds)
        peak = max(yds)
        peak_step = max(steps, key=lambda s: s["ydelta"])
        poplike = sum(1 for y in yds if y > 2 * mean)
        result[cfg] = {
            "n_steps": len(steps), "mean_ydelta": round(mean, 3), "peak_ydelta": round(peak, 3),
            "peak_over_mean": round(peak / mean, 2), "peak_step_z": [peak_step["z_from"], peak_step["z_to"]],
            "min_ssim": round(min(s["ssim"] for s in steps), 5),
            "poplike_steps_gt2xmean": poplike, "steps": steps,
        }
    with open(os.path.join(HERE, "pop_metrics.json"), "w") as f:
        json.dump(result, f, indent=2)

    for cfg, r in result.items():
        print(f"\n== POP-SERIES {cfg} ==  peak_ydelta={r['peak_ydelta']} (at z {r['peak_step_z'][0]}->{r['peak_step_z'][1]}) "
              f"mean={r['mean_ydelta']} peak/mean={r['peak_over_mean']} min_ssim={r['min_ssim']} "
              f"pop-like_steps(>2xmean)={r['poplike_steps_gt2xmean']}")
        print(f"  {'z_from->z_to':>14}{'ydelta':>9}{'ssim':>10}")
        for s in r["steps"]:
            bar = "#" * int(s["ydelta"] * 4)
            print(f"  {str(s['z_from'])+'->'+str(s['z_to']):>14}{s['ydelta']:>9.3f}{s['ssim']:>10.5f}  {bar}")
    print("\nwrote pop_metrics.json")


if __name__ == "__main__":
    main()
