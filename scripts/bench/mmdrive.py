#!/usr/bin/env python3
"""Drives Mattermost Desktop through the Chrome DevTools Protocol like a user: real mouse clicks, wheel and key events.
Every server is a page target of its own (the webapp in a WebContentsView); the top bar and the server dropdown are
pages too. A small harness in each server page reports when the expected channel shows its posts (checked on every
animation frame, so the time is the frame that paints them) and records painted frames while a step runs: the longest
gap between frames is the longest time the window could not respond. Frames are recorded only during steps, so the
harness costs nothing while the app idles."""
import json, subprocess, time
from cdp import CDP, targets

HARNESS = r"""
(() => {
 if (window.__b) return 'ok';
 const b = window.__b = {frames: [], recording: false, longTasks: {max: 0, count: 0}};
 const loop = () => { if (!b.recording) return; b.frames.push(Date.now()); requestAnimationFrame(loop); };
 b.record = () => { b.frames = []; if (!b.recording) { b.recording = true; requestAnimationFrame(loop); } return true; };
 b.stop = () => { b.recording = false; const f = b.frames; b.frames = []; return f; };
 b.state = () => window.store && window.store.getState();
 b.current = () => {
   const s = b.state(); if (!s) return null;
   const ch = s.entities.channels.channels[s.entities.channels.currentChannelId];
   const team = s.entities.teams.teams[s.entities.teams.currentTeamId];
   return {channel: ch && ch.name, channelId: ch && ch.id, team: team && team.name};
 };
 b.onScreen = e => { if (!e) return false; const r = e.getBoundingClientRect(); return r.height > 0 && r.bottom > 0 && r.top < innerHeight; };
 b.postsVisible = () => {
   const s = b.state(); if (!s || document.hidden) return false;
   const ch = s.entities.channels.currentChannelId; if (!ch) return false;
   const posts = s.entities.posts.posts;
   for (const e of document.querySelectorAll('#postListContent [id^="post_"]')) {
     const p = posts[e.id.slice(5)];
     if (p && p.channel_id === ch && b.onScreen(e)) return true;
   }
   return false;
 };
 b.matches = (team, channel) => { const c = b.current(); return !!c && (!team || c.team === team) && (!channel || c.channel === channel); };
 b.waitFrame = (check, timeout) => new Promise(resolve => {
   const timer = setTimeout(() => resolve(null), timeout);
   const tick = () => { const v = check(); if (v) { clearTimeout(timer); resolve(v); } else requestAnimationFrame(tick); };
   requestAnimationFrame(tick);
 });
 b.waitPosts = (team, channel, timeout) => b.waitFrame(() => b.matches(team, channel) && b.postsVisible() && Date.now(), timeout);
 b.postCount = () => {
   const s = b.state(); const ch = s.entities.channels.currentChannelId;
   return (s.entities.posts.postsInChannel[ch] || []).reduce((n, block) => n + block.order.length, 0);
 };
 b.intro = () => b.onScreen(document.getElementById('channelIntro'));
 b.waitHistory = (count, timeout) => b.waitFrame(() => {
   if (b.intro()) return {intro: true, at: Date.now(), count: b.postCount()};
   const n = b.postCount(); return n > count ? {intro: false, at: Date.now(), count: n} : null;
 }, timeout);
 b.watchLongTasks = () => {
   b.longTasks = {max: 0, count: 0};
   if (b.observer) b.observer.disconnect();
   b.observer = new PerformanceObserver(list => { for (const e of list.getEntries()) { b.longTasks.count++; b.longTasks.max = Math.max(b.longTasks.max, e.duration); } });
   b.observer.observe({type: 'longtask'});
   return true;
 };
 b.stopLongTasks = () => { if (b.observer) b.observer.disconnect(); b.observer = null; return b.longTasks; };
 b.arm = make => { b.pending = make(); return true; };
 b.result = () => b.pending;
 b.center = sel => { const e = document.querySelector(sel); if (!e) return null; const r = e.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; };
 return 'installed';
})()
"""
CLICK_CLOCK = ("(() => { window.__clickAt = null; addEventListener('mousedown', e => { window.__clickAt = performance.timeOrigin + e.timeStamp; },"
               " {once: true, capture: true}); return true; })()")
RECT = "(e => { if (!e) return null; e.scrollIntoView({block: 'nearest'}); const r = e.getBoundingClientRect(); return r.width ? [r.x + r.width / 2, r.y + r.height / 2] : null; })"
KEYS = {"Enter": 13, "Escape": 27, "Tab": 9}


