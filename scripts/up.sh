#!/usr/bin/env bash
# Build the worker image, load it into Kind, and apply the pool manifests.
set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_LIB_DIR}/lib.sh"
cd "$ROOT"

require_cmd docker kind kubectl curl
KEY="$(load_api_key)"

manifest_pool="$(awk '
  $1 == "-" && $2 == "name:" && $3 == "POOL_NAME" { grab=1; next }
  grab && $1 == "value:" { gsub(/"/, "", $2); print $2; exit }
' "$ROOT/manifests/deployment.yaml")"
if [[ "$manifest_pool" != "$POOL" ]]; then
  echo "error: POOL is '${POOL}' but manifests/deployment.yaml sets POOL_NAME to '${manifest_pool:-<missing>}'." >&2
  echo "       Workers join the manifest value. Keep POOL and POOL_NAME the same." >&2
  exit 1
fi

echo "== register pool $POOL =="
curl -fsS --request POST \
  --url "https://api.cursor.com/v0/private-workers/pools" \
  -u "$KEY:" \
  --header 'Content-Type: application/json' \
  --data "{\"scope\":\"team\",\"poolName\":\"$POOL\"}" || true
echo

echo "== kind cluster =="
if ! kind get clusters 2>/dev/null | grep -qx cursor-pool; then
  kind create cluster --config "$ROOT/cluster/kind-config.yaml"
else
  echo "cluster exists"
  kubectl cluster-info --context kind-cursor-pool
fi

echo "== fix kind egress (iptables-legacy) =="
if [[ -x "$ROOT/scripts/fix-kind-egress.sh" ]]; then
  "$ROOT/scripts/fix-kind-egress.sh" || true
fi

# kube-proxy iptables mode needs xt_statistic, which some hosts do not have.
if kubectl -n kube-system get cm kube-proxy >/dev/null 2>&1; then
  if kubectl -n kube-system get cm kube-proxy -o yaml | grep -q 'mode: iptables'; then
    echo "== kube-proxy mode nftables =="
    kubectl -n kube-system get cm kube-proxy -o yaml \
      | sed 's/mode: iptables/mode: nftables/' \
      | kubectl apply -f -
    kubectl -n kube-system delete pod -l k8s-app=kube-proxy --force --grace-period=0 2>/dev/null || true
    sleep 3
  fi
fi

echo "== build + load image =="
docker build -t cursor-pool-worker:demo -f "$ROOT/docker/Dockerfile" "$ROOT/docker"
kind load docker-image cursor-pool-worker:demo --name cursor-pool

echo "== apply manifests =="
kubectl apply -f "$ROOT/manifests/namespace.yaml"
kubectl -n cursord create secret generic cursor-workers-api-key \
  --from-literal=api-key="$KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$ROOT/manifests/deployment.yaml"
kubectl apply -f "$ROOT/manifests/service.yaml"

if ! kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1; then
  echo "== metrics-server (Kind) =="
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  kubectl -n kube-system patch deploy metrics-server --type json -p '[
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"}
  ]' || true
  kubectl -n kube-system rollout status deploy/metrics-server --timeout=120s || true
fi

kubectl apply -f "$ROOT/manifests/hpa.yaml"
if [[ "${SKIP_QUEUE_SCALER:-}" == "1" ]]; then
  echo "== skip demo queue-scaler =="
else
  kubectl apply -f "$ROOT/manifests/queue-scaler.yaml"
fi

echo "== wait for worker =="
kubectl -n cursord rollout status deploy/cursor-pool-worker --timeout=180s
kubectl -n cursord get pods,hpa,deploy
curl -fsS -u "$KEY:" https://api.cursor.com/v0/private-workers/summary
echo
echo "Pool ready: $POOL"
echo "In Cursor, open Remote Machines and select $POOL."
