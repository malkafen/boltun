#!/usr/bin/env python3
"""Live traffic for the benchmark, posted by TRAFFIC_USER to all servers at once.
Usage: traffic.py run [per server] [delay s]   posts the same seeded plan every time (mentions of the bench user,
                                              direct messages, markdown, thread replies; a quarter of server 0's posts
                                              go to the channel the apps show, START)
       traffic.py reset                       marks every channel of the bench user read, so every run starts from
                                              the same unread state on the servers"""
import random, sys, threading, time
import scenario
from api import Server

LINES = [
    "Deploy finished, all green :white_check_mark:",
    "Can someone review my PR? https://github.com/mattermost/desktop/pulls",
    "**Reminder:** standup in 5 minutes",
    "```swift\nlet answer = 42\nprint(answer)\n```",
    "I think we should ship it :rocket:",
    "> quoted text\n\nand a reply below",
    "- item one\n- item two\n  - nested item\n- item three",
    "Lunch? :pizza: :coffee:",
    "| Build | Time | Result |\n| --- | ---: | --- |\n| macOS | 4m 12s | :white_check_mark: |\n| Linux | 3m 58s | :x: |",
    "### Release notes\n1. Faster sync\n2. Fewer crashes\n3. `--verbose` flag\n\nSee [the changelog](https://example.com/changelog).",
    "```python\ndef fib(n):\n    return n if n < 2 else fib(n - 1) + fib(n - 2)\n```",
    "_italic_, **bold**, ~~strike~~ and `inline code` in one line",
]


def channels(user):
    """Ids of the bench user's public channels on every team (but the history channel), by (team, channel name)."""
    uid = user.me["id"]
    found = {}
    for team in user.get(f"/users/{uid}/teams"):
        for c in user.get(f"/users/{uid}/teams/{team['id']}/channels"):
            if c["type"] == "O" and c["name"] != scenario.HISTORY[2]: found[(team["name"], c["name"])] = c["id"]
    return found


def plan(index, count, names):
    """(kind, channel key or None, message) for every post of one server; the same on every run."""
    rng = random.Random(f"boltun-bench-{index}")
    keys = sorted(names)
    start = (scenario.START[1], scenario.START[2])
    steps = []
    for i in range(count):
        roll = rng.random()
        line = rng.choice(LINES)
        if roll < 0.2:
            steps.append(("direct", None, line))
        elif roll < 0.3 and i > 3:
            steps.append(("reply", None, line))
        else:
            key = start if index == scenario.START[0] and rng.random() < 0.35 else rng.choice(keys)
            mention = rng.random() < 0.3
            steps.append(("channel", key, f"@{scenario.USER} {line}" if mention else line))
    return steps


def setup(index, count):
    _, url = scenario.SERVERS[index]
    admin = Server(url, scenario.TRAFFIC_USER, scenario.TRAFFIC_PASSWORD)
    user = Server(url, scenario.USER, scenario.PASSWORD)
    names = channels(user)
    direct = admin.dm(admin.me["id"], user.me["id"])["id"]
    return admin, names, direct, plan(index, count, names)


def play(index, prepared, delay, begin, log):
    admin, names, direct, steps = prepared
    posted = []
    for i, (kind, key, message) in enumerate(steps):
        time.sleep(max(0.0, begin + i * delay - time.time()))
        if kind == "reply":
            root = posted[i % len(posted)]
            body = {"channel_id": root["channel_id"], "root_id": root["id"], "message": message}
        else:
            body = {"channel_id": direct if kind == "direct" else names[key], "message": message}
        post = admin.post("/posts", body)
        if kind != "reply": posted.append(post)
    log.append((index, len(steps)))


def run(count, delay):
    prepared = [setup(i, count) for i in range(len(scenario.SERVERS))]
    begin = time.time() + 0.5
    log = []
    workers = [threading.Thread(target=play, args=(i, p, delay, begin, log)) for i, p in enumerate(prepared)]
    for w in workers: w.start()
    for w in workers: w.join()
    print(f"traffic: {count} posts on each of {len(log)} servers in {time.time() - begin:.0f} s")
    if len(log) != len(prepared): sys.exit("traffic: a server failed")


def reset():
    for name, url in scenario.SERVERS:
        user = Server(url, scenario.USER, scenario.PASSWORD)
        uid = user.me["id"]
        ids = {c["id"] for team in user.get(f"/users/{uid}/teams") for c in user.get(f"/users/{uid}/teams/{team['id']}/channels")}
        for cid in ids: user.post(f"/channels/members/{uid}/view", {"channel_id": cid})
        print(f"{name}: {len(ids)} channels marked read")


if __name__ == "__main__":
    if sys.argv[1] == "reset":
        reset()
    else:
        run(int(sys.argv[2]) if len(sys.argv) > 2 else scenario.TRAFFIC_PER_SERVER,
            float(sys.argv[3]) if len(sys.argv) > 3 else scenario.TRAFFIC_DELAY)