class Mattermost:
    def __init__(self, port, origins, timeout=120):
        self.port, self.origins = port, origins
        self.pages, self.chrome = {}, {}
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                if targets(port): break
            except OSError:
                pass
            time.sleep(0.05)

    def _target(self, match, cache, key):
        c = cache.get(key)
        if c is None:
            c = cache[key] = CDP(match, self.port)
        return c

    def page(self, i):
        return self._target(lambda p: p["url"].startswith(self.origins[i]), self.pages, i)

    def shell(self, name):
        return self._target(lambda p: p["url"] == f"mattermost-desktop://renderer/{name}.html", self.chrome, name)

    def js(self, i, expr, timeout=600):
        """Evaluates in server page i; a broken connection (the view was recreated) is opened again."""
        try:
            return self.page(i).eval(expr, timeout)
        except (OSError, EOFError, StopIteration):
            self.pages.pop(i, None)
            return self.page(i).eval(expr, timeout)

    def harness(self, i):
        return self.js(i, HARNESS)

    def has_page(self, i):
        try:
            return any(p["url"].startswith(self.origins[i]) for p in targets(self.port))
        except OSError:
            return False

    def click_xy(self, cdp, xy):
        cdp.call("Input.dispatchMouseEvent", type="mouseMoved", x=xy[0], y=xy[1])
        time.sleep(0.05)
        for t in ("mousePressed", "mouseReleased"):
            cdp.call("Input.dispatchMouseEvent", type=t, x=xy[0], y=xy[1], button="left", clickCount=1)

    def click(self, cdp, el_js):
        xy = cdp.eval(f"{RECT}({el_js})")
        if not xy: raise RuntimeError("no element " + el_js)
        self.click_xy(cdp, xy)

    def wheel(self, i, xy, dy):
        self.page(i).call("Input.dispatchMouseEvent", type="mouseWheel", x=xy[0], y=xy[1], deltaX=0, deltaY=dy)

    def type(self, i, text):
        self.page(i).call("Input.insertText", text=text)

    def key(self, cdp, key):
        for t in ("rawKeyDown", "keyUp"):
            cdp.call("Input.dispatchKeyEvent", type=t, key=key, code=key, windowsVirtualKeyCode=KEYS[key])

    def until(self, i, cond, timeout=60, interval=0.02):
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                if self.js(i, f"(() => {{ try {{ return !!({cond}); }} catch (e) {{ return false; }} }})()", 30): return True
            except (OSError, EOFError, StopIteration, RuntimeError):
                pass
            time.sleep(interval)
        return False

    def open_dropdown(self):
        top = self.shell("index")
        self.click(top, "document.querySelector('.ServerDropdownButton')")
        dd = self.shell("dropdown")
        deadline = time.time() + 10
        while time.time() < deadline:
            if dd.eval("document.visibilityState === 'visible' && document.querySelectorAll('.ServerDropdown__button').length > 0"): return dd
            time.sleep(0.02)
        raise RuntimeError("server dropdown did not open")

    def server_button(self, name):
        return f"[...document.querySelectorAll('.ServerDropdown__button')].find(e => e.innerText.trim().split('\\n')[0] === {json.dumps(name)})"

    def team_button(self, team):
        return f"document.querySelector('.team-sidebar a[href=\"/{team}\"]') || document.getElementById({json.dumps(team + 'TeamButton')})"

    def channel_link(self, channel):
        return f"document.getElementById({json.dumps('sidebarItem_' + channel)})"

    def login(self, i, user, password, timeout=60):
        if not self.until(i, "document.querySelector('#input_loginId') || location.pathname.includes('/channels/')", timeout): raise RuntimeError("no login page")
        if self.js(i, "location.pathname.includes('/channels/')"): return
        p = self.page(i)
        self.click(p, "document.querySelector('#input_loginId')"); self.type(i, user)
        self.click(p, "document.querySelector('#input_password-input')"); self.type(i, password)
        self.click(p, "document.querySelector('#saveSetting')")
        if not self.until(i, "location.pathname.includes('/channels/') && window.store.getState().websocket.connected", timeout): raise RuntimeError("login failed")

    def quit(self, part, timeout=60):
        quit_app(part, timeout)
        for c in list(self.pages.values()) + list(self.chrome.values()): c.close()


def quit_app(part, timeout=60):
    """SIGTERM to the main process (it shuts down like ⌘Q; the app cancels quit Apple events), then waits."""
    subprocess.run(["pkill", "-TERM", "-f", part + "Contents/MacOS/Mattermost"])
    deadline = time.time() + timeout
    while time.time() < deadline and subprocess.run(["pgrep", "-f", part], capture_output=True).returncode == 0:
        time.sleep(0.2)
    subprocess.run(["pkill", "-KILL", "-f", part])


def longest_gap(frames, start, end):
    """Longest time without a painted frame between start and end (ms, Unix time); a gap still open counts to end."""
    prev, gap = start, 0
    for f in sorted(x for x in frames if start <= x <= end):
        gap = max(gap, f - prev); prev = f
    return max(gap, end - prev)
