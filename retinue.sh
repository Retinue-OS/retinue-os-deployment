#!/bin/sh
# Run an arbitrary docker compose command against this deployment.
#
#   ./retinue.sh ps
#   ./retinue.sh logs -f retinue
#   ./retinue.sh exec retinue bash
#   ./retinue.sh --profile messaging up -d signal-gateway
#
# Plain `docker compose` from this directory does not work — the framework's
# compose file lives in the submodule — and the flags below are load-bearing,
# so this is the only supported way to reach the stack. ./start.sh routes
# through this script too, which is what keeps the two from drifting apart.
set -e
cd "$(dirname "$0")"

if [ ! -f retinue/docker-compose.yml ]; then
  echo "Framework not checked out — run ./start.sh first (it inits the submodule)." >&2
  exit 1
fi
if [ ! -f .env ]; then
  echo "No .env here — start with: cp .env.example .env, then fill it in." >&2
  exit 1
fi

# Compose derives the project directory from the FIRST -f file's directory —
# i.e. the submodule, not this repo. Everything here works around that:
#
#   $DEPLOY_DIR   absolute paths for the override's mounts; a relative path
#                 there would resolve against the submodule
#   --env-file    variable substitution reads THIS repo's .env
#   retinue/.env  the framework's own `env_file:` directives still resolve
#                 against the project directory, which --env-file does not
#                 cover — hence the symlink
#   -p            the default project name would be the project directory's
#                 basename, "retinue", colliding with the framework repo run
#                 standalone on the same host (see the README migration note)
export DEPLOY_DIR="$(pwd)"
ln -sf ../.env retinue/.env

exec docker compose \
  -p retinue-os-deployment \
  --env-file "$DEPLOY_DIR/.env" \
  -f retinue/docker-compose.yml \
  -f docker-compose.override.yml \
  "$@"
