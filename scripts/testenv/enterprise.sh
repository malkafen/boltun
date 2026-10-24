#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export HOST_IP=${HOST_IP:-$(hostname -I | awk '{print $1}')}
PORT=8067
docker compose -p boltun-mm3 -f enterprise.yml up -d
until curl -sf "http://localhost:$PORT/api/v4/system/ping" >/dev/null; do sleep 3; done
mmctl() { docker exec boltun-mm3-app-1 mmctl --local "$@"; }
if ! mmctl user search boltun 2>/dev/null | grep -q boltun; then
  mmctl user create --email boltun@example.com --username boltun --password 'Boltun-pass1' --system-admin >/dev/null
  mmctl user create --email sysadmin@example.com --username sysadmin --password 'Sys@dmin-sample1' --system-admin >/dev/null
  mmctl user create --email user1@example.com --username user1 --password 'User1-pass1' >/dev/null
  for team in alpha beta; do
    mmctl team create --name "$team" --display-name "${team^}" >/dev/null
    mmctl team users add "$team" boltun sysadmin user1 >/dev/null
  done
fi
echo "Enterprise server: http://$HOST_IP:$PORT  login: boltun / Boltun-pass1"
