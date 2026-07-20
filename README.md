# retinue-deployment — the project's own deployment

A working Retinue deployment that runs exactly one chamber
([`retinue-chamber`](https://github.com/retinue-os/retinue-os-chamber)) and one
agent, **Aros**, whose job is promoting the Retinue project honestly.

It doubles as a **reference deployment**: the smallest real thing you can point
at when someone asks what a deployment repository actually looks like.

## Layout

This is the *nested deployment* layout described in the framework's
`CLAUDE.md`: this repository owns the deployment, and pins the framework as a
submodule.

```
retinue-deployment/
├── retinue/                       ← submodule: retinue-os/retinue
├── chambers.json                  ← one chamber
├── docker-compose.override.yml    ← edge wiring + what NOT to run
├── .env.example                   ← copy to .env and fill in
├── deployment.sh                  ← manage the deployment: bootstrap, update, bump, login
└── retinue.sh                     ← operate the running stack (docker compose wrapper)
```

## Setup

```bash
git clone --recurse-submodules https://github.com/retinue-os/retinue-os-deployment.git
cd retinue-os-deployment
cp .env.example .env          # then fill it in
./deployment.sh bootstrap
```

**Two scripts, two jobs.** `deployment.sh` changes *what is deployed* — the
framework pin, the submodule checkout, the client certificate, the stored
credentials. `retinue.sh` *runs it*: a `docker compose` passthrough that adds
the flags this deployment needs, so everyday operation is

```bash
./retinue.sh up -d            # start (bootstrap already built it)
./retinue.sh logs -f retinue
./retinue.sh ps
```

Never call `docker compose` directly: the framework's compose file lives in
the submodule (a bare `docker compose up` from here finds nothing), and
`retinue.sh` pins the compose project name (`-p`) and exports `$DEPLOY_DIR`,
which the override interpolates. A bare `docker compose up` gets neither and
fails on the missing variable rather than silently starting a second,
differently-named stack.

`./deployment.sh update` pulls this repo, moves to the newly pinned framework
commit, rebuilds and restarts — it is also a suitable `UPDATE_COMMAND` for the
framework's updater sidecar. `update` never moves the pin itself; it only
checks out the commit this repo already records, so it is reproducible. To
take a newer framework, run `./deployment.sh bump` — it fetches the
framework's `main`, commits the new pin here, then rebuilds and restarts. Push
that commit to roll the same version out to other hosts, where a plain
`update` will pick it up.

`start.sh` remains as a deprecated shim that forwards to the two scripts, so
an existing `UPDATE_COMMAND=…/start.sh update` keeps working — repoint it to
`deployment.sh update` when convenient.

**One-time migration** if this deployment ran before the project name was
pinned: it was previously named after the submodule directory (`retinue`), so
the rename leaves the old volumes behind — including `retinue-root`, which
holds the Claude subscription credentials from `./deployment.sh login`. Move
them before the next start, or re-run the login afterwards:

```bash
docker compose -f retinue/docker-compose.yml -f docker-compose.override.yml down   # old project
docker volume ls | grep '^local *retinue_'                                         # what carries over
# for each volume worth keeping — `retinue-root` (credentials) above all,
# then `chambers` (cloned chamber working copies):
docker run --rm -v retinue_retinue-root:/from -v retinue-os-deployment_retinue-root:/to \
  alpine sh -c 'cd /from && cp -a . /to'
./retinue.sh up -d --build
```

## Model authentication: API key or Claude login

Aros runs headless — every wake-up is a fresh `claude -p`, so there is no
interactive session to prompt for auth. Two ways to provide it:

**Option A — API key.** Set `ANTHROPIC_API_KEY` in `.env`. Simplest, priced
per token.

**Option B — Claude subscription login.** Leave `ANTHROPIC_API_KEY` empty,
bring the stack up, then run the one-time interactive login:

```bash
./retinue.sh up -d       # stack must be up first
./deployment.sh login    # opens Claude interactively inside the container
```

In the Claude prompt type `/login`, follow the browser flow (it prints a URL —
open it on any device, paste the code back), then `/exit`. The credentials
land in `/root/.claude/.credentials.json` inside the `retinue-root` volume, so
they survive restarts and rebuilds, and the framework's entrypoint keeps a
rotation-proof backup of them. All subsequent headless wake-ups use the stored
login.

If both are present, the API key wins — leave it empty deliberately when you
want subscription auth.

## Client-certificate access

The dashboard authenticates with a **client certificate by default**, with
basic auth as the fallback for browsers that don't present one
(`VerifyClientCertIfGiven` — the certificate is an alternative to the
password, not a second factor).

**What `deployment.sh bootstrap` generates** (first run only, into `certs/`,
all gitignored):

| File | What it is |
|---|---|
| `ca.key` / `ca.crt` | The client CA. Whoever holds `ca.key` can mint accepted certificates — after setup, move it somewhere safe and offline. |
| `aros-owner.p12` | The browser-importable certificate bundle. |
| `aros-owner-passphrase.txt` | Its import passphrase. |

The CA *certificate* (never the key) is copied to
`traefik/dynamic/aros-client-ca.crt`, next to the committed TLS-options file
`aros-mtls.yml`. Nothing is sent anywhere: every file above is created and
stays on this host, and the private keys never enter any container — at use
time the browser presents the certificate inside the TLS handshake, and
Traefik forwards only the verified result to the gateway's `/auth` as
stripped-and-rewritten headers.

**Installing the certificate on your device:** transfer `aros-owner.p12` and
the passphrase to the device over a channel you trust (AirDrop, USB, a
password manager's file feature — not plain e-mail), install it (iOS: Settings
→ Profile Downloaded; Android: Settings → Security → Install a certificate;
desktop browsers: certificate manager → Import), then visit the dashboard —
the browser offers the certificate, and no password prompt appears.

**Required Traefik wiring** — this deployment does not run Traefik; yours must
load the two files, e.g. mounted into its file-provider directory. Replace
`/root/retinue-os-deployment` with wherever you cloned this repo — Traefik runs
from its own compose project, so these have to be absolute:

```yaml
volumes:
  - /root/retinue-os-deployment/traefik/dynamic/aros-mtls.yml:/etc/traefik/dynamic/aros-mtls.yml:ro
  - /root/retinue-os-deployment/traefik/dynamic/aros-client-ca.crt:/etc/traefik/dynamic/aros-client-ca.crt:ro
```

The TLS option is deliberately named `aros-mtls` (not the framework's
`retinue-mtls`) so this deployment can share a Traefik with a personal Retinue
deployment without the two option definitions colliding.

**More certificates** (another device, another person):

```bash
bash retinue/scripts/gen-client-cert.sh --name <who> --out certs
```

reuses the CA and issues a fresh `.p12`. **Revocation caveat:** there is no
CRL wired — revoking a single certificate means deleting `certs/ca.*`,
re-running `./deployment.sh bootstrap` to mint a fresh CA, and reissuing
certificates for the devices that keep access.

Read the framework's `README.md` (in `retinue/`) for what each variable does —
this deployment adds only `GITHUB_TOKEN` and `SOCIAL_SEND_POLICY` on top.

## What makes this deployment unusual

**One chamber, on purpose.** Aros is the project's public voice, and his
guardrails forbid him access to personal data. Mounting only `retinue-chamber`
makes that a property of the deployment rather than a promise in a prompt. If
you run Aros, do not add chambers to this file.

**No messaging gateways.** Aros works through GitHub and the dashboard. The
Signal, WhatsApp and Telegram services are parked behind an inactive Compose
profile, so no messaging credentials are ever provisioned. A credential that
isn't deployed can't be stolen.

**A deliberately weak GitHub token.** Aros reads issues and PRs and opens
`owner-action` issues. He must not be able to create repositories, change org
membership, or transfer repos — those are owner actions. Scope the token to
repository read/write on the `retinue-os` org and nothing more.

**His accounts, his voice.** Aros publishes autonomously from accounts that
are openly his — created by the owner (accounts need legal personhood), labeled
as an AI agent, revocable at any time. This is the framework's send-control
model applied honestly: authority keyed to the sending identity, `allow` on his
own accounts, and no configuration of this deployment in which he speaks
through the owner's. What he cannot do without the owner is the short list in
the chamber's `GUARDRAILS.md` §7: accounts, money, terms, legal, org
administration.

## What Aros does here

He wakes every 30 minutes (`.schedule.json` in the chamber), checks GitHub and
his drafts, picks up at most one or two things in service of his strategy
(`strategy.md` in the chamber), writes down what he did, and stops. Once a day
he regenerates the public dashboard data; every two weeks he re-evaluates the
strategy against what actually happened and logs every revision.

An idle wake-up that changes nothing is a correct outcome. If you find him
generating activity to look busy, that is a bug in his prompt — please report
it.

## The owner's part

Aros cannot create accounts, spend money, accept terms of service, or make legal
decisions. When he needs one of those he will:

- open a **dashboard conversation** if it's time-sensitive, or
- open a **GitHub issue labelled `owner-action`** if it needs a durable trail.

Both are enumerated in the chamber's `GUARDRAILS.md` §7. The list is short by
design, and it is the honest cost of running an autonomous agent that speaks in
public: someone with legal personhood stays accountable for what it says.
