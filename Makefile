# Build / release helpers for the DGX Spark (arm64) and CI release builds.
#
# The DGX Spark is arm64: always build natively on the device (`make build`),
# never cross-build from an amd64 machine for the Spark.

# Host port for the smoke test (override: make test PORT=8003)
PORT ?= 8003

.PHONY: build build-pinned up down logs ps test push release tag

build: ## Build the image natively on the DGX Spark (arm64, no emulation)
	docker compose build

build-pinned: ## Build with a pinned laya PyPI release (e.g. make build-pinned VERSION=0.3.11)
	docker compose build --build-arg LAYA_VERSION=$(VERSION)

up: ## Start the container with GPU passthrough
	docker compose up -d

down: ## Stop and remove the container
	docker compose down

logs: ## Follow container logs
	docker compose logs -f

ps: ## Container status
	docker compose ps

# Smoke-test the running server (default port 8003, override with PORT=...)
test: ## Curl /v1/systemone against localhost
	@curl -fsS localhost:$(PORT)/v1/systemone -H 'Content-Type: application/json' -d '{"state": {"document": "I was charged twice. Please fix this ASAP."}, "questions": {"billing": {"type": "noul", "instructions": "Is this ticket about billing?"}}}' ; echo

# Publish the locally-built image to your registry (default GHCR).
#   make push REGISTRY=ghcr.io/cloudn1ne/system1 VERSION=0.1.0
push: ## docker tag + push the local image to REGISTRY
	docker tag laya-serve $(REGISTRY):$(VERSION)
	docker push $(REGISTRY):$(VERSION)

# Trigger the CI release build (builds amd64+arm64 and publishes to the registry).
#   make release VERSION=0.1.0
release: ## git tag v$(VERSION) and push -> CI builds the release image
	git tag v$(VERSION)
	git push origin v$(VERSION)
