#!/usr/bin/env python3
"""The benchmark scenario, shared by both drivers (mmbench.py for Mattermost Desktop, bbench.py for Boltun).
Both apps start on server 0, team ad-1, Town Square (prepare_profiles leaves them there)."""
import json, os
from api import Server

HOST = os.environ.get("BENCH_HOST", "192.168.15.101")
PORTS = [8065, 8066, 8067]
# The apps reach every server under a host name of its own (run.sh maps them to HOST in /etc/hosts): browsers keep
# cookies per host, not per port, so Mattermost Desktop cannot stay logged in to three servers on one address.
ALIASES = [f"bench-{port}.test" for port in PORTS]
SERVERS = [(name, f"http://{HOST}:{port}") for name, port in zip(["Server 8065", "Server 8066", "Enterprise 8067"], PORTS)]
APP_URLS = [f"http://{alias}:{port}" for alias, port in zip(ALIASES, PORTS)]
USER, PASSWORD = "boltun", "Boltun-pass1"
TRAFFIC_USER, TRAFFIC_PASSWORD = "sysadmin", "Sys@dmin-sample1"
START = (0, "ad-1", "town-square")
HISTORY = (0, "ad-1", "bench-history")
HISTORY_POSTS = 1000
QUICK = os.environ.get("BENCH_QUICK") == "1"  # a short rehearsal of the scenario, for trying the drivers
IDLE_AFTER_LAUNCH = 5 if QUICK else 60
IDLE_END = 5 if QUICK else 120
SWITCH_PAUSE = 1.5
TRAFFIC_PER_SERVER, TRAFFIC_DELAY = (4, 1.0) if QUICK else (60, 3.0)
HISTORY_WAIT = 0.25  # scroll to the top again if no older posts arrived by then, like a user flicking the wheel
HISTORY_TIMEOUT = 180

# (kind, server, team, channel). "server" lands on the server's current team and channel, as a click on a server
# does. "team" lands on Town Square in both apps here: Mattermost reopens the team's last channel, Boltun opens Town
# Square, so every team is left on Town Square before it is switched back to. "@sysadmin" is the direct message with
# that user.
SWITCHES = [
    ("channel", 0, "ad-1", "sint-9"),
    ("channel", 0, "ad-1", "culpa-5"),
    ("channel", 0, "ad-1", "@sysadmin"),
    ("channel", 0, "ad-1", "quod-7"),
    ("channel", 0, "ad-1", "boltun-kit-live"),
    ("channel", 0, "ad-1", "town-square"),
    ("team", 0, "reiciendis-0", None),
    ("channel", 0, "reiciendis-0", "et-0"),
    ("channel", 0, "reiciendis-0", "qui-4"),
    ("channel", 0, "reiciendis-0", "rem-3"),
    ("team", 0, "amet-2", None),
    ("channel", 0, "amet-2", "adipisci-7"),
    ("channel", 0, "amet-2", "magni-8"),
    ("server", 1, None, None),
    ("channel", 1, "nisi-1", "porro-7"),
    ("channel", 1, "nisi-1", "minima-6"),
    ("channel", 1, "nisi-1", "@sysadmin"),
    ("channel", 1, "nisi-1", "explicabo-3"),
    ("channel", 1, "nisi-1", "town-square"),
    ("team", 1, "tenetur-0", None),
    ("channel", 1, "tenetur-0", "aperiam-1"),
    ("channel", 1, "tenetur-0", "eos-6"),
    ("server", 2, None, None),
    ("channel", 2, "alpha", "off-topic"),
    ("channel", 2, "alpha", "boltun-read-info-live"),
    ("team", 2, "beta", None),
    ("channel", 2, "beta", "off-topic"),
    ("server", 0, None, None),
    ("channel", 0, "amet-2", "a-3"),
    ("team", 0, "ad-1", None),
    ("channel", 0, "ad-1", "sint-9"),
    ("server", 1, None, None),
    ("team", 1, "nisi-1", None),
    ("server", 2, None, None),
    ("server", 0, None, None),
]

# Every team of every server, visited while the profiles are prepared so that both apps remember the same
# last channel per team and per server: the last team listed for a server is where a "server" switch lands.
PREPARE_VISITS = [
    (0, "reiciendis-0", "town-square"), (0, "amet-2", "town-square"), (0, "ad-1", "town-square"),
    (1, "tenetur-0", "town-square"), (1, "nisi-1", "town-square"),
    (2, "beta", "town-square"), (2, "alpha", "town-square"),
]


class Places:
    """Where each server and team was left, starting from the prepared profiles, to know where a switch lands."""
    def __init__(self):
        self.team, self.channel = {}, {}
        for place in PREPARE_VISITS + [START]: self.visit(*place)

    def visit(self, server, team, channel):
        self.server, self.team[server], self.channel[(server, team)] = server, team, channel

    def target(self, kind, server, team, channel):
        team = self.team[server] if kind == "server" else team
        channel = self.channel[(server, team)] if kind in ("server", "team") else channel
        return server, team, channel


def direct_channels(work):
    """Names of the direct message channels with TRAFFIC_USER, per server, cached in the work directory."""
    path = os.path.join(work, "direct-channels.json")
    if os.path.exists(path): return json.load(open(path))
    names = {}
    for i, (_, url) in enumerate(SERVERS):
        s = Server(url, USER, PASSWORD)
        other = s.user(TRAFFIC_USER)["id"]
        names[str(i)] = s.dm(s.me["id"], other)["name"]
    json.dump(names, open(path, "w"))
    return names


def channel_ids(work):
    """Ids of every channel a switch lands on, as "server/team/name", cached in the work directory."""
    path = os.path.join(work, "channel-ids.json")
    if os.path.exists(path): return json.load(open(path))
    places = Places()
    wanted = set()
    for kind, server, team, channel in switches(work) + [("channel",) + HISTORY, ("channel",) + START]:
        target = places.target(kind, server, team, channel)
        places.visit(*target)
        wanted.add(target)
    ids = {}
    for server, team, name in sorted(wanted):
        s = Server(SERVERS[server][1], USER, PASSWORD)
        direct = "__" in name
        ids[f"{server}/{team}/{name}"] = (s.dm(*name.split("__")) if direct else s.get(f"/teams/name/{team}/channels/name/{name}"))["id"]
    json.dump(ids, open(path, "w"), indent=1)
    return ids


def switches(work):
    dms = direct_channels(work)
    return [(kind, server, team, dms[str(server)] if channel == "@" + TRAFFIC_USER else channel)
            for kind, server, team, channel in SWITCHES]
