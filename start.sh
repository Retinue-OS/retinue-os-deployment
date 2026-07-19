#!/bin/sh
# Start or update this deployment.
#
#   ./start.sh          bring the stack up (build if needed)
#   ./start.sh update   pull deployment + pinned framework, rebuild, restart
#   ./start.sh bump     move the framework pin to upstream main, then update
#   ./start.sh login    interactive Claude login inside the running container
#                       (subscription auth instead of ANTHROPIC_API_KEY)
#
# The framework is the `retinue/` submodule, pinned to a known commit — `update`
# only ever checks out the committed pin, so it is reproducible. Moving to a
# newer framework is the separate, deliberate `bump`, which commits the new pin
# here. This script is also a suitable UPDATE_COMMAND for the framework's
# updater sidecar (use `update`, not `bump` — a sidecar should not move pins):
#
#   UPDATE_COMMAND=/path/to/retinue-os-deployment/start.sh update
set -e
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "No .env here — start with: cp .env.example .env, then fill it in." >&2
  exit 1
fi

# Everything below this line needs the framework checked out — the cert helper
# lives in retinue/scripts/. A plain `git clone` (no --recursive) leaves
# retinue/ empty, so init before first use, not just before `up`.
git submodule update --init --recursive

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

# All compose invocation goes through retinue.sh — it owns the project name,
# the env-file wiring and $DEPLOY_DIR, and explains why each is needed. Keeping
# that flag set in one place is the point: a second copy is how the paths drift.
COMPOSE="./retinue.sh"

case "${1:-start}" in
  bump)
    # Move the pin to the tip of the framework's main, then fall through to the
    # same rebuild `update` does. Committing here is the point: the pin lives in
    # this repo, so an un-committed submodule checkout would be undone by the
    # next `update`.
    git -C retinue fetch origin main
    git -C retinue checkout --detach FETCH_HEAD
    if git diff --quiet -- retinue; then
      echo "[bump] framework already at upstream main — nothing to pin."
    else
      git add retinue
      git commit -m "chore: bump framework pin to $(git -C retinue rev-parse --short HEAD)"
      echo "[bump] pinned framework at $(git -C retinue rev-parse --short HEAD); push when ready."
    fi
    $COMPOSE build
    $COMPOSE up -d
    ;;
  update)
    git pull
    # again: git pull may have moved the submodule pin
    git submodule update --init --recursive
    $COMPOSE build
    $COMPOSE up -d
    ;;
  start)
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
    echo "usage: $0 [start|update|bump|login]" >&2
    exit 1
    ;;
esac
