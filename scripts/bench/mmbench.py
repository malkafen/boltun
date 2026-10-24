#!/usr/bin/env python3
"""Runs the benchmark scenario in Mattermost Desktop through the Chrome DevTools Protocol (see mmdrive.py).
Usage: mmbench.py prepare <Mattermost.app> <profile dir> <work dir>   a logged-in profile left on START
       mmbench.py run <Mattermost.app> <data dir> <work dir> <out.json>   one run on a copy of that profile
Times are Unix milliseconds taken inside the pages: a step starts at the page's own mousedown or wheel event and ends
at the first animation frame that shows the expected posts. Launch counts from the `open` call."""
import json, os, subprocess, sys, time
import scenario
from mmdrive import CLICK_CLOCK, Mattermost, longest_gap, quit_app
from sample import snapshot

PORT = int(os.environ.get("MM_CDP_PORT", "9229"))
BOUNDS = {"x": 100, "y": 60, "width": 1240, "height": 820, "maximized": False, "fullscreen": False}


def part(app):
    return os.path.realpath(app).rstrip("/") + "/"


def write_profile(data):
    os.makedirs(data, exist_ok=True)
    servers = [{"name": name, "url": url + "/", "order": i} for i, ((name, _), url) in enumerate(zip(scenario.SERVERS, scenario.APP_URLS))]
    config = {"version": 4, "servers": servers, "lastActiveServer": scenario.START[0], "autoCheckForUpdates": False,
              "autostart": False, "hideOnStart": False, "showTrayIcon": False, "enableMetrics": False, "enableSentry": False,
              "notifications": {"flashWindow": 0, "bounceIcon": False, "bounceIconType": "informational"}}
    json.dump(config, open(os.path.join(data, "config.json"), "w"), indent=2)
    json.dump(BOUNDS, open(os.path.join(data, "bounds-info.json"), "w"))


def launch(app, data):
    if subprocess.run(["pgrep", "-f", part(app)], capture_output=True).returncode == 0: raise RuntimeError("Mattermost is already running")
    t0 = time.time()
    subprocess.run(["open", "-n", "-a", app, "--args", f"--dataDir={data}", f"--remote-debugging-port={PORT}", "--use-mock-keychain"], check=True)
    return t0, Mattermost(PORT, scenario.APP_URLS)


class Driver:
    def __init__(self, mm):
        self.mm, self.places = mm, scenario.Places()

    def harness(self):
        for i in range(len(scenario.SERVERS)): self.mm.harness(i)

    def action(self, kind, server, team, channel):
        """(page or chrome CDP, element JS) to click for a switch; opens the server dropdown first."""
        mm = self.mm
        if kind == "server":
            return mm.open_dropdown(), mm.server_button(scenario.SERVERS[server][0])
        if kind == "team":
            return mm.page(server), mm.team_button(team)
        return mm.page(server), mm.channel_link(channel)

    def switch(self, kind, server, team, channel, pause=scenario.SWITCH_PAUSE):
        """Clicks like a user; returns ms until the target channel shows posts and the longest painted-frame gap."""
        mm = self.mm
        target = self.places.target(kind, server, team, channel)
        self.harness()
        cdp, element = self.action(kind, server, team, channel)
        if not cdp.eval(f"!!({element})"): raise RuntimeError(f"nothing to click for {kind} {server} {team} {channel}")
        for i in range(len(scenario.SERVERS)): mm.js(i, "__b.record()")
        mm.js(server, f"__b.arm(() => __b.waitPosts({json.dumps(target[1])}, {json.dumps(target[2])}, 30000))")
        before = mm.js(server, "JSON.stringify([__b.current(), document.hidden])")
        retries = 0
        while True:
            cdp.eval(CLICK_CLOCK)
            mm.click(cdp, element)
            shown = mm.js(server, "Promise.race([__b.result(), new Promise(r => setTimeout(() => r('pending'), 2000))])", 60)
            if shown != "pending" or mm.js(server, "JSON.stringify([__b.current(), document.hidden])") != before or retries == 3: break
            retries += 1
            if kind == "server" and not cdp.eval("document.visibilityState === 'visible'"): cdp, element = self.action(kind, server, team, channel)
        if shown == "pending": shown = mm.js(server, "__b.result()", 60)
        clicked = cdp.eval("window.__clickAt")
        time.sleep(pause)
        end = time.time() * 1000
        frames = [f for i in range(len(scenario.SERVERS)) for f in mm.js(i, "__b.stop()")]
        self.places.visit(*target)
        if not shown or not clicked: raise RuntimeError(f"{kind} switch to {target} did not show posts")
        return {"kind": kind, "server": server, "team": target[1], "channel": target[2],
                "ms": round(shown - clicked, 1), "freeze": round(longest_gap(frames, clicked, end), 1), "retries": retries}

    def go(self, server, team, channel):
        """Goes to a channel by clicks, through the server dropdown and the team sidebar when needed."""
        if self.places.server != server: self.switch("server", server, None, None, 0.3)
        if self.places.team[server] != team: self.switch("team", server, team, None, 0.3)
        if self.places.channel[(server, team)] != channel: self.switch("channel", server, team, channel, 0.3)

    def history(self):
        """Scrolls the history channel back to its first post with the mouse wheel; waits for older posts each time."""
        mm, server = self.mm, scenario.HISTORY[0]
        self.harness()
        center = mm.js(server, "__b.center('#postListContent')")
        if not center: raise RuntimeError("no post list")
        mm.js(server, CLICK_CLOCK.replace("'mousedown'", "'wheel'"))
        deadline, scrolls, result = time.time() + scenario.HISTORY_TIMEOUT, 0, None
        while time.time() < deadline:
            count = mm.js(server, "__b.postCount()")
            mm.js(server, f"__b.arm(() => __b.waitHistory({count}, {int(scenario.HISTORY_WAIT * 1000)}))")
            mm.wheel(server, center, -100000)
            scrolls += 1
            result = mm.js(server, "__b.result()", 60) or result
            if result and result["intro"]: break
        started = mm.js(server, "window.__clickAt")
        if not result or not result["intro"]: raise RuntimeError("history did not reach the first post")
        return {"ms": round(result["at"] - started, 1), "posts": result["count"], "scrolls": scrolls}

    def connected_at(self, timeout=120):
        """Unix ms when the last server's WebSocket connected (the webapp keeps the time it connected)."""
        mm, deadline = self.mm, time.time() + timeout
        at = {}
        while time.time() < deadline and len(at) < len(scenario.SERVERS):
            for i in range(len(scenario.SERVERS)):
                if i in at or not mm.has_page(i): continue
                try:
                    v = mm.js(i, "(() => { const s = window.store && window.store.getState(); return s && s.websocket.connected ? s.websocket.lastConnectAt : null; })()", 10)
                except (OSError, EOFError, StopIteration, RuntimeError):
                    mm.pages.pop(i, None); v = None
                if v: at[i] = v
            time.sleep(0.1)
        if len(at) < len(scenario.SERVERS): raise RuntimeError(f"connected only {sorted(at)}")
        return max(at.values())

    def first_posts(self, timeout=120):
        """Unix ms of the first frame that shows START's posts; checked from the moment the page can be reached."""
        mm, (server, team, channel) = self.mm, scenario.START
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                if mm.has_page(server):
                    mm.harness(server)
                    v = mm.js(server, f"__b.waitPosts({json.dumps(team)}, {json.dumps(channel)}, 2000)", 10)
                    if v: return v
            except (OSError, EOFError, StopIteration, RuntimeError):
                mm.pages.pop(server, None)
            time.sleep(0.05)
        raise RuntimeError("no posts after launch")


