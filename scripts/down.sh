#!/usr/bin/env bash
# Delete the local Kind cluster created by scripts/up.sh.
set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: $1 is required" >&2; exit 1; }
}
require_cmd kind

kind delete cluster --name "${KIND_CLUSTER:-cursor-pool}"
