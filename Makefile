# Makefile for tarpn-mon (Go backend with embedded frontend)
#
# Usage:
#   make build          - Build for current platform
#   make build-arm32    - Cross-compile for Raspberry Pi (32-bit)
#   make build-arm64    - Cross-compile for Raspberry Pi (64-bit)
#   make frontend       - Build React Native web frontend
#   make clean          - Remove build artifacts
#   make run            - Run locally (dev mode)
#
# The frontend is embedded in the Go binary via go:embed

SHELL := /bin/bash
.PHONY: all build build-arm32 build-arm64 frontend clean run dev help \
       build-sendroutesviacq-arm32 build-sendroutesviacq-arm64 build-sendroutesviacq-amd64 \
       build-linktest-arm32 build-linktest-arm64 build-linktest-amd64 \
       build-sendroutesviacq test-sendroutesviacq

# Directories
ROOT_DIR := $(shell pwd)
FRONTEND_DIR := $(ROOT_DIR)/tarpn-terminal
SENDROUTESVIACQ_DIR := $(ROOT_DIR)/sendroutesviacq
LINKTEST_DIR := $(ROOT_DIR)/linktest
DIST_DIR := $(ROOT_DIR)/dist

# Version (from git or fallback)
VERSION := $(shell git describe --tags 2>/dev/null || echo "dev")

# Output names
BINARY_NAME := tarpn-mon
SENDROUTESVIACQ_NAME := send-routes-via-cq
LINKTEST_NAME := linktest

# Frontend source files (for dependency tracking)
FRONTEND_SOURCES := $(shell find $(FRONTEND_DIR)/src -type f 2>/dev/null)
FRONTEND_DIST := $(FRONTEND_DIR)/dist/index.html

help:
	@echo "tarpn-mon build system"
	@echo ""
	@echo "Targets:"
	@echo "  make build        - Build for current platform"
	@echo "  make build-arm32  - Cross-compile for Raspberry Pi (32-bit)"
	@echo "  make build-arm64  - Cross-compile for Raspberry Pi (64-bit)"
	@echo "  make build-amd64  - Build for x86_64 Linux"
	@echo "  make frontend     - Build React Native web frontend"
	@echo "  make run          - Run locally (requires frontend built)"
	@echo "  make dev          - Run with auto-reload (dev mode)"
	@echo "  make clean        - Remove build artifacts"
	@echo ""
	@echo "  make build-sendroutesviacq          - Build send-routes-via-cq for current platform"
	@echo "  make build-sendroutesviacq-arm32    - Cross-compile send-routes-via-cq for Pi (32-bit)"
	@echo "  make build-sendroutesviacq-arm64    - Cross-compile send-routes-via-cq for Pi (64-bit)"
	@echo "  make build-sendroutesviacq-amd64    - Build send-routes-via-cq for x86_64"
	@echo "  make build-linktest-arm32           - Cross-compile linktest for Pi (32-bit)"
	@echo "  make build-linktest-arm64           - Cross-compile linktest for Pi (64-bit)"
	@echo "  make build-linktest-amd64           - Build linktest for x86_64"
	@echo "  make test-sendroutesviacq           - Run send-routes-via-cq tests"
	@echo ""
	@echo "Version: $(VERSION)"

# Web-dist directory (where Go embeds from)
WEB_DIST_DIR := $(ROOT_DIR)/web-dist

# Build frontend (incremental - only if sources changed)
$(FRONTEND_DIST): $(FRONTEND_SOURCES) $(FRONTEND_DIR)/package.json
	@echo "Building frontend..."
	cd $(FRONTEND_DIR) && npm install --silent && npx expo export -p web --output-dir dist
	@touch $(FRONTEND_DIST)

# web-dist is what main.go embeds via //go:embed all:web-dist. It gets its own
# rule rather than being a side effect of the frontend build: it is gitignored,
# so it is routinely absent on a fresh clone or after a clean, and without a
# rule of its own make considers the frontend up to date and the Go build then
# fails with "pattern all:web-dist: no matching files found".
WEB_DIST := $(WEB_DIST_DIR)/index.html

$(WEB_DIST): $(FRONTEND_DIST)
	@echo "Syncing to web-dist for embedding..."
	@rm -rf $(WEB_DIST_DIR)
	@cp -r $(FRONTEND_DIR)/dist $(WEB_DIST_DIR)

frontend: $(FRONTEND_DIST)
	@echo "Frontend built: $(FRONTEND_DIST)"

# Build for current platform
build: $(WEB_DIST)
	@echo "Building tarpn-mon for current platform..."
	@mkdir -p $(DIST_DIR)
	go build -ldflags="-s -w -X main.Version=$(VERSION)" -o $(DIST_DIR)/$(BINARY_NAME) .
	@ls -lh $(DIST_DIR)/$(BINARY_NAME)

