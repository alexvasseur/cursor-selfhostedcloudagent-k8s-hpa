#!/usr/bin/env bash
# Long-lived pool worker. Opens outbound HTTPS to Cursor; nothing listens publicly.
set -euo pipefail

: "${CURSOR_API_KEY:?CURSOR_API_KEY required (service-account API key)}"
: "${POOL_NAME:=kind-demo}"
: "${WORKER_NAME:=kind-worker}"

export PATH="/root/.local/bin:/usr/local/bin:${PATH}"

exec agent worker \
  --pool "$POOL_NAME" \
  --name "${WORKER_NAME}-${HOSTNAME}" \
  --worker-dir /workspace \
  --management-addr 0.0.0.0:8080 \
  --idle-release-timeout "${IDLE_RELEASE_TIMEOUT:-600}" \
  start --verbose
