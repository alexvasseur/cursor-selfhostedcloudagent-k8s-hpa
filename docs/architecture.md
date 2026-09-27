# Architecture

This demo runs Cursor Team Pool workers as a normal Kubernetes Deployment on Kind. Cursor routes a Cloud Agent chat to the pool. One connected worker claims it and executes tool calls in the pod.

## Ownership

| Owned by Cursor | Owned by you |
| --- | --- |
| Agent loop, model calls, planning | Kind cluster and namespace `cursord` |
| Pool routing and the claim queue (`/v0/private-workers`) | Worker image and Deployment |
| cursor.com/agents, including Remote Machines | Secret `cursor-workers-api-key` |
| Artifact storage for screenshots and logs the worker uploads | HorizontalPodAutoscaler |
| | Demo `queue-scaler` (optional, not a Cursor product) |

The worker process is the Cursor CLI (`agent worker --pool kind-demo start`). It is the bridge between those two sides. It is not a controller.

## Auth

Pool workers authenticate with a **service-account API key** in `CURSOR_API_KEY`. Other key types are rejected. Create the key from the [service accounts](https://cursor.com/docs/account/enterprise/service-accounts) docs, then let `scripts/up.sh` store it in the Secret, or create the Secret with kubectl. The manifests do not contain a key.

`scripts/up.sh` also registers the pool:

```bash
curl --request POST \
  --url "https://api.cursor.com/v0/private-workers/pools" \
  -u "$CURSOR_API_KEY:" \
  --header 'Content-Type: application/json' \
  --data '{"scope":"team","poolName":"kind-demo"}'
```

The same API is what `scripts/watch-claim.sh` reads: team summary (`inUse`, `totalConnected`) and per-pool `connectedWorkerCount`.

## Network

Workers are outbound-only. `agent worker start` dials Cursor; Cursor does not open a connection into the cluster. No Ingress, certificate, or public Service is required.

Outbound HTTPS from the pod needs to reach at least:

- `api2.cursor.sh` and `api2direct.cursor.sh` (agent session)
- `downloads.cursor.com` (CLI install, at image build time)
- `cloud-agent-artifacts.s3.us-east-1.amazonaws.com` (artifact upload)
- `api.cursor.com` (pool register and summary calls from `up.sh`, `watch-claim.sh`, and the demo scaler)

The Service `cursor-pool-worker` is ClusterIP port 8080. Probes hit `/readyz` and `/healthz` on the worker management address (`--management-addr 0.0.0.0:8080`).

### Kind egress on a locked-down bridge

`scripts/fix-kind-egress.sh` repairs a specific Docker host failure: nftables accepts the Kind bridge, but iptables-legacy FORWARD policy DROP still discards it. The script allows the `172.18.0.0/16` bridge through `iptables-legacy`. `scripts/up.sh` runs it after the cluster exists, and ignores failure so hosts that do not need it still come up.

If kube-proxy is in `iptables` mode, `up.sh` rewrites that ConfigMap to `nftables` and restarts kube-proxy. That avoids `xt_statistic`, which some kernels do not provide. Skip these steps on a cluster where pod egress already works; they are host workarounds, not part of the worker protocol.

## Disk and git

The Deployment has no PersistentVolumeClaim. `/workspace` is the container filesystem, mode `0777`, with no git remote. The entrypoint does not pass a clone flag, so a pod restart drops anything the agent wrote there.

Use **Start from scratch** in the agents UI for this image. Pointing the run at a repository does not check that repository out inside the pod.

## Scaling

Three levers, all clamped to the same 1–5 range in this demo:

1. **HPA** (`manifests/hpa.yaml`). CPU average utilization 50%, with a 100m request. Scale-up can add 2 pods per 15s. Scale-down waits 60s and removes 1 pod. Idle workers sit near 0 CPU, so this rarely leaves `minReplicas`.
2. **Demo queue-scaler** (`manifests/queue-scaler.yaml`). Every 20s it reads `https://api.cursor.com/v0/private-workers/summary` and, when team `inUse >= 1`, sets replicas to `inUse + 1` (max 5). One claimed chat therefore becomes two pods: the busy worker plus a spare. The container image is third-party `alpine/k8s:1.31.0`. Labels mark it `app.kubernetes.io/component: demo-helper`.
3. **Manual** (`scripts/scale-demo.sh`). Deletes the HPA, scales the queue-scaler to 0, scales the worker Deployment to 5, waits until the pool reports 5 connected workers, scales back to 1, then restores both autoscalers.

The HPA and the queue-scaler both write `.spec.replicas`. During a live claim they can disagree. For a walkthrough that only wants CPU autoscaling, set `SKIP_QUEUE_SCALER=1`. For a walkthrough that only wants the claim-driven spare, leave the scaler on and expect the HPA to stay quiet while CPU is low.

metrics-server is not part of Kind. `up.sh` installs the upstream components manifest and adds `--kubelet-insecure-tls` so the HPA can read CPU.

## Production path this demo is not

[anysphere/k8s-workers](https://github.com/anysphere/k8s-workers) is the Kubernetes sample Cursor documents for new deployments. A controller process runs:

```bash
agent worker controller --spawn ./spawn.sh --api-key "$CURSOR_API_KEY" --pool kind-demo
```

The spawn hook creates one Pod per claimed request. `--warm-idle N` keeps N unclaimed pods ready and does not sit on a long-lived Deployment plus HPA. See [Team Pools](https://cursor.com/docs/cloud-agent/self-hosted/pool) and [Integrations](https://cursor.com/docs/cloud-agent/self-hosted/integrations).

The older Kubernetes operator and `WorkerDeployment` chart are deprecated. The operator reference is [Deploy Team Pools on Kubernetes](https://cursor.com/docs/cloud-agent/self-hosted/kubernetes). This repository does not install that operator.

Cursor's cookbook still has longer Docker and cluster examples (EC2, ECS, EKS) under [`self-hosted-cloud-agent/`](https://github.com/cursor/cookbook/tree/main/self-hosted-cloud-agent). The Dockerfile there is the reference image; `docker/Dockerfile` here only installs curl, git, and the CLI so the Kind demo stays small.
