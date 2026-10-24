#!/usr/bin/env python3
"""Prepares the server data once, before all runs. Idempotent: run it again and it only fills what is missing.
- Creates the public channel bench-history in team ad-1 on the first server with HISTORY_POSTS posts by two authors
  (Markdown, code, lists, quotes, links, emoji), so the history step has a long channel to scroll back through.
- Tops up every channel and direct message the scenario visits to at least MIN_POSTS posts, so each switch has posts
  to show.
- Lists the direct messages with TRAFFIC_USER in the sidebar and marks the webapp's onboarding as done.
Seeded: every run writes the same text."""
import random, sys, urllib.error
import scenario
from api import Server

MIN_POSTS = 30
WORDS = ("deploy release build review merge branch server client latency cache index query socket retry token session "
         "channel thread reply mention badge sidebar render layout memory profile metric alert backup rollout").split()


def message(rnd, i):
    w = lambda n: " ".join(rnd.choice(WORDS) for _ in range(n))
    r = rnd.random()
    if r < .45: return f"{w(rnd.randint(4, 30)).capitalize()}. #{i}"
    if r < .55: return f"**{w(2)}** {w(rnd.randint(5, 15))} `{rnd.choice(WORDS)}()` #{i}"
    if r < .65: return "\n".join(f"- {w(rnd.randint(2, 8))}" for _ in range(rnd.randint(2, 5))) + f"\n#{i}"
    if r < .73: return f"```swift\nlet {rnd.choice(WORDS)} = {rnd.randint(1, 999)}\nprint({rnd.choice(WORDS)})\n```\n#{i}"
    if r < .80: return f"> {w(rnd.randint(5, 12))}\n\n{w(rnd.randint(3, 9))} #{i}"
    if r < .88: return f"See https://example.com/{rnd.choice(WORDS)}/{i} for the {w(3)}"
    if r < .95: return f"{w(rnd.randint(3, 8))} :{rnd.choice(['rocket', 'tada', 'white_check_mark', 'eyes', 'fire'])}: #{i}"
    return "\n\n".join(w(rnd.randint(12, 30)).capitalize() + "." for _ in range(rnd.randint(2, 4))) + f" #{i}"


def regular_posts(server, channel_id):
    count, page = 0, 0
    while True:
        batch = server.get(f"/channels/{channel_id}/posts?page={page}&per_page=200")
        count += sum(1 for p in batch["posts"].values() if not p.get("type"))
        if len(batch["order"]) < 200: return count
        page += 1


def history(admin, user):
    _, team, name = scenario.HISTORY
    team_id = admin.team(team)["id"]
    channel = admin.channel(team, name)
    if channel is None:
        channel = admin.post("/channels", {"team_id": team_id, "name": name, "display_name": "Bench History", "type": "O",
                                           "purpose": f"{scenario.HISTORY_POSTS} posts for the history step of the benchmark"})
    if channel.get("delete_at"):
        admin.call("POST", f"/channels/{channel['id']}/restore")
    admin.post(f"/channels/{channel['id']}/members", {"user_id": user.me["id"]})
    have = regular_posts(admin, channel["id"])
    rnd = random.Random(42)
    for i in range(scenario.HISTORY_POSTS):
        text = message(rnd, i + 1)
        author = user if rnd.random() < .2 else admin
        if i < have: continue
        author.post("/posts", {"channel_id": channel["id"], "message": text})
        if (i + 1) % 100 == 0: print(f"bench-history: {i + 1} posts", flush=True)
    print(f"bench-history: {max(have, scenario.HISTORY_POSTS)} posts")


def top_up(admins):
    targets = {(s, t, c) for _, s, t, c in scenario.SWITCHES if t and c and not c.startswith("@")}
    targets |= set(scenario.PREPARE_VISITS)
    rnd = random.Random(7)
    for server, team, name in sorted(targets):
        try:
            channel = admins[server].channel(team, name)
        except urllib.error.HTTPError:
            channel = None
        if channel is None:
            print(f"skip {scenario.SERVERS[server][0]} {team}/{name}: not visible to {scenario.TRAFFIC_USER}")
            continue
        missing = MIN_POSTS - channel["total_msg_count"]
        for i in range(max(0, missing)):
            try:
                admins[server].post("/posts", {"channel_id": channel["id"], "message": message(rnd, i + 1)})
            except urllib.error.HTTPError as e:
                print(f"skip {scenario.SERVERS[server][0]} {team}/{name}: {e.code}")
                break
        if missing > 0: print(f"{scenario.SERVERS[server][0]} {team}/{name}: added {missing} posts")
    for server in sorted({s for _, s, _, c in scenario.SWITCHES if c == "@" + scenario.TRAFFIC_USER}):
        admin = admins[server]
        user = Server(scenario.SERVERS[server][1], scenario.USER, scenario.PASSWORD)
        channel = admin.dm(admin.me["id"], user.me["id"])
        missing = MIN_POSTS - regular_posts(admin, channel["id"])
        for i in range(max(0, missing)):
            (user if rnd.random() < .4 else admin).post("/posts", {"channel_id": channel["id"], "message": message(rnd, i + 1)})
        if missing > 0: print(f"{scenario.SERVERS[server][0]} direct message with {scenario.TRAFFIC_USER}: added {missing} posts")


def show_direct_messages(admins):
    """Lists the direct message with TRAFFIC_USER in the sidebar, as opening it once does."""
    for (name, url), admin in zip(scenario.SERVERS, admins):
        user = Server(url, scenario.USER, scenario.PASSWORD)
        uid, other = user.me["id"], admin.me["id"]
        user.call("PUT", f"/users/{uid}/preferences", [{"user_id": uid, "category": "direct_channel_show", "name": other, "value": "true"}])
        print(f"{name}: direct message with {scenario.TRAFFIC_USER} shown in the sidebar")


def finish_onboarding():
    """Marks the webapp's onboarding checklist and tours as done, as for a long-time user: they cover the sidebars."""
    for name, url in scenario.SERVERS:
        user = Server(url, scenario.USER, scenario.PASSWORD)
        uid = user.me["id"]
        done = [("tutorial_step", uid, "999"), ("crt_thread_pane_step", uid, "999"), ("crt_tutorial_triggered", uid, "999"),
                ("crt_tutorial_step", uid, "999"), ("onboarding_task_list", "onboarding_task_list_show", "false"),
                ("onboarding_task_list", "onboarding_task_list_open", "false"), ("recommended_next_steps", "hide", "true"),
                ("actions_menu", "actions_menu_modal_viewed", "true"), ("drafts", "drafts_tour_tip_showed", '{"drafts_tour_tip_showed":true}'),
                ("insights", "insights_tutorial_state", '{"insights_modal_viewed":true}')]
        user.call("PUT", f"/users/{uid}/preferences", [{"user_id": uid, "category": c, "name": n, "value": v} for c, n, v in done])
        print(f"{name}: onboarding marked done")


def main():
    admins = [Server(url, scenario.TRAFFIC_USER, scenario.TRAFFIC_PASSWORD) for _, url in scenario.SERVERS]
    user = Server(scenario.SERVERS[scenario.HISTORY[0]][1], scenario.USER, scenario.PASSWORD)
    history(admins[scenario.HISTORY[0]], user)
    top_up(admins)
    show_direct_messages(admins)
    finish_onboarding()
    if len(sys.argv) > 1: scenario.direct_channels(sys.argv[1])


if __name__ == "__main__":
    main()
