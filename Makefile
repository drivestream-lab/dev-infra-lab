# Shared local-dev lab — postgres, redis, litellm on network lab_local
# Product overlays join lab_local from their own repos. See `make help`.

.PHONY: help infra-up infra-down infra-logs infra-ps infra-health down down-clean platform-up platform-down platform-health paperclip-bootstrap runner-up runner-down runner-logs runner-test runner-reset-sandbox

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
	@echo "Platform (Temporal, Temporal UI, Paperclip). Not started by infra-up:"
	@echo "  make platform-up      Start core lab, then Temporal, Temporal UI, Paperclip"
	@echo "  make platform-health  Probe core plus :7233 :8233 :3100"
	@echo "  make platform-down    Stop Temporal, Temporal UI, and Paperclip (KEEP volumes)"
	@echo ""
	@echo "Paperclip first admin (after make platform-up):"
	@echo "  No admin has claimed the instance yet."
	@echo "  Sign in or create an account in the browser, then claim it:"
	@echo "    http://localhost:3100/auth?next=/"
	@echo "  Or print a one-time invite URL from the Paperclip container:"
	@echo "    make paperclip-bootstrap"
	@echo ""
	@echo "mandate-runner (grades Mandate PRs, posts mandate/build-verified). Not started by infra-up:"
	@echo "  make runner-up             Start core lab, then the runner and its sandbox"
	@echo "  make runner-down           Stop the runner and its sandbox (KEEP volumes)"
	@echo "  make runner-logs           Follow the runner's logs (run logs: http://localhost:8090/runs/<id>.log)"
	@echo "  make runner-test           Unit tests for the runner (in a container)"
	@echo "  make runner-reset-sandbox  Recreate the sandbox from scratch (drops its images and state)"
	@echo ""
	@echo "Overlays (separate repos):"
	@echo "  cd ../example-local && make up"
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
	@bash -c 'source "$(LIB)" && compose_infra --profile platform --profile runner down'

runner-up:
	@test -r "$$HOME/.mandate/secrets/build/mandate-runner/private-key.pem" || { echo "ERROR: ~/.mandate/secrets/build/mandate-runner/ is missing its key" >&2; exit 1; }
	@$(MAKE) infra-up
	@bash -c 'source "$(LIB)" && compose_infra --profile runner up -d --build mandate-runner-dind mandate-runner'
	@bash -c 'source "$(LIB)" && wait_container_healthy lab-mandate-runner-dind 120 && wait_container_healthy lab-mandate-runner 240'
	@echo "mandate-runner up. Run logs: http://localhost:8090/runs/<run-id>.log"

runner-down:
	@bash -c 'source "$(LIB)" && compose_infra --profile runner stop mandate-runner mandate-runner-dind'

runner-logs:
	@bash -c 'source "$(LIB)" && compose_infra --profile runner logs -f mandate-runner'

runner-test:
	@docker build -q --target test --build-context config=$(ROOT)config/mandate-runner -t drivestream-lab/mandate-runner:test $(ROOT)services/mandate-runner >/dev/null
	@docker run --rm drivestream-lab/mandate-runner:test

runner-reset-sandbox:
	@bash -c 'source "$(LIB)" && compose_infra --profile runner rm -sf mandate-runner-dind'
	@docker volume rm -f dev-infra-lab_mandate_runner_dind_data >/dev/null
	@bash -c 'source "$(LIB)" && compose_infra --profile runner up -d mandate-runner-dind && wait_container_healthy lab-mandate-runner-dind 120'

platform-up:
	@$(MAKE) infra-up
	@bash -c 'source "$(LIB)" && compose_infra --profile platform up -d temporal temporal-ui paperclip'
	@bash -c 'source "$(LIB)" && wait_container_healthy lab-temporal 240 && wait_container_healthy lab-temporal-ui 120 && wait_container_healthy lab-paperclip 240'
	@$(MAKE) platform-health
	@echo "Platform up. Temporal UI: http://localhost:8233  Paperclip: http://localhost:3100"

platform-down:
	@bash -c 'source "$(LIB)" && compose_infra --profile platform stop temporal temporal-ui paperclip'

paperclip-bootstrap:
	@bash -c 'source "$(LIB)" && compose_infra --profile platform exec -T paperclip npx --yes paperclipai auth bootstrap-ceo --base-url http://localhost:3100'

platform-health:
	@$(MAKE) infra-health
	@bash -c 'source "$(LIB)" && compose_infra exec -T temporal temporal operator cluster health --address temporal:7233'
	@curl -sf http://localhost:8233 >/dev/null && echo "temporal-ui: ok"
	@curl -sf http://localhost:3100/api/health >/dev/null && echo "paperclip: ok"

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
	@echo "WARNING: removing containers AND volumes (postgres/redis/paperclip data, runner results and logs)."
	@bash -c 'source "$(LIB)" && compose_infra --profile platform --profile runner down -v'
