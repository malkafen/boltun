#!/usr/bin/env python3
"""Draws the benchmark charts as SVG from a results directory (see report.py), in light and dark mode:
- memory and CPU time over the whole scenario, one run per app (the run with the median wall time), with the phases;
- the time every switch took until the posts were on screen (median over the runs).
Usage: chart.py <dir> <usage.svg> [switches.svg]"""
import glob, json, os, statistics, sys

APPS = [("mattermost", "Mattermost Desktop 6.3.1"), ("boltun", "Boltun")]
COLORS = ["#eb6834", "#2a78d6"]  # light mode; the style sheet has the dark steps
PHASES = [("idle", "idle"), ("switches", "switches"), ("history_open", "history"), ("traffic", "live traffic"),
          ("end", "idle")]
STYLE = """<style>
  @media (prefers-color-scheme: dark) {
    .surface { fill: #1a1a19 } .ink { fill: #f0efec } .muted { fill: #c3c2b7 } .grid { stroke: #2e2d2b } .axis { stroke: #55544f }
    .phase { stroke: #6b6a64 }
    .s0 { stroke: #d95926 } .f0 { fill: #d95926 } .s1 { stroke: #3987e5 } .f1 { fill: #3987e5 }
  }
</style>"""
FONT = 'font-family="-apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif" font-size="12"'


def step(run, name):
    return next(s for s in run["steps"] if s["name"] == name)


def load(folder):
    apps = []
    for key, label in APPS:
        runs = []
        for f in sorted(glob.glob(os.path.join(folder, f"res-{key}-*.json"))):
            run = json.load(open(f))
            samples = f[:-len(".json")] + ".samples.jsonl"
            run["samples"] = [json.loads(l) for l in open(samples)] if os.path.exists(samples) else []
            runs.append(run)
        apps.append((label, runs))
    return apps


def nice(v):
    for e in range(-1, 6):
        for s in [1, 2, 2.5, 5]:
            if v / (s * 10 ** e) <= 5: return s * 10 ** e
    return v / 5


def legend(svg, x0, y):
    for i, (_, label) in enumerate(APPS):
        svg.append(f'<rect class="f{i}" fill="{COLORS[i]}" x="{x0}" y="{y - 6}" width="14" height="4" rx="2"/>')
        svg.append(f'<text class="muted" fill="#52514e" x="{x0 + 20}" y="{y}">{label}</text>')
        x0 += 30 + 7.2 * len(label) + 20


