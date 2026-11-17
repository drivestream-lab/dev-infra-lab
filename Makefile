# Shared local-dev lab — postgres, redis, litellm on network lab_local
# Product overlays: ../adh-iac-local (Buzz), ../realworld-local (api/web)

.PHONY: help infra-up infra-down infra-logs infra-ps infra-health down down-clean

ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
LIB := $(ROOT)scripts/compose-lib.sh

help:
	@echo "dev-infra-lab (shared Postgres Redis LiteLLM)"
	@echo ""
	@echo "  make infra-up       Start shared lab; wait until healthy (keeps volumes)"
	@echo "  make infra-down     Stop containers (KEEP named volumes)"
	@echo "  make infra-logs     Follow logs"
	@echo "  make infra-ps       Status"
	@echo "  make infra-health   Probe :5432 :6379 :4000"
	@echo "  make down           Alias for infra-down"
	@echo "  make down-clean     Destroy containers AND volumes (DESTRUCTIVE)"
	@echo ""
	@echo "Overlays (separate repos):"
	@echo "  cd ../adh-iac-local && make buzz-up"
	@echo "  cd ../realworld-local && make up"
	@echo ""
	@echo "Streaming hole (Kafka/Flink): docker-compose.streaming.yml — not default"

infra-up:
	@bash -c 'source "$(LIB)" && ensure_env_file && ensure_shared_resources'
	@bash "$(ROOT)scripts/render-litellm-config.sh"
	@bash -c 'source "$(LIB)" && compose_infra up -d && wait_infra_core'
	@bash "$(ROOT)scripts/ensure-databases.sh"
	@$(MAKE) infra-health
	@echo "Lab up. Network: lab_local  UI: http://localhost:4000/ui"

infra-down:
	@bash -c 'source "$(LIB)" && compose_infra down'

down: infra-down

infra-logs:
	@bash -c 'source "$(LIB)" && compose_infra logs -f'

infra-ps:
	@bash -c 'source "$(LIB)" && compose_infra ps -a'

infra-health:
	@bash -c 'source "$(LIB)" && \
	  compose_infra exec -T postgres pg_isready -U "$${POSTGRES_USER:-adh}" && \
	  compose_infra exec -T redis redis-cli ping && \
	  curl -sf http://localhost:4000/health/liveliness >/dev/null && echo "litellm: ok" && \
	  echo "UI: http://localhost:4000/ui"'

down-clean:
	@echo "WARNING: removing containers AND volumes (postgres/redis data)."
	@bash -c 'source "$(LIB)" && compose_infra down -v'