def prepare(app, data, work):
    write_profile(data)
    _, mm = launch(app, data)
    d = Driver(mm)
    for i in range(len(scenario.SERVERS)):
        if i:
            dd = mm.open_dropdown(); mm.click(dd, mm.server_button(scenario.SERVERS[i][0]))
        mm.login(i, scenario.USER, scenario.PASSWORD)
        print(f"logged in to {scenario.SERVERS[i][0]}", flush=True)
    for i in range(len(scenario.SERVERS)):
        mm.harness(i)
        if not mm.until(i, "__b.current() && __b.current().team && __b.current().channel"): raise RuntimeError("no current channel")
    current = {i: (lambda c: (c["team"], c["channel"]))(mm.js(i, "__b.current()")) for i in range(len(scenario.SERVERS))}
    d.places = scenario.Places()
    for i, (team, channel) in current.items():
        d.places.team[i] = team; d.places.channel[(i, team)] = channel
    d.places.server = len(scenario.SERVERS) - 1
    for place in scenario.PREPARE_VISITS + [scenario.START]:
        d.go(*place)
    print("visited every team, back on", scenario.START, flush=True)
    time.sleep(40)
    mm.quit(part(app))


def run(app, data, work, out):
    switches = scenario.switches(work)
    steps = []
    t0, mm = launch(app, data)
    d = Driver(mm)
    posts = d.first_posts()
    connected = d.connected_at()
    steps.append({"name": "launch", "start": t0, "end": max(posts, connected) / 1000,
                  "posts": round(posts - t0 * 1000), "connected": round(connected - t0 * 1000)})
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
    for i in range(len(scenario.SERVERS)): mm.js(i, "__b.watchLongTasks()")
    start = time.time()
    subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "traffic.py"), "run",
                    str(scenario.TRAFFIC_PER_SERVER), str(scenario.TRAFFIC_DELAY)], check=True)
    time.sleep(5)
    tasks = [mm.js(i, "__b.stopLongTasks()") for i in range(len(scenario.SERVERS))]
    shown = tasks[scenario.START[0]]
    steps.append({"name": "traffic", "start": start, "end": time.time(), "freeze": round(shown["max"], 1) if shown["count"] else None,
                  "long_tasks": shown["count"], "long_tasks_hidden": sum(t["count"] for i, t in enumerate(tasks) if i != scenario.START[0]),
                  **snapshot(part(app))})

    start = time.time(); time.sleep(scenario.IDLE_END)
    steps.append({"name": "end", "start": start, "end": time.time(), **snapshot(part(app))})
    mm.quit(part(app))
    json.dump({"app": "mattermost", "steps": steps}, open(out, "w"), indent=1)


if __name__ == "__main__":
    mode, app, data, work = sys.argv[1:5]
    try:
        prepare(app, data, work) if mode == "prepare" else run(app, data, work, sys.argv[5])
    finally:
        quit_app(part(app), 10)
