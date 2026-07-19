#!/bin/sh
# Start or update this deployment.
#
#   ./start.sh          bring the stack up (build if needed)
#   ./start.sh update   pull deployment + pinned framework, rebuild, restart
#
# The framework is the `retinue/` submodule, pinned to a known commit — an
# update moves the pin deliberately (git pull in the submodule, commit the new
# pin) rather than floating on main. This script is also a suitable
# UPDATE_COMMAND for the framework's updater sidecar:
#
#   UPDATE_COMMAND=/path/to/retinue-os-deployment/start.sh update
set -e
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "No .env here — start with: cp .env.example .env, then fill it in." >&2
  exit 1
fi
# Compose resolves env_file: .env relative to the project directory, which is
# the FIRST -f file's directory — i.e. the submodule. Link our .env there so
# the framework's services find it (the framework .gitignores .env).
ln -sf ../.env retinue/.env

COMPOSE="docker compose -f retinue/docker-compose.yml -f docker-compose.override.yml"

case "${1:-start}" in
  update)
    git pull
    git submodule update --init --recursive
    $COMPOSE build
    $COMPOSE up -d
    ;;
  start)
    git submodule update --init --recursive
    $COMPOSE up -d --build
    ;;
  *)
    echo "usage: $0 [start|update]" >&2
    exit 1
    ;;
esac