def usage(apps, out):
    chosen, bounds = [], []
    for label, runs in apps:
        runs = sorted(runs, key=lambda r: step(r, "end")["end"] - step(r, "launch")["start"])
        run = runs[len(runs) // 2]
        start = step(run, "launch")["start"]
        chosen.append((label, run, start))
        bounds.append([0] + [step(run, name)["start"] - start for name, _ in PHASES] + [step(run, "end")["end"] - start])
    mean = [statistics.mean(b[i] for b in bounds) for i in range(len(bounds[0]))]

    def aligned(t, b):
        k = max(0, min(len(b) - 2, next((i for i in range(len(b) - 1) if t < b[i + 1]), len(b) - 2)))
        return mean[k] + (t - b[k]) / (b[k + 1] - b[k]) * (mean[k + 1] - mean[k])

    series = []
    for (label, run, start), b in zip(chosen, bounds):
        pts = [p for p in run["samples"] if start <= p["t"] <= start + b[-1]]
        cpu0 = pts[0]["cpu"] if pts else 0
        series.append((label, [(aligned(p["t"] - start, b), p["mb"], p["cpu"] - cpu0) for p in pts]))
    marks = mean[1:-1]
    W, PANEL, TOP, LEFT, RIGHT, GAP = 860, 220, 84, 64, 210, 70
    H = TOP + 2 * PANEL + GAP + 60
    tmax = max(p[0] for _, pts in series for p in pts)
    x = lambda t: LEFT + t / tmax * (W - LEFT - RIGHT)
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" {FONT}>', STYLE,
           f'<rect class="surface" fill="#fcfcfb" width="{W}" height="{H}" rx="8"/>',
           f'<text class="ink" fill="#0b0b0b" x="{LEFT}" y="26" font-size="15" font-weight="600">The whole scenario: memory and CPU time</text>']
    legend(svg, LEFT, 44)
    previous, raised = -1e9, False
    for t, (_, name) in zip(marks, PHASES):
        raised = x(t) - previous < 70 and not raised
        previous = x(t)
        ly = TOP - 26 if raised else TOP - 12
        svg.append(f'<line class="phase" stroke="#c9c8c2" stroke-dasharray="3 4" x1="{x(t):.1f}" x2="{x(t):.1f}" y1="{ly + 4}" y2="{TOP + 2 * PANEL + GAP - 24}"/>')
        svg.append(f'<text class="muted" fill="#52514e" x="{x(t) + 4:.1f}" y="{ly}">{name}</text>')

    def panel(y0, title, idx, unit, f):
        vmax = max(p[idx] for _, pts in series for p in pts) * 1.05
        tick = nice(vmax)
        top, bottom = y0 + 24, y0 + PANEL
        y = lambda v: bottom - v / vmax * (bottom - top)
        svg.append(f'<text class="ink" fill="#0b0b0b" x="{LEFT}" y="{y0 + 10}" font-weight="600">{title}</text>')
        v = 0
        while v <= vmax:
            svg.append(f'<line class="grid" stroke="#e4e3df" x1="{LEFT}" x2="{W - RIGHT}" y1="{y(v):.1f}" y2="{y(v):.1f}"/>')
            svg.append(f'<text class="muted" fill="#52514e" x="{LEFT - 8}" y="{y(v) + 4:.1f}" text-anchor="end">{f(v)}</text>')
            v += tick
        svg.append(f'<line class="axis" stroke="#b8b7b1" x1="{LEFT}" x2="{W - RIGHT}" y1="{bottom}" y2="{bottom}"/>')
        labels = []
        for i, (label, pts) in enumerate(series):
            columns = {}
            for t, *vals in pts:
                c = round(x(t))
                columns[c] = max(columns.get(c, 0), vals[idx - 1])
            d = " ".join(f"{'M' if k == 0 else 'L'}{c},{y(v):.1f}" for k, (c, v) in enumerate(sorted(columns.items())))
            svg.append(f'<path class="s{i}" stroke="{COLORS[i]}" d="{d}" fill="none" stroke-width="2" stroke-linejoin="round"/>')
            last = pts[-1][idx]
            labels.append([y(last), f"{label.split(' ')[0]}: {f(last)} {unit}"])
        labels.sort()
        for k in range(1, len(labels)): labels[k][0] = max(labels[k][0], labels[k - 1][0] + 16)
        for ly, text in labels:
            svg.append(f'<text class="ink" fill="#0b0b0b" x="{W - RIGHT + 8}" y="{ly + 4:.1f}">{text}</text>')
        return bottom

    b = panel(TOP, "Memory (all processes, physical footprint)", 1, "MB", lambda v: f"{v:,.0f}".replace(",", " "))
    b = panel(b + GAP - 24, "CPU time used so far (all cores)", 2, "s", lambda v: f"{v:,.0f}".replace(",", " ") if v >= 10 or v == 0 else f"{v:.1f}")
    v, tick = 0, nice(tmax / 60) * 60
    while v <= tmax:
        svg.append(f'<text class="muted" fill="#52514e" x="{x(v):.1f}" y="{b + 18}" text-anchor="middle">{v / 60:g} min</text>')
        v += tick
    svg.append(f'<text class="muted" fill="#52514e" x="{LEFT}" y="{H - 12}">Minutes since launch, the median run of each app, stretched a little within each phase so that the phases line up.</text>')
    svg.append("</svg>")
    open(out, "w").write("\n".join(svg))


