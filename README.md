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

By default the image is published to **GHCR** as `ghcr.io/<org>/<repo>` using the `GITHUB_TOKEN`. To publish to your own registry (e.g. Harbor on `git.sec.xbcnet.at`) instead:

```yaml
env:
  REGISTRY: harbor.sec.xbcnet.at
  IMAGE_NAME: system1/laya
# and change the login step to use your registry + secret
#   secrets: REGISTRY_TOKEN
```

## Layout

```
Dockerfile                     image definition (CUDA runtime, healthcheck)
docker-compose.yml             one-command deploy
checkpoints/                   model weights (mounted, git-ignored)
.github/workflows/build-release.yml   CI build & publish
```
