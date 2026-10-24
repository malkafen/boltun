#!/bin/bash
set -euo pipefail
HOST_IP=${HOST_IP:-$(hostname -I | awk '{print $1}')}
IMAGE=${MM_IMAGE:-mattermost/mattermost-preview:latest}
USER_NAME=${MM_TEST_USER:-boltun}
USER_PASS=${MM_TEST_PASS:-Boltun-pass1}

start() {
  local name=$1 port=$2
  if ! docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    docker run -d --name "$name" --restart unless-stopped -p "$port:8065" \
      -e MM_SERVICESETTINGS_SITEURL="http://$HOST_IP:$port" \
      -e MM_SERVICESETTINGS_ENABLELOCALMODE=true \
      -e MM_SERVICESETTINGS_ENABLEUSERACCESSTOKENS=true \
      "$IMAGE" >/dev/null
  fi
  docker start "$name" >/dev/null
  until curl -sf "http://localhost:$port/api/v4/system/ping" >/dev/null; do sleep 3; done
}

seed() {
  local name=$1 teams=$2 users=$3 posts=$4 seed=$5
  local mmctl="/mm/mattermost/bin/mmctl --local"
  if docker exec "$name" sh -c "$mmctl user search $USER_NAME" 2>/dev/null | grep -q "$USER_NAME"; then return; fi
  docker exec "$name" sh -c "cd /tmp && $mmctl sampledata -t $teams -u $users --posts-per-channel $posts -s $seed" >/dev/null
  sleep 30
  docker exec "$name" sh -c "$mmctl user create --email $USER_NAME@example.com --username $USER_NAME --password '$USER_PASS' --system-admin" >/dev/null
  for team in $(docker exec "$name" sh -c "$mmctl team list --json" | python3 -c 'import json,sys; print(" ".join(t["name"] for t in json.load(sys.stdin)))'); do
    docker exec "$name" sh -c "$mmctl team users add $team $USER_NAME" >/dev/null
  done
}

start boltun-mm1 8065
start boltun-mm2 8066
seed boltun-mm1 3 25 200 1
seed boltun-mm2 2 15 80 7
echo "Server 1: http://$HOST_IP:8065  Server 2: http://$HOST_IP:8066  login: $USER_NAME / $USER_PASS"
