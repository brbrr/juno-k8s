# End-User Juno Node on Kubernetes

This is a simple but robust baseline to run a Juno node with built-in metrics and logs.

## What End-Users Get

- Juno node (`juno`) with persistent data volume
- Metrics stack: Prometheus
- Log stack: Loki + Promtail
- Dashboards and log exploration: Grafana

## Robust Defaults Included

- PersistentVolumeClaims for Juno, Prometheus, Loki, Grafana
- Resource requests/limits on all workloads
- Liveness/readiness probes everywhere
- `startupProbe` on Juno for slow startup/sync windows
- `Recreate` strategy on stateful single-replica services to avoid PVC rollout issues
- Grafana exposed internally (`ClusterIP`), accessed via `port-forward`

## Deploy

1. Create staking secret only if you need staking:

```bash
cp k8s/secrets/staking.yaml.example k8s/secrets/staking.yaml
vim k8s/secrets/staking.yaml
```

2. Deploy:

```bash
./scripts/apply.sh
```

3. Open Grafana:

```bash
kubectl -n starknet port-forward svc/grafana 3000:3000
```

4. Open Prometheus:

```bash
kubectl -n starknet port-forward svc/prometheus 9090:9090
```

## Verify Node + Observability

```bash
kubectl get pods -n starknet
kubectl get pvc -n starknet
kubectl logs -n starknet deployment/juno -f
```

Prometheus target check:

- `http://localhost:9090/targets`

Grafana quick checks:

- Metrics datasource: `Prometheus`
- Logs datasource: `Loki`
- Example LogQL query: `{namespace="starknet", app="juno"}`

## Recommended Production Adjustments

- Increase `k8s/pvcs/juno.yaml` to `800Gi` for mainnet.
- Replace default Grafana admin password before external exposure.
- Keep services internal and publish via authenticated Ingress if needed.
