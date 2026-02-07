# Makefile for tarpn-chat docker-testnet integration tests
#
# Usage:
#   make build     - Build tarpn-chat binary for x86_64 (musl)
#   make deploy    - Start the docker-compose network
#   make test      - Run integration tests
#   make logs      - Follow container logs
#   make clean     - Stop and remove containers
#   make all       - build + deploy + test

SHELL := /bin/bash
.PHONY: all build deploy test test-quick test-websocket logs clean status restart-clients help ci

# Paths
TARPN_CHAT_DIR := $(shell dirname $(CURDIR))
DOCKER_TESTNET_DIR := $(CURDIR)
DIST_DIR := $(TARPN_CHAT_DIR)/dist

# Binary name
BINARY := tarpn-chat-x86_64-musl

# Timeouts
STARTUP_WAIT := 45
CONVERGENCE_TIMEOUT := 120

# Detect container runtime (podman or docker)
CONTAINER_RUNTIME := $(shell which podman 2>/dev/null || which docker 2>/dev/null)
COMPOSE_CMD := $(shell which podman-compose 2>/dev/null || which docker-compose 2>/dev/null)

help:
	@echo "tarpn-chat docker-testnet integration tests"
	@echo ""
	@echo "Targets:"
	@echo "  make build         - Build tarpn-chat binary for x86_64-musl"
	@echo "  make deploy        - Start docker-compose network"
	@echo "  make test          - Run integration tests"
	@echo "  make test-websocket - Run WebSocket API tests only"
	@echo "  make logs          - Follow container logs"
	@echo "  make status        - Show container status + client health"
	@echo "  make clean         - Stop and remove containers"
	@echo "  make all           - build + deploy + test"
	@echo "  make ci            - Full CI pipeline (clean, build, deploy, test, clean)"
	@echo ""
	@echo "Options:"
	@echo "  VERBOSE=1     - Enable verbose test output"
	@echo "  TEST=name     - Run specific test (e.g., TEST=message_delivery)"
	@echo ""
	@echo "Container runtime: $(CONTAINER_RUNTIME)"
	@echo "Compose command: $(COMPOSE_CMD)"

# Build tarpn-chat binary for x86_64-musl (statically linked)
build:
	@echo "Building tarpn-chat for x86_64-musl..."
	cd $(TARPN_CHAT_DIR) && \
		cross build --release --target x86_64-unknown-linux-musl
	@mkdir -p $(DIST_DIR)
	cp $(TARPN_CHAT_DIR)/target/x86_64-unknown-linux-musl/release/tarpn-chat \
		$(DIST_DIR)/$(BINARY)
	@echo "Binary: $(DIST_DIR)/$(BINARY)"
	@ls -lh $(DIST_DIR)/$(BINARY)

# Check that binary exists
check-binary:
	@if [ ! -f "$(DIST_DIR)/$(BINARY)" ]; then \
		echo "Error: Binary not found at $(DIST_DIR)/$(BINARY)"; \
		echo "Run 'make build' first"; \
		exit 1; \
	fi

# Start docker-compose network
deploy: check-binary
	@echo "Starting docker-compose network..."
	$(COMPOSE_CMD) up -d --build
	@echo ""
	@echo "Waiting $(STARTUP_WAIT)s for network initialization..."
	@sleep $(STARTUP_WAIT)
	@echo ""
	@echo "Container status:"
	@$(COMPOSE_CMD) ps
	@echo ""
	@echo "Telnet client API endpoints:"
	@echo "  client1: http://localhost:5001/status"
	@echo "  client2: http://localhost:5002/status"
	@echo "  client6: http://localhost:5006/status"
	@echo "  client7: http://localhost:5007/status"
	@echo ""
	@echo "WebSocket client API endpoints (tarpn-chat):"
	@echo "  node4: ws://localhost:8514/"
	@echo "  node5: ws://localhost:8515/"

