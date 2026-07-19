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
└── start.sh
```

## Setup

```bash
git clone --recurse-submodules https://github.com/retinue-os/retinue-os-deployment.git
cd retinue-os-deployment
cp .env.example .env        # then fill it in
./start.sh
```

`start.sh` wraps the compose invocation (the framework's compose file lives in
the submodule, so plain `docker compose up` from this directory would find
nothing) and keeps the submodule in sync with the pin. Later, `./start.sh
update` pulls this repo, moves to the newly pinned framework commit, rebuilds
and restarts — it is also a suitable `UPDATE_COMMAND` for the framework's
updater sidecar.

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
