#!/usr/bin/env python3
"""Turns the runs in a results directory (res-<app>-<n>.json from mmbench.py and bbench.py, the res-*.samples.jsonl
that sample.py wrote next to them, sizes.json from run.sh) into Markdown tables: medians over the runs.
Usage: report.py <dir> [--short]   --short prints only the rows for the README"""
import bisect, glob, json, os, statistics, sys

APPS = [("mattermost", "Mattermost Desktop 6.3.1"), ("boltun", "Boltun")]


def load(folder):
    apps = []
    for key, label in APPS:
        runs = []
        for f in sorted(glob.glob(os.path.join(folder, f"res-{key}-*.json"))):
            r = json.load(open(f))
            samples = f[:-len(".json")] + ".samples.jsonl"
            r["samples"] = [json.loads(l) for l in open(samples)] if os.path.exists(samples) else []
            runs.append(r)
        apps.append((key, label, runs))
    sizes_path = os.path.join(folder, "sizes.json")
    return apps, json.load(open(sizes_path)) if os.path.exists(sizes_path) else {}


def step(run, name):
    return next((s for s in run["steps"] if s["name"] == name), None)


def switches(run, kind=None):
    return [s["ms"] for s in step(run, "switches")["switches"] if kind in (None, s["kind"])]


def median(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


def cpu_at(samples, t):
    i = bisect.bisect_right([x["t"] for x in samples], t) - 1
    return samples[max(0, i)]["cpu"]


def window(run, a, b):
    """CPU seconds, peak MB, average MB and duration of the samples between Unix times a and b."""
    sm = run["samples"]
    if not sm: return None
    inside = [x for x in sm if a <= x["t"] <= b] or [min(sm, key=lambda x: abs(x["t"] - b))]
    return cpu_at(sm, b) - cpu_at(sm, a), max(x["mb"] for x in inside), statistics.mean(x["mb"] for x in inside), b - a


def span(first, last=None):
    return lambda r: (step(r, first)["start"], step(r, last or first)["end"])


TIMES = [
    ("Launch until the first channel shows its posts", lambda r: step(r, "launch")["posts"], "ms"),
    ("Launch until all three servers are connected", lambda r: step(r, "launch")["connected"], "ms"),
    ("Switch channel, team or server (median of {n})", lambda r: median(switches(r)), "ms"),
    ("— channel switches only (median of {n_channel})", lambda r: median(switches(r, "channel")), "ms"),
    ("— team switches only (median of {n_team})", lambda r: median(switches(r, "team")), "ms"),
    ("— server switches only (median of {n_server})", lambda r: median(switches(r, "server")), "ms"),
    ("— slowest switch", lambda r: max(switches(r)), "ms"),
    ("— longest freeze while switching", lambda r: max(s["freeze"] for s in step(r, "switches")["switches"]), "ms"),
    ("Open a channel with 1000 posts", lambda r: step(r, "history_open")["ms"], "ms"),
    ("Scroll it back to its first post", lambda r: step(r, "history")["ms"], "ms"),
    ("Longest freeze during 3 min of live traffic", lambda r: step(r, "traffic")["freeze"], "freeze"),
]
MEMORY = [
    ("Memory, idle 60 s after launch", lambda r: step(r, "idle")["mb"], "MB"),
    ("Memory after {n} switches", lambda r: step(r, "switches")["mb"], "MB"),
    ("Memory after scrolling back 1000 posts", lambda r: step(r, "history")["mb"], "MB"),
    ("Memory after 3 min of live traffic", lambda r: step(r, "traffic")["mb"], "MB"),
    ("Memory after 2 min idle at the end", lambda r: step(r, "end")["mb"], "MB"),
    ("Processes / threads, idle after launch", lambda r: (step(r, "idle")["processes"], step(r, "idle")["threads"]), "pair"),
]
PHASES = [
    ("Launch until ready", span("launch"), "cpu"),
    ("Idle 60 s after launch", span("idle"), "idle"),
    ("{n} switches", span("switches"), "cpu"),
    ("Open and scroll back 1000 posts", span("history_open", "history"), "cpu"),
    ("3 min of live traffic", span("traffic"), "cpu"),
    ("— average load during the traffic", span("traffic"), "idle"),
    ("Idle 2 min at the end", span("end"), "idle"),
    ("**Whole scenario**", span("launch", "end"), "cpu"),
]
SHORT = {
    "Launch until the first channel shows its posts": "Launch until the first channel shows its posts",
    "Launch until all three servers are connected": "Launch until all three servers are connected",
    "Switch channel, team or server (median of {n})": "Switch channel, team or server (median)",
    "Scroll it back to its first post": "Scroll a 1000-post channel back to its start",
    "Memory, idle 60 s after launch": "Memory, idle after launch",
    "Memory after 3 min of live traffic": "Memory after 3 min of live traffic",
    "3 min of live traffic": "CPU time for 3 min of live traffic",
    "Idle 2 min at the end": "CPU when idle at the end",
    "App size on disk": "App size on disk",
}


def fmt(v, unit):
    if v is None: return "< 50 ms" if unit == "freeze" else "—"
    if unit == "MB": return f"{v:,.0f} MB".replace(",", " ")
    if unit == "pair": return f"{v[0]:.0f} / {v[1]:.0f}"
    return f"{v / 1000:.1f} s" if v >= 1000 else f"{v:.0f} ms"


def cpu(v): return "—" if v is None else f"{v:.1f} s" if v >= 0.95 else f"{v * 1000:.0f} ms"


def per_run(runs, f, unit):
    values = [f(r) for r in runs]
    if values and isinstance(values[0], tuple): return tuple(median(v[i] for v in values) for i in range(len(values[0])))
    if unit == "freeze":
        m = median(-1 if v is None else v for v in values)
        return None if m is None or m < 0 else m
    return median(values)


def phase(runs, f, kind):
    windows = [w for w in (window(r, *f(r)) for r in runs) if w]
    if not windows: return "—"
    if kind == "idle": return f"{median(w[0] / w[3] * 100 for w in windows):.1f} % of a core"
    return f"{cpu(median(w[0] for w in windows))} / {fmt(median(w[1] for w in windows), 'MB')}"


def main():
    folder = sys.argv[1]
    short = "--short" in sys.argv
    apps, sizes = load(folder)
    first = apps[0][2][0]
    counts = {"n": len(switches(first))}
    for kind in ("channel", "team", "server"): counts[f"n_{kind}"] = len(switches(first, kind))
    header = "| | " + " | ".join(label for _, label, _ in apps) + " |\n|:--|" + "--:|" * len(apps)
    rows = []
    for title, f, unit in TIMES + MEMORY:
        rows.append((title, [fmt(per_run(runs, f, unit), unit) for _, _, runs in apps]))
    rows.append(("App size on disk", [fmt(sizes[key] / 1048576, "MB") if key in sizes else "—" for key, _, _ in apps]))
    cpu_rows = [(title, [phase(runs, f, kind) for _, _, runs in apps]) for title, f, kind in PHASES]
    whole = span("launch", "end")
    cpu_rows.append(("— wall time", [f"{median(b - a for a, b in map(whole, runs)):.0f} s" for _, _, runs in apps]))
    averages = lambda runs: [w[2] for w in (window(r, *whole(r)) for r in runs) if w]
    cpu_rows.append(("— average memory", [fmt(median(averages(runs)), "MB") for _, _, runs in apps]))
    if short:
        print(header)
        for title, cells in rows + cpu_rows:
            if title in SHORT: print(f"| {SHORT[title]} | " + " | ".join(c.split(" / ")[0] for c in cells) + " |")
        return
    print(header)
    for title, cells in rows: print(f"| {title.format(**counts)} | " + " | ".join(cells) + " |")
    print()
    print("| CPU time (all cores) / peak memory | " + " | ".join(label for _, label, _ in apps) + " |")
    print("|:--|" + "--:|" * len(apps))
    for title, cells in cpu_rows: print(f"| {title.format(**counts)} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
