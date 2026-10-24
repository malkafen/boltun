#!/usr/bin/env python3
import json
import random
import sys
import time
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8065"
COUNT = int(sys.argv[2]) if len(sys.argv) > 2 else 20
DELAY = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
TARGET = sys.argv[4] if len(sys.argv) > 4 else "boltun"

LINES = [
    "Deploy finished, all green :white_check_mark:",
    "Can someone review my PR? https://github.com/mattermost/desktop/pulls",
    "**Reminder:** standup in 5 minutes",
    "```swift\nlet answer = 42\nprint(answer)\n```",
    "I think we should ship it :rocket:",
    "> quoted text\n\nand a reply below",
    "- item one\n- item two\n- item three",
    "Lunch? :pizza:",
]


OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def call(method, path, token=None, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + "/api/v4" + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with OPENER.open(req) as resp:
        return resp.headers.get("Token"), json.loads(resp.read() or b"null")


def login(user, password):
    token, me = call("POST", "/users/login", body={"login_id": user, "password": password})
    return token, me


def main():
    token, me = login("sysadmin", "Sys@dmin-sample1")
    _, target = call("GET", "/users/username/" + TARGET, token)
    _, teams = call("GET", "/users/%s/teams" % target["id"], token)
    channels = []
    for team in teams:
        _, chans = call("GET", "/users/%s/teams/%s/channels" % (target["id"], team["id"]), token)
        channels += [c for c in chans if c["type"] == "O"]
    _, direct = call("POST", "/channels/direct", token, [me["id"], target["id"]])
    for i in range(COUNT):
        roll = random.random()
        if roll < 0.2:
            channel, message = direct["id"], random.choice(LINES)
        elif roll < 0.4:
            channel, message = random.choice(channels)["id"], "@%s %s" % (TARGET, random.choice(LINES))
        else:
            channel, message = random.choice(channels)["id"], random.choice(LINES)
        call("POST", "/posts", token, {"channel_id": channel, "message": message})
        print("posted", i + 1, channel, message.splitlines()[0][:60], flush=True)
        time.sleep(DELAY)


if __name__ == "__main__":
    main()
