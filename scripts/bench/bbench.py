#!/usr/bin/env python3
"""Runs the benchmark scenario in Boltun through its debug automation (boltun://debug/..., see docs/automation.md).
Usage: bbench.py prepare <Boltun Bench.app> <home dir> <work dir>   a logged-in home left on START
       bbench.py run <Boltun Bench.app> <home dir> <work dir> <out.json>   one run on a copy of that home
The app runs with CFFIXED_USER_HOME=<home dir>, so its state, credentials and caches live there. Times come from the
app's automation probe: a step starts when the app receives the command and ends when the first rows of the expected
channel are on screen (stamped after the frame is committed). Launch counts from the `open` call."""
import json, os, subprocess, sys, time
import scenario
from sample import snapshot

LOG = "/tmp/boltun-automation.log"
BUNDLE_ID = "io.github.malkafen.boltun.bench"
SCREEN_HEIGHT = 1003


def part(app):
    return os.path.realpath(app).rstrip("/") + "/"


class Boltun:
    def __init__(self, app):
        self.app = app

    def running(self):
        return subprocess.run(["pgrep", "-f", part(self.app) + "Contents/MacOS/"], capture_output=True).returncode == 0

    def launch(self, home):
        if self.running(): raise RuntimeError("Boltun Bench is already running")
        t0 = time.time()
        subprocess.run(["open", "-n", "-a", self.app, "--env", f"CFFIXED_USER_HOME={home}"], check=True)
        while not self.running(): time.sleep(0.01)
        return t0

    def send(self, command, timeout=120):
        """Sends one command and returns its log detail; raises on an error line."""
        start = os.path.getsize(LOG) if os.path.exists(LOG) else 0
        path = "/" + command.split("?")[0]
        subprocess.run(["open", "-g", "-a", self.app, "boltun://debug/" + command], check=True)
        deadline = time.time() + timeout
        while time.time() < deadline:
            if os.path.exists(LOG):
                with open(LOG) as f:
                    f.seek(start)
                    for line in f.read().splitlines():
                        _, status, rest = line.split(" ", 2)
                        cmd, _, detail = rest.partition(" ")
                        if cmd != path: continue
                        if status != "ok": raise RuntimeError(f"{command}: {detail}")
                        return detail
            time.sleep(0.01)
        raise RuntimeError(f"{command}: no answer")

    def probe(self, query, timeout=60):
        return json.loads(self.send(f"probe?{query}&timeout={timeout}", timeout + 30))

    def quit(self, timeout=60):
        try:
            self.send("quit", 5)
        except RuntimeError:
            pass
        deadline = time.time() + timeout
        while self.running() and time.time() < deadline: time.sleep(0.2)
        subprocess.run(["pkill", "-KILL", "-f", part(self.app) + "Contents/MacOS/"])


def select(server, team=None, channel=None):
    return f"select?server={server}" + (f"&team={team}" if team else "") + (f"&channel={channel}" if channel else "")


class Driver:
    def __init__(self, app, work):
        self.b, self.places, self.ids = Boltun(app), scenario.Places(), scenario.channel_ids(work)

    def switch(self, kind, server, team, channel, pause=scenario.SWITCH_PAUSE):
        target = self.places.target(kind, server, team, channel)
        self.b.send(select(server, team, channel))
        shown = self.b.probe("wait=posts", 30)
        time.sleep(pause)
        freeze = self.b.probe("freeze=1")["freeze"]
        self.places.visit(*target)
        expected = self.ids.get("/".join(map(str, target)))
        if expected and shown["channel"] != expected: raise RuntimeError(f"{kind} switch landed on {shown['channel']}, not {target}")
        return {"kind": kind, "server": server, "team": target[1], "channel": target[2],
                "ms": round((shown["shown"] - shown["command"]) * 1000, 1), "freeze": round(freeze, 1), "retries": 0}

    def go(self, server, team, channel):
        self.b.send(select(server, team, channel))
        self.b.probe("wait=posts", 30)
        self.places.visit(server, team, channel)

    def history(self):
        """Scrolls the history channel to the top until its first post shows; waits for older posts each time."""
        deadline, scrolls, first, report = time.time() + scenario.HISTORY_TIMEOUT, 0, None, None
        count = self.b.probe("wait=history")["count"]
        while time.time() < deadline:
            self.b.send("scroll?to=top")
            scrolls += 1
            report = self.b.probe(f"wait=history&count={count}", scenario.HISTORY_WAIT)
            first = first or report["command"]
            count = report["count"]
            if report.get("intro"): break
        if not report or not report.get("intro"): raise RuntimeError("history did not reach the first post")
        return {"ms": round((report["shown"] - first) * 1000, 1), "posts": report["count"], "scrolls": scrolls}


