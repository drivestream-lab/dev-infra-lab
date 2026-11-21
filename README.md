# dev-infra-lab

Shared **local-dev** infrastructure lab for [drivestream-lab](https://github.com/drivestream-lab) products.

Not cloud IAC. One laptop cluster. Separate databases, not separate servers.

| Service | Container | Host ports | Notes |
| --- | --- | --- | --- |
| postgres | `lab-postgres` | `5432` | DBs: `litellm`, `buzz`, `hermes`, `ledger`, `realworld`, `temporal`, `temporal_visibility`, `paperclip`, `mandate` |
| redis | `lab-redis` | `6379` | AOF volume |
| litellm | `lab-litellm` | `4000` | UI http://localhost:4000/ui |
| temporal | `lab-temporal` | `7233` | `temporalio/auto-setup:1.29.7`. Profile `platform`. Role `temporal` |
| temporal-ui | `lab-temporal-ui` | `8233` | `temporalio/ui:2.58.1`. UI http://localhost:8233 |
| paperclip | `lab-paperclip` | `3100` | `drivestream-lab/paperclip:mandate-baseline-a665ed6`. UI http://localhost:3100 |
| mandate-runner | `lab-mandate-runner` | `127.0.0.1:8090` | Grades Mandate PRs, posts `mandate/build-verified`. Profile `runner`. Run logs http://localhost:8090/runs/&lt;id&gt;.log |
| mandate-runner-dind | `lab-mandate-runner-dind` | none | The runner's sandbox (Docker-in-Docker, no secrets). Profile `runner` |

**Network:** `lab_local`  
**Compose DNS names** (for overlays): `postgres`, `redis`, `litellm`, `temporal`, `temporal-ui`, `paperclip`  
**Volumes:** `postgres_data`, `redis_data`, `paperclip_data` — survive `make infra-down`; wiped only by `make down-clean`

Roles created by `scripts/ensure-databases.sh` (passwords in `.env`, names in `.env.example`):

| Role | Owns | Used by |
| --- | --- | --- |
| `temporal` | `temporal`, `temporal_visibility` | Temporal |
| `paperclip` | `paperclip` | Paperclip |
| `mandate_owner` | `mandate` | Mandate migrations only |
| `mandate_app` | none yet | Mandate runtime. Schema grants come from Mandate's own migrations |

## Overlays (separate repos)

| Overlay | Owns | Joins |
| --- | --- | --- |
| `example-local` | That product's apps | `lab_local` |

No second Postgres/Redis in overlays.

## Start

```bash
cp .env.example .env   # first time
make infra-up

# Example overlay
cd ../example-local && make up
```

Stop (keep data): `make infra-down`  
Destroy volumes: `make down-clean`

## Platform (Temporal and Paperclip)

`make infra-up` still starts only Postgres, Redis, and LiteLLM. Temporal and Paperclip sit on the Compose profile `platform`.

```bash
make platform-up
```

That runs `infra-up` first, then starts Temporal, Temporal UI, and Paperclip, and waits until they are healthy.

Stop the platform containers and keep their volumes: `make platform-down`  
Probe core plus Temporal, Temporal UI, and Paperclip: `make platform-health`

## mandate-runner

Builds Mandate's swarm, wave B0, task B0-01 (Mandate engineering-ready PRD PL-16). This is plain Python, with no model. Every 30 seconds it polls open PRs on `drivestream-lab/mandate` and `drivestream-lab/mandate-control-tower`. For each PR head into `develop` or `main` it posts the commit status `mandate/build-verified`.

```bash
make runner-up      # needs ~/.mandate/secrets/build/mandate-runner/{app-id,installation-id,private-key.pem}
make runner-logs
make runner-test    # unit tests, in a container
```

**What it runs.** The command set for each base branch comes from [config/mandate-runner/runner.toml](config/mandate-runner/runner.toml), never from the PR. Today it is `make check`, `make test` and `make journeys`, with the full journey set on every graded PR. The runner checks out the exact head commit into a fresh workspace and runs the commands in a job container inside its sandbox. The sandbox is wiped between runs: no containers, networks or volumes are kept.

**When it posts success.** The commands passed and every review rule holds on the current head:

| PR | Rule |
| --- | --- |
| Into `develop` | An Approve from `mandate-challenger[bot]` whose body has the line `Challenger: first` |
| Touches a trust-critical path (ledger, signoff check, evidence verification, merge control) | A second, separate `mandate-challenger[bot]` Approve with the line `Challenger: second`. A single review carrying both lines counts for neither |
| Touches a protected path (PL-16 BP-6, including any `[tool.*]` change in `pyproject.toml`) | An Approve from `nikd10x` |
| `develop` into `main` (wave close) | Label `wave-accepted`, PR ready (not draft), and an Approve from `nikd10x` whose body has the lines `Initiative: INIT-MANDATE-001` and `Head: <full 40-character head sha>`. No challenger review is needed |

Only reviews on the current head count. For each identity, and for each challenger marker, the latest Approve, Request changes or dismissal decides. Comment-only reviews never count. Path patterns live in the config.

**Grading once.** Commands run once per head and command set. The result is kept in the `mandate_runner_data` volume, so a restart doesn't run them again. While they run, the status is `pending`. A head whose commands failed stays failed until a new push. Review rules are re-checked on every poll, and a new status is posted only when the state, description or log link changes. Runner errors (sandbox down, fetch failed) are not cached and are retried.

**When it fails.** The status is `failure`, and the description names the failing command or rule. The status link opens that run's log. Logs are kept in the `mandate_runner_data` volume and served read-only on `127.0.0.1:8090`.

**Identity and secrets.**

- It authenticates as the GitHub App `mandate-runner` (App ID 5860839). At startup it refuses to run if the mounted key belongs to a different App, or if the slug `mandate-challenger` doesn't resolve to App ID 5860827.
- `~/.mandate/secrets/build/mandate-runner/` is mounted read-only into `lab-mandate-runner` only. Only the runner calls GitHub.
- The token reaches git only through one process's environment. It is never written to `.git/config`. Every log line and run log is redacted.
- PR code runs only in the sandbox, which has no build secrets and no GitHub credentials. The runner drives the sandbox over TLS, using a client certificate that only the runner holds.

**Test secrets for journeys (off by default).** `MANDATE_RUNNER_TEST_SECRETS=1` in `.env` mounts `~/.mandate/secrets/test/` read-only into the sandbox, where job containers see it at `/secrets/test`. See [docker-compose.runner-test-secrets.yml](docker-compose.runner-test-secrets.yml). `~/.mandate/secrets/build/` is never mounted there.

**Limits.** PR code controls the sandbox's Docker engine; that's how `make journeys` brings up its own stack. The job image runs by image id, so a PR can't swap it for a later run. A PR that compromises the sandbox engine itself could still affect later runs, though. `make runner-reset-sandbox` rebuilds the sandbox from scratch. The sandbox sits on `lab_local`, so PR code can reach the lab services.

## Extension hole (Kafka / Flink / …)

See [docker-compose.streaming.yml](docker-compose.streaming.yml) and [docs/extension-hole.md](docs/extension-hole.md).  
**Not** part of default `infra-up`.
