#!/usr/bin/env bash
# Shared compose helpers for dev-infra-lab.
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$LAB_ROOT"

INFRA_PROJECT="${INFRA_PROJECT:-dev-infra-lab}"
INFRA_FILE="${INFRA_FILE:-docker-compose.infra.yml}"
ENV_FILE="${ENV_FILE:-.env}"
LAB_NETWORK="${LAB_NETWORK:-lab_local}"

ensure_env_file() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Creating $ENV_FILE from .env.example (local defaults; not committed)."
    cp "$LAB_ROOT/.env.example" "$LAB_ROOT/$ENV_FILE"
    return
  fi
  local missing=0 line key
  while IFS= read -r line; do
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    key="${line%%=*}"
    if ! grep -q "^${key}=" "$ENV_FILE"; then
      if (( missing == 0 )); then
        echo "Adding new keys from .env.example to $ENV_FILE."
        printf '\n' >> "$ENV_FILE"
      fi
      printf '%s\n' "$line" >> "$ENV_FILE"
      missing=1
    fi
  done < "$LAB_ROOT/.env.example"
}

ensure_shared_resources() {
  if ! docker network inspect "$LAB_NETWORK" >/dev/null 2>&1; then
    echo "Creating network $LAB_NETWORK..."
    docker network create "$LAB_NETWORK" >/dev/null
  fi
}

compose_infra() {
  local args=(-p "$INFRA_PROJECT" -f "$INFRA_FILE")
  if [[ -f "$ENV_FILE" ]]; then
    args+=(--env-file "$ENV_FILE")
  fi
  docker compose "${args[@]}" "$@"
}

wait_container_healthy() {
  local name="$1"
  local timeout="${2:-120}"
  local elapsed=0
  echo "Waiting for $name healthy (timeout ${timeout}s)..."
  while (( elapsed < timeout )); do
    local status
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo missing)"
    if [[ "$status" == "healthy" ]]; then
      echo "  $name: $status"
      return 0
    fi
    echo "  $name: $status"
    sleep 3
    elapsed=$((elapsed + 3))
  done
  echo "ERROR: $name not healthy within ${timeout}s (last=$status)" >&2
  return 1
}

wait_infra_core() {
  wait_container_healthy lab-postgres 90
  wait_container_healthy lab-redis 60
  wait_container_healthy lab-litellm 180
}
