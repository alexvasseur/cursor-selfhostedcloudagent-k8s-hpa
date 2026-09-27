#!/usr/bin/env bash
# Refresh pods and pool claim state until you stop it with Ctrl-C.
set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_LIB_DIR}/lib.sh"

require_cmd kubectl curl python3
KEY="$(load_api_key)"
CTX="${KUBE_CONTEXT:-kind-cursor-pool}"
NS="${NAMESPACE:-cursord}"

echo "=== ${POOL} claim watch (Ctrl-C to stop) ==="
echo "Waiting for a Cloud Agent to claim a worker in pool ${POOL}..."
echo
while true; do
  clear
  echo "======== $(date '+%H:%M:%S')  pool=${POOL}  ========"
  echo
  echo "--- kubectl pods (${NS}) ---"
  kubectl --context "$CTX" -n "$NS" get pods -o wide
  echo
  echo "--- private-workers summary ---"
  SUM=$(curl -fsS -u "${KEY}:" https://api.cursor.com/v0/private-workers/summary)
  echo "$SUM" | python3 -m json.tool
  echo
  echo "--- ${POOL} pool ---"
  curl -fsS -u "${KEY}:" https://api.cursor.com/v0/private-workers/pools \
    | POOL_NAME="$POOL" python3 -c 'import json,os,sys
pools=json.load(sys.stdin).get("pools",[])
name=os.environ["POOL_NAME"]
print("\n".join(json.dumps(p, indent=2) for p in pools if p.get("poolName")==name))'
  INUSE=$(echo "$SUM" | python3 -c "import sys,json; print(json.load(sys.stdin)['teamSummary']['inUse'])")
  if [ "$INUSE" != "0" ]; then
    echo
    echo "############################################"
    echo "#  CLAIMED  inUse=$INUSE  worker busy NOW  #"
    echo "############################################"
  else
    echo
    echo "(idle — inUse=0)"
  fi
  sleep 2
done
