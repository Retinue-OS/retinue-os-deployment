#!/bin/sh
# Start or update this deployment.
#
#   ./start.sh          bring the stack up (build if needed)
#   ./start.sh update   pull deployment + pinned framework, rebuild, restart
#   ./start.sh login    interactive Claude login inside the running container
#                       (subscription auth instead of ANTHROPIC_API_KEY)
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

# --- Client certificate (on by default) -----------------------------------
# First start mints a client CA plus one owner certificate (browser-importable
# .p12) into certs/, then publishes the CA certificate where the Traefik
# file-provider config expects it. The dashboard router requires certificates
# to verify against this CA when presented; browsers without one fall back to
# basic auth (VerifyClientCertIfGiven). See README.md for installing the .p12
# and the two Traefik mounts this needs.
if [ ! -f certs/ca.crt ] || ! ls certs/*.p12 >/dev/null 2>&1; then
  echo "[mtls] issuing client CA and owner certificate into certs/ ..."
  bash retinue/scripts/gen-client-cert.sh --name aros-owner --out certs
  echo "[mtls] install certs/aros-owner.p12 on your device;"
  echo "[mtls] import passphrase is in certs/aros-owner-passphrase.txt"
fi
cp -f certs/ca.crt traefik/dynamic/aros-client-ca.crt

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
  login)
    # One-time interactive login for Claude subscription auth. Credentials
    # land in /root/.claude/.credentials.json inside the retinue-root volume,
    # so they survive restarts and rebuilds; the framework's entrypoint keeps
    # a rotation-proof backup of them. Requires the stack to be up.
    echo "Claude starts interactively. Type /login and follow the browser"
    echo "flow, then /exit. Headless wake-ups use the stored login from then on."
    $COMPOSE exec retinue claude
    ;;
  *)
    echo "usage: $0 [start|update|login]" >&2
    exit 1
    ;;
esac
