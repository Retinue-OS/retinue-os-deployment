#!/bin/sh
# Manage this deployment — the git artifact: framework pin, submodule, client
# certificate, credentials. This script changes WHAT is deployed; operating the
# running stack (logs, restart, exec, ps) is ./retinue.sh's job.
#
#   ./deployment.sh bootstrap   first-time setup: init the submodule, mint the
#                               client certificate, build and start the stack
#   ./deployment.sh update      pull deployment + pinned framework, rebuild, restart
#   ./deployment.sh bump        move the framework pin to upstream main, then update
#   ./deployment.sh login       interactive Claude login inside the running container
#                               (subscription auth instead of ANTHROPIC_API_KEY)
#
# The framework is the `retinue/` submodule, pinned to a known commit — `update`
# only ever checks out the committed pin, so it is reproducible. Moving to a
# newer framework is the separate, deliberate `bump`, which commits the new pin
# here. This script is also a suitable UPDATE_COMMAND for the framework's
# updater sidecar (use `update`, not `bump` — a sidecar should not move pins):
#
#   UPDATE_COMMAND=/path/to/retinue-os-deployment/deployment.sh update
set -e
cd "$(dirname "$0")"

usage() {
  echo "usage: $0 bootstrap|update|bump|login" >&2
  echo "(operating the running stack — logs, restart, exec — goes through ./retinue.sh)" >&2
  exit 1
}
case "${1:-}" in bootstrap|update|bump|login) ;; *) usage ;; esac

if [ ! -f .env ]; then
  echo "No .env here — start with: cp .env.example .env, then fill it in." >&2
  exit 1
fi

# Everything below needs the framework checked out — the cert helper lives in
# retinue/scripts/. A plain `git clone` (no --recursive) leaves retinue/ empty.
git submodule update --init --recursive

# All compose invocation goes through retinue.sh — it owns the project name,
# the env-file wiring and $DEPLOY_DIR, and explains why each is needed. Keeping
# that flag set in one place is the point: a second copy is how the paths drift.
COMPOSE="./retinue.sh"

# Mint a client CA plus one owner certificate (browser-importable .p12) into
# certs/ if absent, then (re)publish the CA certificate where the Traefik
# file-provider config expects it. The dashboard router requires certificates
# to verify against this CA when presented; browsers without one fall back to
# basic auth (VerifyClientCertIfGiven). See README.md for installing the .p12
# and the two Traefik mounts this needs. Every mutating command runs this, so
# a wiped traefik/dynamic heals itself on the next update.
provision_certs() {
  if [ ! -f certs/ca.crt ] || ! ls certs/*.p12 >/dev/null 2>&1; then
    echo "[mtls] issuing client CA and owner certificate into certs/ ..."
    bash retinue/scripts/gen-client-cert.sh --name aros-owner --out certs
    echo "[mtls] install certs/aros-owner.p12 on your device;"
    echo "[mtls] import passphrase is in certs/aros-owner-passphrase.txt"
  fi
  cp -f certs/ca.crt traefik/dynamic/aros-client-ca.crt
}

case "$1" in
  bootstrap)
    provision_certs
    $COMPOSE up -d --build
    ;;
  update)
    git pull
    # the pull may have moved the submodule pin
    git submodule update --init --recursive
    provision_certs
    $COMPOSE build
    $COMPOSE up -d
    ;;
  bump)
    # Move the pin to the tip of the framework's main, then the same rebuild
    # `update` does. Committing here is the point: the pin lives in this repo,
    # so an un-committed submodule checkout would be undone by the next `update`.
    git -C retinue fetch origin main
    git -C retinue checkout --detach FETCH_HEAD
    if git diff --quiet -- retinue; then
      echo "[bump] framework already at upstream main — nothing to pin."
    else
      git add retinue
      git commit -m "chore: bump framework pin to $(git -C retinue rev-parse --short HEAD)"
      echo "[bump] pinned framework at $(git -C retinue rev-parse --short HEAD); push when ready."
    fi
    provision_certs
    $COMPOSE build
    $COMPOSE up -d
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
esac
