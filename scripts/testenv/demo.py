#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8066"
ADMIN = ("sysadmin", "Sys@dmin-sample1")
ME = ("boltun", "Boltun-pass1")
PASSWORD = "Demo-pass1"
TEAM = ("northwind-hq", "Northwind")

PEOPLE = [
    ("emma.wilson", "Emma", "Wilson", "Product Manager", "#7c3aed", "#db2777"),
    ("liam.chen", "Liam", "Chen", "Backend Engineer", "#0ea5e9", "#2563eb"),
    ("sofia.garcia", "Sofia", "Garcia", "Product Designer", "#f97316", "#e11d48"),
    ("noah.patel", "Noah", "Patel", "Release Engineer", "#10b981", "#0d9488"),
]

CHANNELS = [
    ("engineering", "Engineering", "Backend, apps and infrastructure"),
    ("design", "Design", "Mockups, research and feedback"),
    ("releases", "Releases", "Release notes and rollout status"),
    ("random", "Random", "Coffee, links and everything else"),
]

OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def request(method, path, token=None, body=None, raw=None, content_type="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(BASE + "/api/v4" + path, data=data, method=method)
    req.add_header("Content-Type", content_type)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with OPENER.open(req) as resp:
            return resp.headers.get("Token"), json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as error:
        return None, {"status_code": error.code, "error": error.read().decode(errors="replace")}


def call(method, path, token=None, body=None):
    return request(method, path, token, body)[1]


def login(user, password):
    token, me = request("POST", "/users/login", body={"login_id": user, "password": password})
    if not token:
        sys.exit(f"login failed for {user}: {me}")
    return token, me


def upload(path, token, field, filename, data, mime, extra=None):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in (extra or {}).items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; filename="{filename}"\r\nContent-Type: {mime}\r\n\r\n'.encode())
    parts.append(data + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return request("POST", path, token, raw=b"".join(parts), content_type=f"multipart/form-data; boundary={boundary}")[1]


def render(*args):
    out = tempfile.mktemp(suffix=".png")
    subprocess.run(["magick", *args, out], check=True)
    with open(out, "rb") as handle:
        data = handle.read()
    os.remove(out)
    return data


def avatar(initials, start, end):
    return render(
        "-size", "512x512", f"gradient:{start}-{end}", "-rotate", "-45", "-gravity", "center", "-extent", "512x512",
        "-fill", "white", "-font", "DejaVu-Sans-Bold", "-pointsize", "160", "-annotate", "0", initials,
    )


def team_icon():
    return render(
        "-size", "512x512", "gradient:#2563eb-#7c3aed", "-gravity", "center",
        "-fill", "white", "-font", "DejaVu-Sans-Bold", "-pointsize", "300", "-annotate", "0", "N",
    )


def mockup():
    cards = []
    for index, (title, color) in enumerate([("Welcome", "#7c3aed"), ("Connect", "#0ea5e9"), ("Ready", "#10b981")]):
        x = 140 + index * 620
        cards += [
            "-fill", "#ffffff", "-draw", f"roundrectangle {x},260 {x + 540},1300 48,48",
            "-fill", color, "-draw", f"roundrectangle {x + 50},320 {x + 490},760 36,36",
            "-fill", "#1f2937", "-pointsize", "64", "-annotate", f"+{x + 60}+880", title,
            "-fill", "#e5e7eb", "-draw", f"roundrectangle {x + 60},940 {x + 480},970 15,15",
            "-fill", "#e5e7eb", "-draw", f"roundrectangle {x + 60},1000 {x + 400},1030 15,15",
            "-fill", color, "-draw", f"roundrectangle {x + 60},1160 {x + 480},1250 45,45",
            "-fill", "white", "-pointsize", "44", "-annotate", f"+{x + 200}+1222", "Continue",
        ]
    return render(
        "-size", "2000x1400", "gradient:#eef2ff-#fdf2f8", "-font", "DejaVu-Sans-Bold",
        "-fill", "#111827", "-pointsize", "72", "-annotate", "+140+180", "Onboarding v2",
        *cards,
    )


def ensure_user(admin, username, first, last, position):
    found = call("GET", f"/users/username/{username}", admin)
    if found.get("id"):
        return found
    return call("POST", "/users", admin, {
        "username": username, "email": f"{username}@northwind.example", "password": PASSWORD,
        "first_name": first, "last_name": last, "position": position,
    })


def ensure_team(admin):
    found = call("GET", f"/teams/name/{TEAM[0]}", admin)
    if found.get("id"):
        return found, False
    return call("POST", "/teams", admin, {"name": TEAM[0], "display_name": TEAM[1], "type": "O"}), True


def ensure_channel(admin, team, name, display, purpose):
    found = call("GET", f"/teams/{team}/channels/name/{name}", admin)
    if found.get("id"):
        return found
    return call("POST", "/channels", admin, {"team_id": team, "name": name, "display_name": display, "purpose": purpose, "type": "O"})


def post(token, channel, message, root="", file_ids=None, props=None):
    body = {"channel_id": channel, "message": message, "root_id": root}
    if file_ids:
        body["file_ids"] = file_ids
    if props:
        body["props"] = props
    created = call("POST", "/posts", token, body)
    time.sleep(0.25)
    return created["id"]


def react(token, user_id, post_id, emoji):
    call("POST", "/reactions", token, {"user_id": user_id, "post_id": post_id, "emoji_name": emoji})


def main():
    admin, _ = login(*ADMIN)
    me_token, me = login(*ME)
    team, created = ensure_team(admin)
    if not created:
        print(f"team {TEAM[0]} already exists, nothing to do")
        return
    upload(f"/teams/{team['id']}/image", admin, "image", "team.png", team_icon(), "image/png")

    people = {}
    for username, first, last, position, start, end in PEOPLE:
        user = ensure_user(admin, username, first, last, position)
        upload(f"/users/{user['id']}/image", admin, "image", "avatar.png", avatar(first[0] + last[0], start, end), "image/png")
        token, _ = login(username, PASSWORD)
        people[first.lower()] = (token, user)

    upload(f"/users/{me['id']}/image", admin, "image", "avatar.png", avatar("B", "#f59e0b", "#ef4444"), "image/png")
    member_ids = [me["id"]] + [user["id"] for _, user in people.values()]
    for user_id in member_ids:
        call("POST", f"/teams/{team['id']}/members", admin, {"team_id": team["id"], "user_id": user_id})

    channels = {"town-square": call("GET", f"/teams/{team['id']}/channels/name/town-square", admin)["id"]}
    for name, display, purpose in CHANNELS:
        channels[name] = ensure_channel(admin, team["id"], name, display, purpose)["id"]
        for user_id in member_ids:
            call("POST", f"/channels/{channels[name]}/members", admin, {"user_id": user_id})

    emma, liam, sofia, noah = (people[name] for name in ("emma", "liam", "sofia", "noah"))

    post(emma[0], channels["town-square"], "Welcome to **Northwind**! :wave: Quarterly planning notes are pinned in ~releases.")
    post(noah[0], channels["town-square"], "Office is closed on Friday, enjoy the long weekend :palm_tree:")

    post(noah[0], channels["releases"], "### Northwind 2.4.0 is rolling out :rocket:\n\n- Offline mode for the mobile apps\n- 40% faster sync on large workspaces\n- New onboarding flow\n\nRollout: **25%** today, **100%** on Thursday.")

    post(noah[0], channels["engineering"], "Good morning! :sunny: Nightly builds are green on all platforms.")
    post(emma[0], channels["engineering"], "Standup in 10 minutes. Agenda:\n1. Sync engine review\n2. Release 2.4 rollout\n3. Flaky UI tests")
    post(sofia[0], channels["engineering"], "I'll join a bit late, finishing the onboarding handoff :art:")
    post(liam[0], channels["engineering"], "Heads-up: `api-gateway` will restart at 10:30 for the TLS certificate rotation. Expect a few seconds of reconnects.")
    review = post(liam[0], channels["engineering"], "Morning! The **sync engine** rewrite is ready for review :rocket:\nIt replaces polling with a single WebSocket and batches writes.")
    for who, emoji in [(emma, "rocket"), (noah, "rocket"), (sofia, "tada"), (emma, "eyes")]:
        react(who[0], who[1]["id"], review, emoji)
    react(me_token, me["id"], review, "rocket")
    post(emma[0], channels["engineering"], "Benchmarks from the staging cluster:\n\n| Scenario | Before | After |\n|:--|--:|--:|\n| Cold start | 2.1 s | 0.6 s |\n| Sync 10k items | 14.3 s | 3.8 s |\n| Memory, idle | 410 MB | 96 MB |", root=review)
    post(noah[0], channels["engineering"], "Retry policy looks good to me:\n\n```swift\nlet policy = RetryPolicy(\n    attempts: 5,\n    backoff: .exponential(base: .milliseconds(250), cap: .seconds(8))\n)\ntry await sync.run(with: policy)\n```", root=review)
    post(me_token, channels["engineering"], "Reviewed, left two small comments. Ship it once CI is green :white_check_mark:", root=review)
    post(liam[0], channels["engineering"], "Thanks all! Merging after the last CI run :raised_hands:", root=review)

    table = post(emma[0], channels["engineering"], "Numbers from the staging cluster are in the thread above :point_up: the idle memory drop is the big one.")
    react(liam[0], liam[1]["id"], table, "fire")
    react(noah[0], noah[1]["id"], table, "fire")
    react(sofia[0], sofia[1]["id"], table, "+1")
    post(noah[0], channels["engineering"], "> Deploy to `staging-eu` finished in 4m 12s, all checks green :white_check_mark:\n\nI'll promote it to production after lunch.")
    ask = post(sofia[0], channels["engineering"], "@boltun could you double-check the error states on the new sync banner before we promote? Screens are in ~design")
    react(emma[0], emma[1]["id"], ask, "+1")

    files = upload("/files", sofia[0], "files", "onboarding-v2.png", mockup(), "image/png", {"channel_id": channels["design"]})
    mock = post(sofia[0], channels["design"], "New onboarding flow mockups :art: three steps instead of five. Feedback welcome!", file_ids=[files["file_infos"][0]["id"]])
    for who, emoji in [(emma, "heart_eyes"), (liam, "heart_eyes"), (noah, "+1")]:
        react(who[0], who[1]["id"], mock, emoji)
    post(emma[0], channels["design"], "Love the progress indicator. Can we try the **Connect** step with a lighter illustration?")

    post(liam[0], channels["random"], "Who's up for coffee at 11? :coffee:")

    direct = call("POST", "/channels/direct", emma[0], [emma[1]["id"], me["id"]])
    post(emma[0], direct["id"], "Hey! Are we still on for our 1:1 at 3pm?")
    post(emma[0], direct["id"], "I'd like to go over the Q4 roadmap draft :spiral_note_pad:")
    direct = call("POST", "/channels/direct", liam[0], [liam[1]["id"], me["id"]])
    post(liam[0], direct["id"], "Thanks for the quick review :pray:")
    for channel in channels.values():
        for item in call("GET", f"/channels/{channel}/posts?per_page=200", admin)["posts"].values():
            if item["type"].startswith("system_"):
                call("DELETE", f"/posts/{item['id']}", admin)
    call("PUT", f"/users/{me['id']}/preferences", me_token, [{"user_id": me["id"], "category": "display_settings", "name": "name_format", "value": "full_name"}])
    print(f"seeded team {TEAM[0]} on {BASE}")


if __name__ == "__main__":
    main()
