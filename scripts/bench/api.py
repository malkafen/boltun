#!/usr/bin/env python3
"""Mattermost REST v4 helper for the benchmark scripts (stdlib only, ignores HTTP proxies)."""
import json, urllib.request

OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class Server:
    def __init__(self, url, user, password):
        self.url = url.rstrip("/")
        self.token = None
        self.token, self.me = self.call("POST", "/users/login", {"login_id": user, "password": password}, raw=True)

    def call(self, method, path, body=None, raw=False):
        req = urllib.request.Request(self.url + "/api/v4" + path, data=json.dumps(body).encode() if body is not None else None, method=method)
        req.add_header("Content-Type", "application/json")
        if self.token: req.add_header("Authorization", "Bearer " + self.token)
        with OPENER.open(req, timeout=60) as resp:
            value = json.loads(resp.read() or b"null")
            return (resp.headers.get("Token"), value) if raw else value

    def get(self, path): return self.call("GET", path)
    def post(self, path, body): return self.call("POST", path, body)

    def user(self, username): return self.get(f"/users/username/{username}")
    def team(self, name): return self.get(f"/teams/name/{name}")

    def channel(self, team, name):
        try:
            return self.get(f"/teams/name/{team}/channels/name/{name}?include_deleted=true")
        except urllib.error.HTTPError as e:
            if e.code == 404: return None
            raise

    def dm(self, user_a, user_b):
        return self.post("/channels/direct", [user_a, user_b])