# Cross-compile for ARM32 (Raspberry Pi 32-bit)
build-arm32: $(WEB_DIST)
	@echo "Building tarpn-mon for linux/arm32..."
	@mkdir -p $(DIST_DIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 \
		go build -ldflags="-s -w -X main.Version=$(VERSION)" \
		-o $(DIST_DIR)/$(BINARY_NAME).linux-arm32 .
	@ls -lh $(DIST_DIR)/$(BINARY_NAME).linux-arm32

# Cross-compile for ARM64 (Raspberry Pi 64-bit)
build-arm64: $(WEB_DIST)
	@echo "Building tarpn-mon for linux/arm64..."
	@mkdir -p $(DIST_DIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
		go build -ldflags="-s -w -X main.Version=$(VERSION)" \
		-o $(DIST_DIR)/$(BINARY_NAME).linux-arm64 .
	@ls -lh $(DIST_DIR)/$(BINARY_NAME).linux-arm64

# Cross-compile for AMD64 (x86_64 Linux)
build-amd64: $(WEB_DIST)
	@echo "Building tarpn-mon for linux/amd64..."
	@mkdir -p $(DIST_DIR)
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build -ldflags="-s -w -X main.Version=$(VERSION)" \
		-o $(DIST_DIR)/$(BINARY_NAME).linux-amd64 .
	@ls -lh $(DIST_DIR)/$(BINARY_NAME).linux-amd64

# Build all architectures
build-all: build-arm32 build-arm64 build-amd64 build-sendroutesviacq-arm32 build-sendroutesviacq-arm64 build-sendroutesviacq-amd64 \
       build-linktest-arm32 build-linktest-arm64 build-linktest-amd64
	@echo "All architectures built in $(DIST_DIR)/"
	@ls -lh $(DIST_DIR)/

# =============================================================================
# send-routes-via-cq (separate Go module in sendroutesviacq/)
# =============================================================================

# Build for current platform
build-sendroutesviacq:
	@echo "Building send-routes-via-cq for current platform..."
	@mkdir -p $(DIST_DIR)
	cd $(SENDROUTESVIACQ_DIR) && go build -ldflags="-s -w -X main.Version=$(VERSION)" -o $(DIST_DIR)/$(SENDROUTESVIACQ_NAME) .
	@ls -lh $(DIST_DIR)/$(SENDROUTESVIACQ_NAME)

# Cross-compile for ARM32
build-linktest-arm32:
	@echo "Building linktest for linux/arm32..."
	@mkdir -p $(DIST_DIR)
	cd $(LINKTEST_DIR) && CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 \
		go build -ldflags="-s -w -X main.Version=$(VERSION)" -o $(DIST_DIR)/$(LINKTEST_NAME).linux-arm32 .
	@ls -lh $(DIST_DIR)/$(LINKTEST_NAME).linux-arm32

build-linktest-arm64:
	@echo "Building linktest for linux/arm64..."
	@mkdir -p $(DIST_DIR)
	cd $(LINKTEST_DIR) && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
		go build -ldflags="-s -w -X main.Version=$(VERSION)" -o $(DIST_DIR)/$(LINKTEST_NAME).linux-arm64 .
	@ls -lh $(DIST_DIR)/$(LINKTEST_NAME).linux-arm64

build-linktest-amd64:
	@echo "Building linktest for linux/amd64..."
	@mkdir -p $(DIST_DIR)
	cd $(LINKTEST_DIR) && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build -ldflags="-s -w -X main.Version=$(VERSION)" -o $(DIST_DIR)/$(LINKTEST_NAME).linux-amd64 .
	@ls -lh $(DIST_DIR)/$(LINKTEST_NAME).linux-amd64

build-sendroutesviacq-arm32:
	@echo "Building send-routes-via-cq for linux/arm32..."
	@mkdir -p $(DIST_DIR)
	cd $(SENDROUTESVIACQ_DIR) && CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 \
		go build -ldflags="-s -w -X main.Version=$(VERSION)" -o $(DIST_DIR)/$(SENDROUTESVIACQ_NAME).linux-arm32 .
	@ls -lh $(DIST_DIR)/$(SENDROUTESVIACQ_NAME).linux-arm32

# Cross-compile for ARM64
build-sendroutesviacq-arm64:
	@echo "Building send-routes-via-cq for linux/arm64..."
	@mkdir -p $(DIST_DIR)
	cd $(SENDROUTESVIACQ_DIR) && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
		go build -ldflags="-s -w -X main.Version=$(VERSION)" -o $(DIST_DIR)/$(SENDROUTESVIACQ_NAME).linux-arm64 .
	@ls -lh $(DIST_DIR)/$(SENDROUTESVIACQ_NAME).linux-arm64

# Cross-compile for AMD64
build-sendroutesviacq-amd64:
	@echo "Building send-routes-via-cq for linux/amd64..."
	@mkdir -p $(DIST_DIR)
	cd $(SENDROUTESVIACQ_DIR) && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
		go build -ldflags="-s -w -X main.Version=$(VERSION)" -o $(DIST_DIR)/$(SENDROUTESVIACQ_NAME).linux-amd64 .
	@ls -lh $(DIST_DIR)/$(SENDROUTESVIACQ_NAME).linux-amd64

# Run tests
test-sendroutesviacq:
	@echo "Testing send-routes-via-cq..."
	cd $(SENDROUTESVIACQ_DIR) && go test -v ./...

# Run locally
run: $(FRONTEND_DIST)
	go run . -call N0CALL

# Dev mode (if air or similar is installed)
dev:
	@if command -v air &>/dev/null; then \
		air; \
	else \
		echo "Run: go install github.com/cosmtrek/air@latest"; \
		echo "Or use: make run"; \
	fi

# Clean build artifacts
clean:
	rm -rf $(DIST_DIR)
	rm -rf $(FRONTEND_DIR)/dist
	rm -f $(BINARY_NAME)

# Also clean node_modules (deep clean)
clean-all: clean
	rm -rf $(FRONTEND_DIR)/node_modules
