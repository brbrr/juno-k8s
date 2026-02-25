# Juno Starknet Node - Kubernetes Setup

Complete Kubernetes setup for running a Juno Starknet node with full observability (metrics and logs).

## Features

- **Juno Node**: Starknet client (Sepolia testnet)
- **Staking Service**: Connected to local Juno instance
- **Metrics**: Prometheus scraping from Juno and Staking
- **Logs**: Loki + Promtail for centralized log aggregation
- **Visualization**: Grafana with pre-configured dashboards
- **Persistent Storage**: All data persisted across restarts
- **Resource Management**: CPU and memory limits configured
- **Health Checks**: Liveness and readiness probes

## Prerequisites

- Kubernetes cluster (minikube, kind, or cloud provider)
- kubectl configured
- At least 800GB available storage for Juno data (400GB for Sepolia)

## Quick Start

### Testing with Limited Disk Space

If you have limited disk space (~55GB available), use the dev configuration:

```bash
# Create staking secret first
cp k8s/secrets/staking.yaml.example k8s/secrets/staking.yaml
vim k8s/secrets/staking.yaml  # Add your credentials

# Deploy with reduced storage (50Gi for Juno instead of 400Gi)
./scripts/apply-dev.sh
```

### Production Deployment

### 1. Create Staking Secret

**Important**: Before deploying, you must create the staking secret with your credentials:

```bash
# Copy the example file
cp k8s/secrets/staking.yaml.example k8s/secrets/staking.yaml

# Edit with your actual private keys
# Replace YOUR_PRIVATE_KEY_HERE and YOUR_OPERATIONAL_ADDRESS_HERE
vim k8s/secrets/staking.yaml
```

**Note**: The actual `k8s/secrets/staking.yaml` file is gitignored and should never be committed to version control.

### 2. Start Cluster and Deploy

```bash
# Start minikube (if using local cluster)
minikube start --cpus=8 --memory=16384 --disk-size=500g

# Deploy everything
./scripts/apply.sh

# Check status
kubectl get pods -n starknet
```

## Access Services

### Grafana Dashboard

```bash
kubectl -n starknet port-forward svc/grafana 3000:3000
```

Open <http://localhost:3000> (default login: admin/admin)

Grafana includes:

- **Prometheus datasource**: Metrics from Juno and Staking
- **Loki datasource**: Logs from all pods
- **Pre-configured dashboards**: Juno and Staking metrics

### Prometheus

```bash
kubectl -n starknet port-forward svc/prometheus 9090:9090
```

Open <http://localhost:9090>

### View Logs

Via kubectl:

```bash
# Juno logs
kubectl logs -n starknet deployment/juno -f

# Staking logs
kubectl logs -n starknet deployment/staking -f

# All logs in namespace
kubectl logs -n starknet --all-containers=true -f
```

Via Grafana:

1. Navigate to Explore in Grafana
2. Select Loki datasource
3. Use LogQL queries:
   - `{namespace="starknet", app="juno"}`
   - `{namespace="starknet", app="staking"}`
   - `{namespace="starknet"} |= "error"`

## Architecture

### Components

- **Juno**: Starknet node (4 CPU, 8Gi RAM, 400Gi storage)
- **Staking**: Staking service (2 CPU, 4Gi RAM)
- **Prometheus**: Metrics storage (1 CPU, 2Gi RAM, 20Gi storage)
- **Loki**: Log aggregation (1 CPU, 2Gi RAM, 20Gi storage)
- **Promtail**: Log collector (DaemonSet)
- **Grafana**: Visualization (1 CPU, 2Gi RAM, 2Gi storage)

### Network Configuration

- Juno RPC: `http://juno.starknet.svc.cluster.local:6060`
- Juno WebSocket: `ws://juno.starknet.svc.cluster.local:6061`
- Juno Metrics: `http://juno.starknet.svc.cluster.local:8080`
- Staking Metrics: `http://staking.starknet.svc.cluster.local:8081`

## Storage

All services use PersistentVolumeClaims:

```bash
kubectl get pvc -n starknet
```

**Note**: For mainnet, increase Juno storage to 800Gi in `k8s/pvcs/juno.yaml`

## Configuration

### Switching Networks (Mainnet/Sepolia)

Edit `k8s/deployments/juno.yaml`:

```yaml
args:
  - --network=mainnet # or sepolia
```

Update storage in `k8s/pvcs/juno.yaml`:

```yaml
storage: 800Gi # for mainnet
```

### Staking Credentials

Credentials are stored in Kubernetes Secret (`k8s/secrets/staking.yaml`).

**Security Best Practices**:

1. Never commit `k8s/secrets/staking.yaml` to Git (already in .gitignore)
2. Use the provided `k8s/secrets/staking.yaml.example` as template
3. Update with your actual private keys before deployment
4. Consider using external secret managers (Vault, AWS Secrets Manager) for production

**Example Secret Structure**:

```yaml
stringData:
  config.json: |
    {
      "signer": {
        "privateKey": "0xYOUR_PRIVATE_KEY_HERE",
        "operationalAddress": "0xYOUR_OPERATIONAL_ADDRESS_HERE"
      }
    }
```

## Documentation

For detailed documentation on architecture, troubleshooting, and advanced topics, see:

- **[END_USER_NODE_GUIDE.md](END_USER_NODE_GUIDE.md)**: Simple end-user deployment guide for Juno + metrics + logs
- **[INFRASTRUCTURE.md](INFRASTRUCTURE.md)**: Complete infrastructure guide with detailed explanations of all components

## Monitoring

### Prometheus Targets

- Juno metrics: `:8080/metrics`
- Staking metrics: `:8081/metrics`

### Log Retention

- Loki: 30 days (configurable in `k8s/configmaps/loki.yaml`)
- Prometheus: 30 days (configurable in `k8s/deployments/prometheus.yaml`)

## Cleanup

**Warning**: This deletes all PVCs and data. Backup if needed.

```bash
./scripts/delete.sh
```
