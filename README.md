# system1 - Laya decision-model HTTP server (containerized)

Self-hosted deployment of **[Laya](https://huggingface.co/convaiinnovations/laya)** — a multilingual, non-autoregressive **System 1 decision model**. `laya-serve` exposes the built-in `Router` on the same `POST /v1/systemone` request/response shape as TypeSafe Jev, so existing TypeSafe clients keep working by changing their base URL.

This repo hosts:

- `Dockerfile` — CUDA-capable image for `laya-serve`
- `docker-compose.yml` — one-command deploy with GPU passthrough, checkpoint mount, healthcheck
- `.github/workflows/build-release.yml` — CI that builds and publishes the image on every push / version tag

## Quickstart

```bash
# 1. Put model checkpoints here (they are git-ignored, mounted, never baked in)
mkdir -p checkpoints
#    -> download the checkpoint(s) you serve from the HF repo into ./checkpoints

# 2. Deploy
docker compose up -d

# 3. Query (Jev-compatible)
curl -s localhost:8000/v1/systemone -H 'Content-Type: application/json' -d '{
  "state": {"document": "I was charged twice. Please fix this ASAP."},
  "questions": {"billing": {"type": "noul", "instructions": "Is this ticket about billing?"}}
}'
```

Every question shape the Jev API accepts works (`criteria` as a list, etc.); unknown fields are ignored; a malformed question returns `422` naming the problem. Set `LAYA_API_KEY` to require `Authorization: Bearer <key>`.

## GPU vs CPU

- **GPU host**: requires the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html). Compose passes the GPU through (`deploy.resources...`), and the image ships `nvidia-cuda-runtime-cu12`.
- **CPU host**: run `LAYA_DEVICE=cpu docker compose up -d` and drop the GPU `deploy:` block (see the note in the compose file).

> The CUDA **driver** must always come from the host via the toolkit; the image only carries the client-side runtime libs.

## Build on the DGX Spark (native arm64)

The DGX Spark is an NVIDIA **arm64** workstation — build the container **on the device, natively**. Native builds pull the prebuilt `aarch64` wheels (torch, CUDA runtime), so there is *no compilation* under emulation.

One-time prereqs on the Spark:
- Docker with the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (standard on DGX)
- `docker buildx` plugin (bundled with modern Docker)

```bash
# 1. get the repo
git clone git@github.com:cloudn1ne/system1.git
cd system1

# 2. download the model checkpoint(s) into ./checkpoints
mkdir -p checkpoints

#    one-time: install the HF CLI
pip install -U huggingface_hub

#    pull the whole model repo (classic CLI)
huggingface-cli download convaiinnovations/laya --local-dir checkpoints
#    newer huggingface_hub builds accept:  hf download convaiinnovations/laya --local-dir checkpoints

#    (optional) pull only the weights you serve, e.g.
#    huggingface-cli download convaiinnovations/laya --local-dir checkpoints --include "*.safetensors"

# 3. build natively (arm64, no emulation)
make build            # == docker compose build
#    or pin a release:  make build-pinned VERSION=0.3.11

# 4. run with GPU passthrough
make up               # == docker compose up -d
docker compose ps

# 5. verify (Jev-compatible endpoint)
curl -s localhost:8000/v1/systemone -H 'Content-Type: application/json' -d '{
  "state": {"document": "I was charged twice. Please fix this ASAP."},
  "questions": {"billing": {"type": "noul", "instructions": "Is this ticket about billing?"}}
}'
```

### Publishing the image from the Spark

```bash
# CI path (recommended): tag the git repo -> CI builds amd64+arm64 and publishes
make release VERSION=0.1.0          # git tag v0.1.0 && git push origin v0.1.0

# Registry path: tag + push the local image yourself
make push REGISTRY=ghcr.io/cloudn1ne/system1 VERSION=0.1.0
```

To run a CI-published image on the Spark (or anywhere): `docker pull`. The multi-arch manifest auto-selects `linux/arm64` on the Spark and `linux/amd64` elsewhere.

## Configuration

| env | default | purpose |
|-----|---------|---------|
| `LAYA_DEVICE` | `cuda` | compute device (`cuda` / `cpu`) |
| `LAYA_PRELOAD` | `1` | preload checkpoints at boot for sub-35 ms routing |
| `LAYA_API_KEY` | empty | enable `Bearer` auth |
| `LAYA_PORT` | `8000` | host port |
| `LAYA_VERSION` | `latest` | pin the installed PyPI release (compose build arg) |

## Build / release pipeline

`.github/workflows/build-release.yml` (works on GitHub Actions and Gitea Actions):

- **push to `main`** → builds and publishes `latest` (plus a `sha-*` tag)
- **push a version tag `vX.Y.Z`** → publishes a release image tagged `vX.Y.Z`
- PRs build (without pushing) as a gate
- produces **multi-arch** manifests (`linux/amd64` + `linux/arm64`) via buildx + QEMU, so the same release image runs on the DGX Spark (`arm64`) and amd64 hosts

By default the image is published to **GHCR** as `ghcr.io/cloudn1ne/system1` using the auto-provided `GITHUB_TOKEN` (no secrets to configure on GitHub). To publish to your own registry instead:

## Layout

```
Dockerfile                     image definition (CUDA runtime, healthcheck)
docker-compose.yml             one-command deploy
checkpoints/                   model weights (mounted, git-ignored)
.github/workflows/build-release.yml   CI build & publish
```
