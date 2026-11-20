#!/usr/bin/env bash
# Create lab databases if missing (existing postgres_data volumes skip initdb.d).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=compose-lib.sh
source "$SCRIPT_DIR/compose-lib.sh"

if [[ -f "$LAB_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$LAB_ROOT/.env"
  set +a
fi

USER="${POSTGRES_USER:-adh}"

if ! docker inspect -f '{{.State.Running}}' lab-postgres 2>/dev/null | grep -q true; then
  echo "ERROR: lab-postgres is not running. Run: make infra-up" >&2
  exit 1
fi

for db in litellm buzz hermes ledger realworld; do
  echo "Ensuring database '$db' exists (user=$USER)..."
  exists="$(compose_infra exec -T postgres \
    psql -U "$USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$db'" | tr -d '[:space:]')"
  if [[ "$exists" == "1" ]]; then
    echo "  $db already exists."
  else
    compose_infra exec -T postgres psql -U "$USER" -d postgres -c "CREATE DATABASE $db"
    compose_infra exec -T postgres psql -U "$USER" -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE $db TO $USER"
    echo "  created $db."
  fi
  compose_infra exec -T postgres psql -U "$USER" -d "$db" -c "CREATE EXTENSION IF NOT EXISTS vector" >/dev/null
done

# Product roles. The lab admin account creates them. The products connect as these roles.
ensure_login_role() {
  local role="$1"
  local password="$2"
  local password_sql
  if [[ ! "$role" =~ ^[a-z_][a-z0-9_]*$ ]]; then
    echo "ERROR: refusing unsafe role name: $role" >&2
    exit 1
  fi
  if [[ -z "$password" ]]; then
    echo "ERROR: password for role $role is empty. Set it in .env." >&2
    exit 1
  fi
  password_sql="${password//\'/\'\'}"
  echo "Ensuring role '$role' exists..."
  compose_infra exec -T postgres psql -U "$USER" -d postgres -v ON_ERROR_STOP=1 -c \
    "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${role}') THEN CREATE ROLE ${role} LOGIN PASSWORD '${password_sql}'; ELSE ALTER ROLE ${role} WITH LOGIN PASSWORD '${password_sql}'; END IF; END \$\$;"
}

ensure_owned_database() {
  local db="$1"
  local owner="$2"
  local exists
  echo "Ensuring database '$db' exists (owner=$owner)..."
  exists="$(compose_infra exec -T postgres \
    psql -U "$USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '${db}'" | tr -d '[:space:]')"
  if [[ "$exists" == "1" ]]; then
    compose_infra exec -T postgres psql -U "$USER" -d postgres -c "ALTER DATABASE ${db} OWNER TO ${owner}"
    echo "  $db already exists."
  else
    compose_infra exec -T postgres psql -U "$USER" -d postgres -c "CREATE DATABASE ${db} OWNER ${owner}"
    echo "  created $db."
  fi
}

ensure_login_role temporal "${TEMPORAL_DB_PASSWORD:-}"
ensure_login_role paperclip "${PAPERCLIP_DB_PASSWORD:-}"
ensure_login_role mandate_owner "${MANDATE_DB_OWNER_PASSWORD:-}"
ensure_login_role mandate_app "${MANDATE_DB_APP_PASSWORD:-}"

ensure_owned_database temporal temporal
ensure_owned_database temporal_visibility temporal
ensure_owned_database paperclip paperclip
ensure_owned_database mandate mandate_owner
# mandate_app is the runtime role. Schema grants come later from Mandate's own migrations.
