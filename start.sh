#!/bin/sh
# Deprecated shim — this script was split in two. Deployment management
# (bootstrap, update, bump, login) moved to ./deployment.sh; everyday operation
# of the running stack is ./retinue.sh (e.g. `./retinue.sh up -d`). This shim
# exists so updater sidecars configured with `UPDATE_COMMAND=.../start.sh
# update` keep working across the rename; repoint them to deployment.sh — the
# shim will be removed eventually.
set -e
cd "$(dirname "$0")"

case "${1:-start}" in
  start)
    echo "[start.sh] deprecated — everyday start is now: ./retinue.sh up -d" >&2
    echo "[start.sh] running ./deployment.sh bootstrap (same as the old no-arg behaviour) ..." >&2
    exec ./deployment.sh bootstrap
    ;;
  update|bump|login)
    echo "[start.sh] deprecated — use ./deployment.sh $1 (repoint UPDATE_COMMAND too)" >&2
    exec ./deployment.sh "$1"
    ;;
  *)
    echo "start.sh is deprecated; see ./deployment.sh (bootstrap|update|bump|login)" >&2
    echo "and ./retinue.sh for operating the running stack." >&2
    exit 1
    ;;
esac
