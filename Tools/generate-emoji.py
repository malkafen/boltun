#!/usr/bin/env python3
import argparse
import json
import pathlib
import urllib.request

IAMCAL_URL = "https://raw.githubusercontent.com/iamcal/emoji-data/master/emoji.json"
GEMOJI_URL = "https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json"
OUTPUT = pathlib.Path(__file__).resolve().parent.parent / "Sources" / "BoltunMarkup" / "EmojiData.swift"


def load(path, url):
    if path:
        return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    with urllib.request.urlopen(url) as response:
        return json.loads(response.read().decode("utf-8"))


def glyph(unified):
    return "".join(chr(int(part, 16)) for part in unified.split("-"))


def valid_name(name):
    return name and all(c.isascii() and (c.isalnum() or c in "_+-") for c in name)


def main():
    parser = argparse.ArgumentParser(
        description="Regenerate EmojiData.swift from emoji-datasource (iamcal) and gemoji; downloads them unless paths are given."
    )
    parser.add_argument("--iamcal", help="local copy of iamcal emoji.json")
    parser.add_argument("--gemoji", help="local copy of gemoji db/emoji.json")
    args = parser.parse_args()

    iamcal = load(args.iamcal, IAMCAL_URL)
    gemoji = load(args.gemoji, GEMOJI_URL)

    entries = []
    by_glyph = {}
    seen = set()
    for item in sorted(iamcal, key=lambda e: e.get("sort_order", 1 << 30)):
        names = [n.lower() for n in item["short_names"] if valid_name(n) and n.lower() not in seen]
        if not names:
            continue
        g = glyph(item["unified"])
        seen.update(names)
        entry = [g, names]
        entries.append(entry)
        by_glyph[g] = entry
        if item.get("non_qualified"):
            by_glyph.setdefault(glyph(item["non_qualified"]), entry)

    for item in gemoji:
        g = item["emoji"]
        stripped = g.replace("\ufe0f", "")
        target = by_glyph.get(g) or by_glyph.get(stripped)
        for alias in item["aliases"]:
            alias = alias.lower()
            if not valid_name(alias) or alias in seen:
                continue
            seen.add(alias)
            if target is None:
                target = [g, []]
                entries.append(target)
                by_glyph[g] = target
            target[1].append(alias)

    lines = [f"{g} {' '.join(names)}" for g, names in entries]
    body = "\n".join(lines)
    OUTPUT.write_text(
        "enum EmojiData {\n"
        "    static let packed = \"\"\"\n"
        f"{body}\n"
        "\"\"\"\n"
        "}\n",
        encoding="utf-8",
    )
    print(f"{len(entries)} glyphs, {len(seen)} names -> {OUTPUT}")


if __name__ == "__main__":
    main()
