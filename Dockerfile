# syntax=docker/dockerfile:1
#
# Laya - multilingual, non-autoregressive System 1 decision model
# Self-hosted Jev-compatible HTTP server: laya-serve
#
# GPU notes:
#   - nvidia-cuda-runtime-cu12 provides the CUDA driver API client libraries
#     inside the container. The actual NVIDIA driver lives on the host and is
#     exposed via the NVIDIA Container Toolkit (--gpus all / nvidia runtime).
#   - Without GPU passthrough, set LAYA_DEVICE=cpu.
FROM python:3.11-slim

# CUDA runtime layer (adjust to your GPU; example is CUDA 12.x)
RUN pip install --no-cache-dir nvidia-cuda-runtime-cu12 || true

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    LAYA_DEVICE=cuda \
    LAYA_PRELOAD=1 \
    USE_TF=0

WORKDIR /app

# curl is handy for debugging and compose healthchecks
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Pin the package version for reproducibility.
# Build with --build-arg LAYA_VERSION=0.3.11 (or any pinned release).
ARG LAYA_VERSION=latest
RUN pip install --no-cache-dir "laya[serve]==${LAYA_VERSION}" \
    || pip install --no-cache-dir "laya[serve]"

# DGX Spark / GB10 (Blackwell sm_120) fix:
# Some torch releases that laya pulls predate Blackwell and crash the forward
# pass on a GB10 (SIGSEGV, no traceback -> the server returns 500). Force a
# torch build with sm_120 + CUDA 12.8/13 support. Best-effort: if the pinned
# laya is incompatible, the build still succeeds (falls back to its torch) and
# you can run CPU-only via LAYA_DEVICE=cpu.
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu128 \
        "torch>=2.7" || true

# Checkpoints live here and are mounted from the host at runtime, so weights
# are never baked into the image and rebuilds stay small.
RUN mkdir -p /app/checkpoints

EXPOSE 8000

# Lightweight TCP liveness probe: avoids running a model inference every 30s.
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD python -c "import socket; s=socket.socket(); s.connect(('localhost',8000)); s.close()" || exit 1

CMD ["laya-serve"]