# Run integration tests
test:
	@echo "Running integration tests..."
	@if [ "$(VERBOSE)" = "1" ]; then \
		python3 run_tests.py --verbose --wait-for-healthy; \
	elif [ -n "$(TEST)" ]; then \
		python3 run_tests.py --test $(TEST) --wait-for-healthy; \
	else \
		python3 run_tests.py --wait-for-healthy; \
	fi

# Quick test (skip waiting for healthy)
test-quick:
	@echo "Running tests (no wait)..."
	python3 run_tests.py

# Run only WebSocket API tests
test-websocket:
	@echo "Running WebSocket API tests..."
	@echo "Note: requires websocket-client (pip install websocket-client)"
	python3 run_tests.py --wait-for-healthy \
		--test websocket_port_available && \
	python3 run_tests.py --test websocket_connect && \
	python3 run_tests.py --test websocket_send_receive && \
	python3 run_tests.py --test websocket_to_telnet && \
	python3 run_tests.py --test telnet_to_websocket

# List available tests
test-list:
	@python3 run_tests.py --list

# Follow logs from all containers
logs:
	$(COMPOSE_CMD) logs -f

# Follow logs from specific service (e.g., make logs-node4)
logs-%:
	$(COMPOSE_CMD) logs -f $*

# Show container status
status:
	@$(COMPOSE_CMD) ps
	@echo ""
	@echo "Telnet client API health:"
	@for port in 5001 5002 5006 5007; do \
		status=$$(curl -s http://localhost:$$port/health 2>/dev/null || echo '{"status":"unavailable"}'); \
		echo "  localhost:$$port: $$status"; \
	done
	@echo ""
	@echo "Client status (node counts):"
	@for port in 5001 5002 5006 5007; do \
		status=$$(curl -s http://localhost:$$port/status 2>/dev/null); \
		if [ -n "$$status" ]; then \
			client=$$(echo "$$status" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('client_id','?'))"); \
			nodes=$$(echo "$$status" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('node_count',0))"); \
			in_chat=$$(echo "$$status" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('in_chat',False))"); \
			echo "  $$client: $$nodes nodes, in_chat=$$in_chat"; \
		else \
			echo "  localhost:$$port: unavailable"; \
		fi; \
	done
	@echo ""
	@echo "WebSocket client API ports (tarpn-chat):"
	@for port in 8514 8515; do \
		nc -z localhost $$port 2>/dev/null && echo "  localhost:$$port: open" || echo "  localhost:$$port: closed"; \
	done

# Restart just the client containers (preserves node state)
restart-clients:
	$(COMPOSE_CMD) restart client1 client2 client6 client7
	@echo "Waiting 15s for clients to reconnect..."
	@sleep 15

# Stop and remove all containers
clean:
	@echo "Stopping containers..."
	$(COMPOSE_CMD) down -v
	@echo "Done"

# Full clean including images
clean-all: clean
	@echo "Removing docker images..."
	$(COMPOSE_CMD) down --rmi local -v

# Full pipeline: build, deploy, test
all: build deploy test
	@echo ""
	@echo "Integration test pipeline complete"

# CI-friendly target: non-interactive, clean before/after
ci: clean build deploy
	@echo "Running CI tests..."
	@python3 run_tests.py --wait-for-healthy; \
	EXIT_CODE=$$?; \
	echo ""; \
	echo "Cleaning up..."; \
	$(COMPOSE_CMD) down -v; \
	exit $$EXIT_CODE

# Rebuild just the client containers (after modifying chat-client.py)
rebuild-clients:
	$(COMPOSE_CMD) build client1 client2 client6 client7
	$(COMPOSE_CMD) up -d client1 client2 client6 client7
	@echo "Waiting 20s for clients to reconnect..."
	@sleep 20

# Quick deploy (skip build, use existing binary)
quick-deploy: check-binary
	@echo "Quick deploy (using existing binary)..."
	$(COMPOSE_CMD) up -d
	@echo "Waiting $(STARTUP_WAIT)s for network initialization..."
	@sleep $(STARTUP_WAIT)
	@$(MAKE) status
