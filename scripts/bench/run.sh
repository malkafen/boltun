#!/bin/bash
# Benchmarks Boltun against Mattermost Desktop on this Mac: the same three servers, account and scripted steps,
# RUNS runs per app, alternating, never both apps at once. Writes the raw results to docs/benchmark/, the chart to
# docs/benchmark-usage.svg and prints the table. Needs sudo for the /etc/hosts aliases (see scenario.py).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
work=${BENCH_DIR:-/tmp/boltun-bench}
runs=${RUNS:-3}
mm_version=6.3.1
mm_url="https://github.com/mattermost/desktop/releases/download/v$mm_version/mattermost-desktop-$mm_version-mac-arm64.zip"
bundle=io.github.malkafen.boltun.bench
mkdir -p "$work/apps"
work=$(cd "$work" && pwd -P)
cd "$work"
mm_app="$work/apps/Mattermost.app"
bb_app="$work/apps/Boltun Bench.app"
aliases=$(python3 -c "import sys; sys.path.insert(0, '$here'); import scenario; print(scenario.HOST, ' '.join(scenario.ALIASES))")

quit_all() {
  pkill -TERM -f "/Mattermost.app/Contents/MacOS/Mattermost" 2>/dev/null || true
  pkill -TERM -f "/Boltun.app/Contents/MacOS/Boltun" 2>/dev/null || true
  pkill -TERM -f "/Boltun Bench.app/Contents/MacOS/Boltun" 2>/dev/null || true
  while pgrep -f "/Mattermost.app/Contents/MacOS/|/Boltun.app/Contents/MacOS/|/Boltun Bench.app/Contents/MacOS/" >/dev/null; do sleep 0.5; done
}
sampler=""
sample() { python3 "$here/sample.py" "$1" "$2" & sampler=$!; }
stop_sampling() { kill "$sampler" 2>/dev/null || true; wait "$sampler" 2>/dev/null || true; }

add_aliases() {
  if ! grep -q "# boltun-bench$" /etc/hosts; then
    echo "$aliases # boltun-bench" | sudo tee -a /etc/hosts >/dev/null
    sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
  fi
  python3 "$here/serverconf.py" allow "$work"
}
remove_aliases() {
  stop_sampling
  quit_all
  python3 "$here/serverconf.py" restore "$work" || true
  sudo /usr/bin/sed -i '' '/# boltun-bench$/d' /etc/hosts
  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
}

if [ ! -d "$mm_app" ]; then
  echo "Installing Mattermost Desktop $mm_version into $work/apps…"
  curl -fsSL -o mattermost.zip "$mm_url"
  ditto -x -k mattermost.zip apps && rm mattermost.zip
fi

echo "Building Boltun and its bench copy (bundle id $bundle, debug automation on)…"
(cd "$repo" && scripts/build-app.sh >/dev/null)
rm -rf "$bb_app" && cp -R "$repo/build/Boltun.app" "$bb_app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundle" -c "Set :CFBundleName Boltun Bench" \
  -c "Set :CFBundleDisplayName Boltun Bench" -c "Delete :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$bb_app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$bb_app" 2>/dev/null
defaults write "$bundle" BoltunDebugAutomation -bool YES

quit_all
add_aliases
trap remove_aliases EXIT
python3 "$here/prepare.py" "$work"

if [ ! -d mm-pristine ]; then
  echo "Logging Mattermost Desktop in to the three servers…"
  rm -rf mm-prepare
  python3 "$here/mmbench.py" prepare "$mm_app" "$work/mm-prepare" "$work"
  mv mm-prepare mm-pristine
fi
if [ ! -d bb-pristine ]; then
  echo "Logging Boltun in to the three servers…"
  rm -rf bb-prepare
  python3 "$here/bbench.py" prepare "$bb_app" "$work/bb-prepare" "$work"
  mv bb-prepare bb-pristine
fi

echo "Launching each app once, so that no measured run pays for the first launch of a new build…"
rm -rf bb-run && cp -R bb-pristine bb-run
open -n -a "$bb_app" --env CFFIXED_USER_HOME="$work/bb-run"; sleep 15; quit_all
rm -rf mm-run && cp -R mm-pristine mm-run
open -n -a "$mm_app" --args --dataDir="$work/mm-run" --use-mock-keychain; sleep 15; quit_all

python3 - "$mm_app" "$bb_app" > sizes.json <<'EOF'
import json, os, subprocess, sys
size = lambda p: int(subprocess.run(["du", "-sk", p], capture_output=True, text=True).stdout.split()[0]) * 1024
print(json.dumps({"mattermost": size(sys.argv[1]), "boltun": size(sys.argv[2])}))
EOF

run_boltun() {
  echo "Boltun, run $1…"
  rm -rf bb-run && cp -R bb-pristine bb-run && rm -f /tmp/boltun-automation.log
  python3 "$here/traffic.py" reset >/dev/null
  sleep 20
  sample "/apps/Boltun Bench.app/" "$work/res-boltun-$1.samples.jsonl"
  python3 "$here/bbench.py" run "$bb_app" "$work/bb-run" "$work" "$work/res-boltun-$1.json" > "$work/res-boltun-$1.log" 2>&1
  stop_sampling
  quit_all
}
run_mattermost() {
  echo "Mattermost Desktop, run $1…"
  rm -rf mm-run && cp -R mm-pristine mm-run
  python3 "$here/traffic.py" reset >/dev/null
  sleep 20
  sample "/apps/Mattermost.app/" "$work/res-mattermost-$1.samples.jsonl"
  python3 "$here/mmbench.py" run "$mm_app" "$work/mm-run" "$work" "$work/res-mattermost-$1.json" > "$work/res-mattermost-$1.log" 2>&1
  stop_sampling
  quit_all
}
for i in $(seq "$runs"); do
  if [ $((i % 2)) -eq 1 ]; then run_boltun "$i"; run_mattermost "$i"; else run_mattermost "$i"; run_boltun "$i"; fi
done
rm -rf bb-run mm-run

mkdir -p "$repo/docs/benchmark"
cp res-*.json res-*.samples.jsonl sizes.json "$repo/docs/benchmark/"
python3 "$here/chart.py" "$repo/docs/benchmark" "$repo/docs/benchmark-usage.svg" "$repo/docs/benchmark-switches.svg"
python3 "$here/report.py" "$repo/docs/benchmark"
