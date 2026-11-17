# dev-infra-lab

Shared **local-dev** infrastructure lab for [drivestream-lab](https://github.com/drivestream-lab) products.

Not cloud IAC. One laptop cluster. Separate databases, not separate servers.

| Service | Container | Host ports | Notes |
| --- | --- | --- | --- |
| postgres | `lab-postgres` | `5432` | DBs: `litellm`, `buzz`, `hermes`, `ledger`, `realworld` |
| redis | `lab-redis` | `6379` | AOF volume |
| litellm | `lab-litellm` | `4000` | UI http://localhost:4000/ui |

**Network:** `lab_local`  
**Compose DNS names** (for overlays): `postgres`, `redis`, `litellm`  
**Volumes:** `postgres_data`, `redis_data` — survive `make infra-down`; wiped only by `make down-clean`

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

## Extension hole (Kafka / Flink / …)

See [docker-compose.streaming.yml](docker-compose.streaming.yml) and [docs/extension-hole.md](docs/extension-hole.md).  
**Not** part of default `infra-up`.

## Migration note (from adh-iac-local infra)

Network renamed `adh_local` → `lab_local`; containers `adh-postgres` → `lab-postgres` (etc.).  
One-time: stop old stack, `make infra-up` here (new volumes unless you migrate manually).