def window_frame():
    frame = f"100 {SCREEN_HEIGHT - 60 - 820} 1240 820 0 0 1800 {SCREEN_HEIGHT}"
    subprocess.run(["defaults", "write", BUNDLE_ID, "NSWindow Frame BoltunMainWindow", frame], check=True)


def prepare(app, home, work):
    os.makedirs(home, exist_ok=True)
    window_frame()
    d = Driver(app, work)
    d.b.launch(home)
    for (name, _), url in zip(scenario.SERVERS, scenario.APP_URLS):
        d.b.send(f"add-server?url={url}&name={name.replace(' ', '%20')}")
    for i in range(len(scenario.SERVERS)):
        d.b.send(f"login?server={i}&user={scenario.USER}&password={scenario.PASSWORD}")
        print(f"logged in to {scenario.SERVERS[i][0]}", flush=True)
    d.b.probe("wait=connected")
    for place in scenario.PREPARE_VISITS + [scenario.START]:
        d.go(*place)
    print("visited every team, back on", scenario.START, flush=True)
    time.sleep(5)
    d.b.quit()


def run(app, home, work, out):
    switches = scenario.switches(work)
    d = Driver(app, work)
    window_frame()
    steps = []
    t0 = d.b.launch(home)
    posts = d.b.probe("wait=posts&since=launch", 120)
    connected = d.b.probe("wait=connected", 120)
    end = max(posts["shown"], connected["connected"])
    if posts["channel"] != d.ids["/".join(map(str, scenario.START))]: raise RuntimeError("launch did not land on START")
    steps.append({"name": "launch", "start": t0, "end": end,
                  "posts": round((posts["shown"] - t0) * 1000), "connected": round((connected["connected"] - t0) * 1000)})
    print(f"launch: posts {steps[-1]['posts']} ms, connected {steps[-1]['connected']} ms", flush=True)

    start = time.time(); time.sleep(scenario.IDLE_AFTER_LAUNCH)
    steps.append({"name": "idle", "start": start, "end": time.time(), **snapshot(part(app))})

    start, results = time.time(), []
    for s in switches:
        results.append(d.switch(*s))
    steps.append({"name": "switches", "start": start, "end": time.time(), "switches": results, **snapshot(part(app))})
    print("switches:", sorted(r["ms"] for r in results), flush=True)

    d.go(*scenario.START)
    start = time.time()
    opened = d.switch("channel", *scenario.HISTORY)
    steps.append({"name": "history_open", "start": start, "end": time.time(), "ms": opened["ms"], "freeze": opened["freeze"]})
    start = time.time()
    h = d.history()
    time.sleep(scenario.SWITCH_PAUSE)
    steps.append({"name": "history", "start": start, "end": time.time(), **h, **snapshot(part(app))})
    print(f"history: {h}", flush=True)

    d.go(*scenario.START)
    time.sleep(5)
    start = time.time()
    subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "traffic.py"), "run",
                    str(scenario.TRAFFIC_PER_SERVER), str(scenario.TRAFFIC_DELAY)], check=True)
    time.sleep(5)
    freeze = d.b.probe(f"freeze=1&since={start}")["freeze"]
    steps.append({"name": "traffic", "start": start, "end": time.time(), "freeze": round(freeze, 1), **snapshot(part(app))})

    start = time.time(); time.sleep(scenario.IDLE_END)
    steps.append({"name": "end", "start": start, "end": time.time(), **snapshot(part(app))})
    d.b.quit()
    json.dump({"app": "boltun", "steps": steps}, open(out, "w"), indent=1)


if __name__ == "__main__":
    mode, app, home, work = sys.argv[1:5]
    try:
        prepare(app, home, work) if mode == "prepare" else run(app, home, work, sys.argv[5])
    finally:
        Boltun(app).quit(10)
