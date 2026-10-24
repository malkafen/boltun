#!/usr/bin/env python3
"""Adjusts the servers for the benchmark and undoes it afterwards; the old values are saved in the work dir.
- ServiceSettings.AllowCorsFrom gets the host aliases the apps use (see scenario.ALIASES): the servers accept WebSocket
  origins only from their SiteURL and from this list.
- ServiceSettings.EnableLinkPreviews is turned off: the test servers cannot reach the internet, so the first fetch of
  posts with links waits 5-10 s for the link preview to time out, whichever app happens to ask first.
Usage: serverconf.py allow <work dir>
       serverconf.py restore <work dir>"""
import json, os, sys
import scenario
from api import Server

KEYS = ("AllowCorsFrom", "EnableLinkPreviews")


def wanted(current, app_url):
    origins = (current["AllowCorsFrom"] or "").split()
    return {"AllowCorsFrom": " ".join(origins + ([] if app_url in origins else [app_url])), "EnableLinkPreviews": False}


def main():
    action, work = sys.argv[1], sys.argv[2]
    saved_path = os.path.join(work, "server-settings.json")
    saved = json.load(open(saved_path)) if os.path.exists(saved_path) else {}
    for i, ((name, url), app_url) in enumerate(zip(scenario.SERVERS, scenario.APP_URLS)):
        admin = Server(url, scenario.TRAFFIC_USER, scenario.TRAFFIC_PASSWORD)
        current = {k: admin.get("/config")["ServiceSettings"][k] for k in KEYS}
        if action == "allow":
            saved.setdefault(str(i), current)
            value = wanted(current, app_url)
        elif str(i) in saved:
            value = saved[str(i)]
        else:
            continue
        admin.call("PUT", "/config/patch", {"ServiceSettings": value})
        print(f"{name}: {value}")
    if action == "allow":
        json.dump(saved, open(saved_path, "w"))
    elif os.path.exists(saved_path):
        os.remove(saved_path)


if __name__ == "__main__":
    main()
