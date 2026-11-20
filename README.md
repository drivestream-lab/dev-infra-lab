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
| [adh-iac-local](../adh-iac-local) | Buzz API + UI | `lab_local` |
| [realworld-local](../realworld-local) | RealWorld api + web | `lab_local` |

No second Postgres/Redis in overlays.

## Start

```bash
cp .env.example .env   # first time
make infra-up

# ADH Buzz
cd ../adh-iac-local && make buzz-up

# RealWorld apps
cd ../realworld-local && make up
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

## Extension hole (Kafka / Flink / …)

See [docker-compose.streaming.yml](docker-compose.streaming.yml) and [docs/extension-hole.md](docs/extension-hole.md).  
**Not** part of default `infra-up`.

## Migration note (from adh-iac-local infra)

Network renamed `adh_local` → `lab_local`; containers `adh-postgres` → `lab-postgres` (etc.).  
One-time: stop old stack, `make infra-up` here (new volumes unless you migrate manually).