def switches(apps, out, limit=400):
    rows = []
    for _, runs in apps:
        per_run = [step(r, "switches")["switches"] for r in runs]
        rows.append([statistics.median(run[i]["ms"] for run in per_run) for i in range(len(per_run[0]))])
    highest = max(v for values in rows for v in values)
    cap = min(limit, 100 * -(-highest // 100))
    kinds = [s["kind"] for s in step(apps[0][1][0], "switches")["switches"]]
    servers = [s["server"] for s in step(apps[0][1][0], "switches")["switches"]]
    W, TOP, LEFT, RIGHT, PANEL = 860, 84, 64, 24, 260
    H = TOP + PANEL + 76
    n = len(kinds)
    slot = (W - LEFT - RIGHT) / n
    bottom = TOP + PANEL
    y = lambda v: bottom - min(v, cap) / cap * PANEL
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" {FONT}>', STYLE,
           f'<rect class="surface" fill="#fcfcfb" width="{W}" height="{H}" rx="8"/>',
           f'<text class="ink" fill="#0b0b0b" x="{LEFT}" y="26" font-size="15" font-weight="600">Every switch: time until the posts are on screen (median of the runs)</text>']
    legend(svg, LEFT, 44)
    cut = f" Bars are cut at {cap} ms." if highest > cap else ""
    svg.append(f'<text class="muted" fill="#52514e" x="{LEFT}" y="{H - 12}">C channel, T team, S server switch, in the order of the scenario.{cut}</text>')
    v = 0
    while v <= cap:
        svg.append(f'<line class="grid" stroke="#e4e3df" x1="{LEFT}" x2="{W - RIGHT}" y1="{y(v):.1f}" y2="{y(v):.1f}"/>')
        svg.append(f'<text class="muted" fill="#52514e" x="{LEFT - 8}" y="{y(v) + 4:.1f}" text-anchor="end">{v} ms</text>')
        v += 100
    bar = slot * 0.36
    last_label = -1e9
    for i in range(n):
        x0 = LEFT + i * slot + slot * 0.14
        for a, values in enumerate(rows):
            v = values[i]
            svg.append(f'<rect class="f{a}" fill="{COLORS[a]}" x="{x0 + a * bar:.1f}" y="{y(v):.1f}" width="{bar - 1:.1f}" height="{bottom - y(v):.1f}"/>')
            if v > cap:
                lx = x0 + a * bar + bar / 2
                ly = TOP - 16 if lx - last_label < 28 else TOP - 4
                last_label = lx if ly == TOP - 4 else last_label
                text = f"{v / 1000:.1f} s" if v >= 1000 else f"{v:.0f}"
                svg.append(f'<text class="ink" fill="#0b0b0b" x="{lx:.1f}" y="{ly}" text-anchor="middle" font-size="10">{text}</text>')
        svg.append(f'<text class="muted" fill="#52514e" x="{LEFT + (i + 0.5) * slot:.1f}" y="{bottom + 16}" text-anchor="middle" font-size="10">{kinds[i][0].upper()}</text>')
        if i == 0 or servers[i] != servers[i - 1]:
            width = next((j for j in range(i, n) if servers[j] != servers[i]), n) - i
            name = f"server {servers[i] + 1}" if width >= 3 else str(servers[i] + 1)
            svg.append(f'<text class="muted" fill="#52514e" x="{LEFT + i * slot + 3:.1f}" y="{bottom + 34}" font-size="10">{name}</text>')
            svg.append(f'<line class="axis" stroke="#b8b7b1" x1="{LEFT + i * slot:.1f}" x2="{LEFT + i * slot:.1f}" y1="{bottom}" y2="{bottom + 24}"/>')
    svg.append(f'<line class="axis" stroke="#b8b7b1" x1="{LEFT}" x2="{W - RIGHT}" y1="{bottom}" y2="{bottom}"/>')
    svg.append("</svg>")
    open(out, "w").write("\n".join(svg))


def main():
    apps = load(sys.argv[1])
    usage(apps, sys.argv[2])
    if len(sys.argv) > 3: switches(apps, sys.argv[3])


if __name__ == "__main__":
    main()
