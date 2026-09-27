# Talk track

Notes for a short live walkthrough of pool `kind-demo` on Kind. Pair this with the screenshots in `docs/screenshots/`.

## Before the demo

**Self-hosted Team Pool on Kubernetes**

- The Cloud Agent loop stays in Cursor. Tool calls run on workers in this Kind cluster.
- Pool `kind-demo` is any-repo. Workers dial out over HTTPS. The cluster has no Ingress and no TLS certificate to manage.
- The fleet uses a service-account API key. Replicas move between 1 and 5.

Show:

- The pool picker: Remote Machines, `kind-demo` selected (`docs/screenshots/01-select-kind-demo-pool.png`).
- The worker command in `docker/entrypoint.sh`: `agent worker --pool "$POOL_NAME" --idle-release-timeout 600 start`.
- The HPA in `manifests/hpa.yaml`: `minReplicas: 1`, `maxReplicas: 5`, CPU `averageUtilization: 50`.

Line to leave on: pick `kind-demo`, send a prompt, watch the claim on the worker.

## While it runs

Terminal (`scripts/watch-claim.sh`) next to the agents page.

- Start: one pod `Running`, `connectedWorkerCount` 1, `inUse` 0 (`02-k8s-worker-idle.png`).
- After the claim: two workers connected, `inUse` 1, and the `CLAIMED` banner (`03-claim-side-by-side-inuse.png`). The extra pod is the demo scaler keeping one spare above `inUse`, not the HPA reacting to CPU.

Say the split out loud: Cursor owns the queue and the agent loop; the cluster owner owns the Deployment and the HPA.

## Diagram to draw

```text
Cursor cloud
  agent loop / model
  pool routing + claim queue
  cursor.com/agents  (Remote Machines → kind-demo)

Kind cluster, namespace cursord
  Deployment cursor-pool-worker
    agent worker --pool kind-demo
  HPA cursor-pool-worker          (stock Kubernetes)
  Deployment queue-scaler         (demo helper only)

arrow: UI → claim queue → worker outbound HTTPS → tool calls back
```

The same picture is a mermaid diagram in the README.

## Say this about the scaler

`manifests/queue-scaler.yaml` is a demo helper. It is not a Cursor product. It runs the third-party image `alpine/k8s:1.31.0`, polls `GET /v0/private-workers/summary`, and runs `kubectl scale`.

The production Kubernetes path is [anysphere/k8s-workers](https://github.com/anysphere/k8s-workers): `agent worker controller --spawn` with optional `--warm-idle`. That starts a Pod per claim instead of resizing a long-lived Deployment.

## Close

- No PersistentVolumeClaim. `/workspace` is ephemeral.
- This image does not clone a git remote.
- `scripts/scale-demo.sh` is the manual 1 → 5 → 1 beat if you want to show the HPA bounds without waiting on CPU.
