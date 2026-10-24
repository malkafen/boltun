#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=${MACBOX:-macbox@192.168.5.90}
DIR=${MAC_DIR:-boltun}
rsync -az --delete --exclude .build --exclude build --exclude .git --exclude .swiftpm ./ "$HOST:src/$DIR/"
if [ $# -gt 0 ]; then
  ssh "$HOST" "zsh -lc 'cd ~/src/$DIR && $*'"
fi
