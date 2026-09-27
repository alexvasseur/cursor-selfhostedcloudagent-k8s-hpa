#!/usr/bin/env bash
# Manual 1→5→1 scale walkthrough. Pauses the HPA and the demo queue-scaler so they do not fight.
set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_LIB_DIR}/lib.sh"

require_cmd kubectl curl python3
KEY="$(load_api_key)"
NS="${NAMESPACE:-cursord}"

echo "Current:"
kubectl -n "$NS" get deploy cursor-pool-worker
kubectl -n "$NS" get hpa cursor-pool-worker 2>/dev/null || true
kubectl -n "$NS" get pods -l app=cursor-pool-worker -o wide
curl -fsS -u "$KEY:" https://api.cursor.com/v0/private-workers/summary; echo

echo "Pause autoscalers (HPA + queue-scaler)"
kubectl -n "$NS" scale deploy/queue-scaler --replicas=0 2>/dev/null || true
kubectl -n "$NS" delete hpa cursor-pool-worker --ignore-not-found
kubectl -n "$NS" wait --for=delete pod -l app=queue-scaler --timeout=60s 2>/dev/null || true

echo "Scale 1 -> 5"
kubectl -n "$NS" scale deploy/cursor-pool-worker --replicas=5
kubectl -n "$NS" rollout status deploy/cursor-pool-worker --timeout=300s
kubectl -n "$NS" get pods -l app=cursor-pool-worker
for _ in $(seq 1 20); do
  CONN=$(curl -fsS -u "$KEY:" https://api.cursor.com/v0/private-workers/pools \
    | POOL_NAME="$POOL" python3 -c 'import json,os,sys
d=json.load(sys.stdin)
name=os.environ["POOL_NAME"]
print(next((p["connectedWorkerCount"] for p in d.get("pools",[]) if p.get("poolName")==name),0))')
  echo "${POOL} connected=$CONN"
  [[ "$CONN" -ge 5 ]] && break
  sleep 3
done
curl -fsS -u "$KEY:" https://api.cursor.com/v0/private-workers/summary; echo

echo "Scale 5 -> 1"
kubectl -n "$NS" scale deploy/cursor-pool-worker --replicas=1
kubectl -n "$NS" rollout status deploy/cursor-pool-worker --timeout=120s
kubectl -n "$NS" get pods -l app=cursor-pool-worker

echo "Restore autoscalers"
kubectl apply -f "$ROOT/manifests/hpa.yaml"
if kubectl -n "$NS" get deploy queue-scaler >/dev/null 2>&1; then
  kubectl -n "$NS" scale deploy/queue-scaler --replicas=1
fi
sleep 3
curl -fsS -u "$KEY:" https://api.cursor.com/v0/private-workers/summary; echo
