# Makefile for the sous-chef-api Go service.
#
# Depends on: a working Go 1.26 toolchain, gofumpt, golangci-lint
# (all available on PATH).
# Depended on by: developers running the build/test/lint cycle locally, and
# CI which calls the same targets so local and CI behaviour cannot drift.
# Why it exists: one canonical set of verbs (build, test, lint, fmt, run)
# means a developer joining the project does not have to guess which `go`
# incantation matches the dc-07 gates.

.DEFAULT_GOAL := help
.PHONY: help build test lint fmt fmt-check run tidy clean

BIN_DIR := bin
BIN     := $(BIN_DIR)/sous-chef-api

# build compiles the binary with the version stamp wired into buildinfo. The
# -ldflags ... -X path lets a deployment carry the git SHA without requiring
# the binary to read a file at startup. The default values are "dev" so a
# plain `make build` from a clean working tree builds something useful.
VERSION    ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
BUILD_TIME ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS    := -ldflags "-s -w \
  -X github.com/djd39448/Sous-Chef-Claude2/backend/internal/buildinfo.Version=$(VERSION) \
  -X github.com/djd39448/Sous-Chef-Claude2/backend/internal/buildinfo.BuildTime=$(BUILD_TIME)"

build: ## compile the binary into bin/sous-chef-api
	@mkdir -p $(BIN_DIR)
	go build $(LDFLAGS) -o $(BIN) ./cmd/sous-chef-api

test: ## run unit tests across every package
	go test ./...

lint: ## run go vet and golangci-lint
	go vet ./...
	golangci-lint run ./...

fmt: ## format every Go file in-place with gofumpt
	gofumpt -w .

fmt-check: ## fail if any file is not gofumpt-clean (CI guard)
	@unformatted=$$(gofumpt -l .); \
	if [ -n "$$unformatted" ]; then \
	  echo "files need gofumpt:"; \
	  echo "$$unformatted"; \
	  exit 1; \
	fi

run: build ## build then run the binary; expects env vars per internal/config
	./$(BIN)

tidy: ## refresh go.mod / go.sum after dependency changes
	go mod tidy

clean: ## remove the bin directory
	rm -rf $(BIN_DIR)

help: ## print this help
	@awk 'BEGIN {FS = ":.*##"; printf "Targets:\n"} \
	      /^[a-zA-Z_-]+:.*##/ {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
