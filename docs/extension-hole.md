# Extension hole — streaming & future lab services

`dev-infra-lab` day-1 core is **Postgres · Redis · network · LiteLLM** only.

## Future services (not default)

Kafka, Flink, and similar join **`lab_local`** via optional compose:

- File: [`docker-compose.streaming.yml`](../docker-compose.streaming.yml)
- Prefer Compose **profiles** (`streaming`) so `make infra-up` stays thin
- Each service: named **volumes**, documented host ports, no second Postgres/Redis

## Contract

1. Join `lab_local` (external network created by `make infra-up`)
2. Durable state on named Docker volumes
3. Off by default
4. Document hostname + ports in the lab README when added
5. Product overlays only **consume** via env (never vendor their own broker)
