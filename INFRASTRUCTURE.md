# Kubernetes Infrastructure Documentation

This document provides a comprehensive overview of the Kubernetes infrastructure for running Juno Starknet node with complete observability.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Components Deep Dive](#components-deep-dive)
3. [Observability Stack](#observability-stack)
4. [Storage Architecture](#storage-architecture)
5. [Resource Management](#resource-management)
6. [Security](#security)
7. [Networking](#networking)
8. [Deployment Process](#deployment-process)
9. [Monitoring & Alerting](#monitoring--alerting)
10. [Troubleshooting Guide](#troubleshooting-guide)

---

## Architecture Overview

The infrastructure consists of 6 main components organized in the `starknet` namespace:

```
┌─────────────────────────────────────────────────────────────┐
│                     Starknet Namespace                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────┐      ┌──────────┐      ┌──────────────┐      │
│  │   Juno   │─────▶│ Staking  │      │  Prometheus  │      │
│  │  Client  │      │ Service  │◀─────│   (Metrics)  │      │
│  └──────────┘      └──────────┘      └──────────────┘      │
│       │                 │                     │              │
│       │                 │                     ▼              │
│       │                 │              ┌──────────────┐     │
│       │                 │              │   Grafana    │     │
│       │                 │              │(Visualization)│     │
│       │                 │              └──────────────┘     │
│       │                 │                     ▲              │
│       ▼                 ▼                     │              │
│  ┌─────────────────────────────┐            │              │
│  │        Promtail             │            │              │
│  │   (Log Collector - DaemonSet)│────────▶  │              │
│  └─────────────────────────────┘            │              │
│                 │                             │              │
│                 ▼                             │              │
│          ┌──────────┐                        │              │
│          │   Loki   │────────────────────────┘              │
│          │  (Logs)  │                                        │
│          └──────────┘                                        │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Design Principles

1. **Self-Sufficient**: All metrics and logs are collected, stored, and visualized within the cluster
2. **Persistent**: All stateful services use PersistentVolumeClaims
3. **Observable**: Complete visibility into all components via metrics and logs
4. **Resilient**: Health probes ensure automatic recovery from failures
5. **Resource-Controlled**: CPU and memory limits prevent resource exhaustion

---

## Components Deep Dive

### 1. Juno (Starknet Client)

**Purpose**: Full Starknet node for Sepolia testnet

**Configuration**:
- **Image**: `nethermind/juno:v0.15.8`
- **Resources**: 2-4 CPU, 4-8Gi memory
- **Storage**: 400Gi PVC (sepolia) or 800Gi (mainnet)
- **Network**: Sepolia testnet
- **Ports**:
  - 6060: JSON-RPC API
  - 6061: WebSocket API
  - 8080: Prometheus metrics

**Key Features**:
- L1 verification disabled for faster sync
- CORS enabled for browser access
- Info-level logging (adjustable)
- Persistent blockchain data

**Health Checks**:
- Liveness: HTTP GET on port 6060 (every 30s after 60s)
- Readiness: HTTP GET on port 6060 (every 10s after 30s)

**Files**:
- Deployment: `k8s/deployments/juno.yaml`
- Service: `k8s/services/juno.yaml`
- PVC: `k8s/pvcs/juno.yaml`

---

### 2. Staking Service

**Purpose**: Starknet staking operations connected to local Juno

**Configuration**:
- **Image**: `staking:latest` (local build)
- **Resources**: 1-2 CPU, 2-4Gi memory
- **Storage**: None (stateless)
- **Connection**: Local Juno instance
- **Ports**:
  - 8081: Prometheus metrics

**Key Features**:
- Reads config from Kubernetes Secret
- Connects to local Juno via internal DNS
- Exposes Prometheus metrics
- No external dependencies

**Security**:
- Private keys stored in `staking-secret` Secret
- Secret mounted as read-only volume at `/config`
- Config file: `/config/config.json`

**Health Checks**:
- Liveness: HTTP GET on `/metrics` (every 30s after 30s)
- Readiness: HTTP GET on `/metrics` (every 10s after 10s)

**Files**:
- Deployment: `k8s/deployments/staking.yaml`
- Service: `k8s/services/staking.yaml`
- Secret: `k8s/secrets/staking.yaml` (create from example)

---

### 3. Prometheus (Metrics Collection)

**Purpose**: Time-series database for metrics

**Configuration**:
- **Image**: `prom/prometheus:v2.48.0`
- **Resources**: 0.5-1 CPU, 1-2Gi memory
- **Storage**: 20Gi PVC
- **Retention**: 30 days

**Scrape Targets**:
- Juno: `juno.starknet.svc.cluster.local:8080`
- Staking: `staking.starknet.svc.cluster.local:8081`

**Key Features**:
- 15-second scrape interval
- Persistent metrics storage
- Built-in query interface
- Service discovery via static configs

**Health Checks**:
- Liveness: HTTP GET on `/-/healthy` (every 30s after 30s)
- Readiness: HTTP GET on `/-/ready` (every 10s after 10s)

**Files**:
- Deployment: `k8s/deployments/prometheus.yaml`
- Service: `k8s/services/prometheus.yaml`
- ConfigMap: `k8s/configmaps/prometheus.yaml`
- PVC: `k8s/pvcs/prometheus.yaml`

---

### 4. Loki (Log Aggregation)

**Purpose**: Centralized log storage and querying

**Configuration**:
- **Image**: `grafana/loki:2.9.3`
- **Resources**: 0.5-1 CPU, 1-2Gi memory
- **Storage**: 20Gi PVC
- **Retention**: 30 days

**Key Features**:
- Filesystem-based storage (BoltDB + filesystem)
- No authentication required (internal only)
- Embedded cache for query performance
- Label-based log indexing

**Storage Layout**:
```
/loki/
├── chunks/     # Compressed log chunks
└── rules/      # Alerting rules (if configured)
```

**Health Checks**:
- Liveness: HTTP GET on `/ready` (every 30s after 45s)
- Readiness: HTTP GET on `/ready` (every 10s after 30s)

**Files**:
- Deployment: `k8s/deployments/loki.yaml`
- Service: `k8s/services/loki.yaml`
- ConfigMap: `k8s/configmaps/loki.yaml`
- PVC: `k8s/pvcs/loki.yaml`

---

### 5. Promtail (Log Collection)

**Purpose**: Scrapes logs from all pods and ships to Loki

**Configuration**:
- **Type**: DaemonSet (runs on every node)
- **Image**: `grafana/promtail:2.9.3`
- **Resources**: 100-200m CPU, 128-256Mi memory
- **Storage**: None (streams logs)

**Key Features**:
- Kubernetes service discovery
- Automatic pod/container labeling
- Reads from host log directories
- Pushes to Loki via HTTP

**Labels Applied**:
- `namespace`: Kubernetes namespace
- `pod`: Pod name
- `container`: Container name
- `job`: namespace/pod (for grouping)

**Permissions**:
- ServiceAccount: `promtail`
- ClusterRole: Read pods, nodes, services, endpoints
- Mounts: `/var/log` and `/var/lib/docker/containers` (read-only)

**Files**:
- DaemonSet: `k8s/deployments/promtail.yaml`
- ConfigMap: `k8s/configmaps/promtail.yaml`
- RBAC: `k8s/rbac.yaml`

---

### 6. Grafana (Visualization)

**Purpose**: Unified dashboard for metrics and logs

**Configuration**:
- **Image**: `grafana/grafana:10.2.2`
- **Resources**: 0.5-1 CPU, 1-2Gi memory
- **Storage**: 2Gi PVC
- **Default Login**: admin/admin

**Datasources**:
1. **Prometheus** (default)
   - URL: `http://prometheus:9090`
   - Used for metrics dashboards
   
2. **Loki**
   - URL: `http://loki:3100`
   - Used for log exploration

**Pre-configured Dashboards**:
- Juno metrics dashboard
- Staking metrics dashboard

**Key Features**:
- Persistent dashboard storage
- Auto-provisioned datasources
- Explore interface for ad-hoc queries
- Dashboard JSON import/export

**Health Checks**:
- Liveness: HTTP GET on `/api/health` (every 30s after 60s)
- Readiness: HTTP GET on `/api/health` (every 10s after 30s)

**Files**:
- Deployment: `k8s/deployments/grafana.yaml`
- Service: `k8s/services/grafana.yaml`
- ConfigMaps:
  - `k8s/configmaps/grafana-datasources.yaml`
  - `k8s/configmaps/grafana-dashboard-providers.yaml`
  - `k8s/configmaps/grafana-dashboards.yaml` (generated)
- PVC: `k8s/pvcs/grafana.yaml`

---

## Observability Stack

### Metrics Flow

```
┌──────────┐         ┌──────────────┐         ┌──────────┐
│   Juno   │────────▶│  Prometheus  │────────▶│ Grafana  │
│ :8080    │ scrape  │    :9090     │  query  │  :3000   │
└──────────┘         └──────────────┘         └──────────┘
                            ▲
┌──────────┐               │
│ Staking  │───────────────┘
│ :8081    │ scrape
└──────────┘
```

**What gets collected**:
- Juno: Block height, peer count, sync status, RPC metrics
- Staking: Validator status, transaction metrics, balance info

**Query Examples** (Prometheus):
```promql
# Juno block height
juno_block_height

# Staking transactions per second
rate(staking_transactions_total[5m])

# Memory usage
container_memory_usage_bytes{pod=~"juno.*"}
```

---

### Logs Flow

```
┌──────────────────┐         ┌────────┐         ┌──────────┐
│  All Pods Logs   │────────▶│  Loki  │────────▶│ Grafana  │
│  /var/log/pods/  │ push    │ :3100  │  query  │  :3000   │
└──────────────────┘         └────────┘         └──────────┘
         ▲
         │ reads
    ┌────────────┐
    │  Promtail  │
    │ DaemonSet  │
    └────────────┘
```

**What gets collected**:
- All stdout/stderr from all containers
- Kubernetes metadata (namespace, pod, container)
- Timestamps and log levels

**Query Examples** (LogQL in Grafana):
```logql
# All logs in starknet namespace
{namespace="starknet"}

# Juno errors only
{namespace="starknet", app="juno"} |= "error"

# Staking logs from last hour
{namespace="starknet", app="staking"} [1h]

# Pattern extraction
{namespace="starknet"} | json | level="error"
```

---

## Storage Architecture

### PersistentVolumeClaims

| Service | Size | Purpose | Retention |
|---------|------|---------|-----------|
| Juno | 400Gi (Sepolia)<br/>800Gi (Mainnet) | Blockchain data | Permanent |
| Prometheus | 20Gi | Metrics TSDB | 30 days |
| Loki | 20Gi | Log chunks | 30 days |
| Grafana | 2Gi | Dashboards, users | Permanent |

### Storage Classes

By default, PVCs use the cluster's default StorageClass. For production:

**Local Development (Minikube)**:
```yaml
storageClassName: standard
```

**Cloud Providers**:
- AWS: `gp3` or `io2` for Juno (high IOPS)
- GCP: `pd-ssd` for Juno
- Azure: `managed-premium` for Juno

### Backup Strategy

**Critical Data**:
1. **Juno blockchain data** (`juno-data` PVC)
   - Can be re-synced from network (time-consuming)
   - Backup recommended for faster recovery

2. **Grafana dashboards** (`grafana-data` PVC)
   - Contains custom dashboards and settings
   - Export dashboards via Grafana UI regularly

**Non-Critical Data**:
- Prometheus metrics (30-day retention, historical only)
- Loki logs (30-day retention, historical only)

---

## Resource Management

### CPU and Memory Allocation

| Component | Request | Limit | Ratio |
|-----------|---------|-------|-------|
| Juno | 2 CPU, 4Gi | 4 CPU, 8Gi | 2x |
| Staking | 1 CPU, 2Gi | 2 CPU, 4Gi | 2x |
| Prometheus | 0.5 CPU, 1Gi | 1 CPU, 2Gi | 2x |
| Loki | 0.5 CPU, 1Gi | 1 CPU, 2Gi | 2x |
| Grafana | 0.5 CPU, 1Gi | 1 CPU, 2Gi | 2x |
| Promtail | 0.1 CPU, 128Mi | 0.2 CPU, 256Mi | 2x |

**Total Cluster Requirements**:
- **CPU**: 4.6 (requests) - 9.2 (limits) cores
- **Memory**: 9.1Gi (requests) - 18.3Gi (limits)
- **Storage**: 442Gi (Sepolia) or 842Gi (Mainnet)

### Kubernetes QoS Classes

All pods use **Burstable** QoS class:
- Requests < Limits
- Allows bursting for peak loads
- Better resource utilization

### Scaling Considerations

**Current Setup** (Single Replica):
- Suitable for development and testing
- Single point of failure for each component

**Production Recommendations**:
1. **Juno**: Keep at 1 replica (stateful, blockchain sync)
2. **Staking**: Can scale to 2-3 replicas if needed
3. **Prometheus**: Consider HA setup with Thanos for multi-cluster
4. **Loki**: Can scale with distributed mode (needs configuration change)
5. **Grafana**: Can scale to 2-3 replicas for HA

---

## Security

### Secrets Management

**Staking Private Keys**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: staking-secret
  namespace: starknet
type: Opaque
stringData:
  config.json: |
    {
      "signer": {
        "privateKey": "0x...",
        "operationalAddress": "0x..."
      }
    }
```

**Best Practices**:
1. Never commit real secrets to Git
2. Use `k8s/secrets/staking.yaml.example` as template
3. Create actual secret before deployment
4. Consider using external secret managers (Vault, AWS Secrets Manager)

### RBAC (Role-Based Access Control)

**Promtail ServiceAccount**:
- **ClusterRole**: `promtail`
- **Permissions**: Read-only access to pods, nodes, services, endpoints
- **Purpose**: Kubernetes service discovery for log collection

**Namespace Isolation**:
- All resources in `starknet` namespace
- No cross-namespace access required
- Can be further restricted with NetworkPolicies

### Network Security

**Current State**:
- All services use ClusterIP (internal only)
- No external ingress configured
- Access via `kubectl port-forward` only

**Production Recommendations**:
1. Add NetworkPolicies to restrict pod-to-pod communication
2. Use Ingress with TLS for external access
3. Enable Grafana authentication (LDAP, OAuth)
4. Restrict Prometheus/Loki to read-only for Grafana

---

## Networking

### Service DNS Resolution

All services are accessible via internal DNS:

| Service | DNS Name | Ports |
|---------|----------|-------|
| Juno | `juno.starknet.svc.cluster.local` | 6060 (RPC), 6061 (WS), 8080 (metrics) |
| Staking | `staking.starknet.svc.cluster.local` | 8081 (metrics) |
| Prometheus | `prometheus.starknet.svc.cluster.local` | 9090 |
| Loki | `loki.starknet.svc.cluster.local` | 3100 |
| Grafana | `grafana.starknet.svc.cluster.local` | 3000 |

### Service Types

- **Juno, Staking, Prometheus, Loki**: ClusterIP (internal only)
- **Grafana**: NodePort (port 32000) - for easier local access

### External Access

**Development** (kubectl port-forward):
```bash
kubectl -n starknet port-forward svc/grafana 3000:3000
kubectl -n starknet port-forward svc/juno 6060:6060
```

**Production** (Ingress example):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: starknet
spec:
  rules:
    - host: grafana.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
```

---

## Deployment Process

### Prerequisites

1. Kubernetes cluster (minikube, kind, or cloud)
2. kubectl configured
3. Sufficient storage (500GB+ for Sepolia)
4. Staking secret created from example

### Step-by-Step Deployment

1. **Create staking secret**:
   ```bash
   cp k8s/secrets/staking.yaml.example k8s/secrets/staking.yaml
   # Edit with your private keys
   ```

2. **Run deployment script**:
   ```bash
   ./scripts/apply.sh
   ```

3. **Script execution flow**:
   ```
   ✓ Create namespace (starknet)
   ✓ Create RBAC (promtail ServiceAccount + ClusterRole)
   ✓ Create secrets (staking-secret)
   ✓ Generate dynamic ConfigMaps (staking, grafana-dashboards)
   ✓ Apply static ConfigMaps (prometheus, loki, promtail, grafana)
   ✓ Create PVCs (juno, prometheus, loki, grafana)
   ✓ Create services (juno, staking, prometheus, loki, grafana)
   ✓ Create deployments (juno, staking, prometheus, loki, grafana, promtail)
   ✓ Wait for pods to be ready
   ```

4. **Verify deployment**:
   ```bash
   kubectl get pods -n starknet
   kubectl get pvc -n starknet
   kubectl get svc -n starknet
   ```

### Deployment Order (Important)

The order matters to avoid dependency issues:
1. Namespace → RBAC → Secrets
2. ConfigMaps → PVCs
3. Services → Deployments

---

## Monitoring & Alerting

### Health Monitoring

**Via Kubernetes**:
```bash
# Pod health
kubectl get pods -n starknet

# Pod details and events
kubectl describe pod -n starknet <pod-name>

# Resource usage
kubectl top pods -n starknet
```

**Via Grafana**:
- Navigate to Explore → Prometheus
- Query: `up{namespace="starknet"}`
- All services should show `1` (up)

### Key Metrics to Monitor

**Juno**:
- Block height (sync progress)
- Peer count (network connectivity)
- RPC request rate
- Memory usage

**Staking**:
- Transaction success rate
- Validator balance
- Error rate

**Infrastructure**:
- CPU/Memory usage per pod
- Disk usage on PVCs
- Network traffic

### Alerting (Future Enhancement)

Consider adding Alertmanager for:
- Juno sync lag > 100 blocks
- Pod restarts > 5 in 1 hour
- Disk usage > 80%
- High error rates in logs

---

## Troubleshooting Guide

### Common Issues

#### 1. Pods Not Starting

**Symptoms**:
```bash
kubectl get pods -n starknet
# Shows: CrashLoopBackOff, ImagePullBackOff, Pending
```

**Diagnosis**:
```bash
kubectl describe pod -n starknet <pod-name>
kubectl logs -n starknet <pod-name>
```

**Common Causes**:
- PVC pending (insufficient storage)
- Image pull failure (network/auth issue)
- Config errors (check ConfigMaps/Secrets)
- Resource constraints (insufficient CPU/memory)

---

#### 2. Juno Not Syncing

**Symptoms**:
- Block height not increasing
- Logs show sync errors

**Diagnosis**:
```bash
kubectl logs -n starknet deployment/juno | grep -i sync
```

**Solutions**:
- Check network connectivity
- Verify Sepolia network is accessible
- Increase CPU/memory if resource-constrained
- Check disk space on PVC

---

#### 3. Prometheus Not Scraping

**Symptoms**:
- No metrics in Grafana
- Targets down in Prometheus UI

**Diagnosis**:
```bash
kubectl -n starknet port-forward svc/prometheus 9090:9090
# Visit http://localhost:9090/targets
```

**Solutions**:
- Verify service endpoints exist
- Check prometheus ConfigMap syntax
- Ensure pods are healthy and ready
- Check network policies (if any)

---

#### 4. Loki Not Receiving Logs

**Symptoms**:
- No logs in Grafana Explore
- Promtail logs show errors

**Diagnosis**:
```bash
kubectl logs -n starknet daemonset/promtail
kubectl logs -n starknet deployment/loki
```

**Solutions**:
- Verify Promtail has RBAC permissions
- Check Loki service is accessible
- Ensure log paths are correct
- Verify Promtail is running on all nodes

---

#### 5. Staking Service Failing

**Symptoms**:
- Staking pod in CrashLoopBackOff
- Connection errors in logs

**Diagnosis**:
```bash
kubectl logs -n starknet deployment/staking
```

**Common Causes**:
- Secret not created (missing staking-secret)
- Invalid config.json format
- Juno not ready yet (wait for Juno to sync)
- Network connection issues

**Solutions**:
```bash
# Verify secret exists
kubectl get secret -n starknet staking-secret

# Verify Juno is ready
kubectl get pods -n starknet -l app=juno

# Test Juno connectivity
kubectl -n starknet exec deployment/staking -- curl http://juno:6060
```

---

#### 6. Grafana Dashboards Not Loading

**Symptoms**:
- Empty dashboard list
- Datasources not working

**Diagnosis**:
```bash
kubectl logs -n starknet deployment/grafana
kubectl get configmap -n starknet | grep grafana
```

**Solutions**:
- Verify ConfigMaps are created
- Check datasource URLs are correct
- Ensure Prometheus/Loki are accessible
- Restart Grafana pod to reload configs

---

### Debugging Commands

```bash
# Get all resources in namespace
kubectl get all -n starknet

# Watch pod status in real-time
kubectl get pods -n starknet -w

# Get pod logs with timestamps
kubectl logs -n starknet <pod-name> --timestamps=true

# Get previous logs (after restart)
kubectl logs -n starknet <pod-name> --previous

# Execute command in pod
kubectl exec -it -n starknet <pod-name> -- /bin/sh

# Check resource usage
kubectl top pods -n starknet
kubectl top nodes

# Get events (sorted by time)
kubectl get events -n starknet --sort-by='.lastTimestamp'

# Describe all pods
kubectl describe pods -n starknet

# Port-forward multiple services
kubectl -n starknet port-forward svc/grafana 3000:3000 &
kubectl -n starknet port-forward svc/prometheus 9090:9090 &
kubectl -n starknet port-forward svc/juno 6060:6060 &
```

---

### Performance Tuning

#### Juno Performance

**Slow Sync**:
```yaml
# Increase resources in juno deployment
resources:
  limits:
    cpu: "8000m"      # Up from 4000m
    memory: "16Gi"    # Up from 8Gi
```

**High Memory Usage**:
```yaml
# Add memory limits to args
args:
  - --db-max-handles=512  # Reduce open file handles
```

---

#### Prometheus Performance

**High Cardinality**:
```yaml
# Reduce retention in prometheus deployment
args:
  - "--storage.tsdb.retention.time=15d"  # Down from 30d
```

**Slow Queries**:
- Use recording rules for frequently-used queries
- Reduce scrape interval to 30s (from 15s)

---

#### Loki Performance

**Ingestion Rate Limits**:
```yaml
# Increase in loki configmap
limits_config:
  ingestion_rate_mb: 20      # Up from 10
  ingestion_burst_size_mb: 40 # Up from 20
```

---

### Recovery Procedures

#### Complete Cluster Reset

```bash
# Delete everything
./scripts/delete.sh

# Wait for namespace deletion
kubectl get namespace starknet -w

# Redeploy
./scripts/apply.sh
```

#### Reset Juno (Re-sync from Genesis)

```bash
# Delete Juno pod and PVC
kubectl delete pod -n starknet -l app=juno
kubectl delete pvc -n starknet juno-data

# Redeploy (will create new PVC)
kubectl apply -f k8s/pvcs/juno.yaml
kubectl apply -f k8s/deployments/juno.yaml
```

#### Restore from Backup

```bash
# Example: Restore Juno data from snapshot
kubectl delete pod -n starknet -l app=juno

# Copy data to PVC (requires helper pod)
kubectl run -n starknet pvc-restore --image=busybox \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"juno-data"}}],"containers":[{"name":"restore","image":"busybox","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}]}}'

# Copy backup data
kubectl cp -n starknet backup-data.tar.gz pvc-restore:/data/

# Extract and cleanup
kubectl exec -n starknet pvc-restore -- tar -xzf /data/backup-data.tar.gz -C /data
kubectl delete pod -n starknet pvc-restore

# Start Juno
kubectl apply -f k8s/deployments/juno.yaml
```

---

## Advanced Topics

### High Availability Setup

For production, consider:

1. **Multi-replica Grafana**:
   ```yaml
   spec:
     replicas: 2
   ```

2. **Prometheus HA** with Thanos:
   - Deploy Thanos sidecar with Prometheus
   - Use remote storage (S3, GCS)
   - Query via Thanos Query

3. **Loki Distributed Mode**:
   - Split into read/write paths
   - Use object storage (S3, GCS)
   - Scale independently

### Multi-Cluster Monitoring

For monitoring multiple Juno instances:

1. **Centralized Prometheus**:
   - Use Prometheus federation
   - Or use Thanos Query across clusters

2. **Centralized Loki**:
   - Configure Promtail to push to remote Loki
   - Use Grafana to query multiple Loki instances

### Automated Backups

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: juno-backup
  namespace: starknet
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: backup-tool:latest
            volumeMounts:
            - name: juno-data
              mountPath: /data
          volumes:
          - name: juno-data
            persistentVolumeClaim:
              claimName: juno-data
```

---

## Maintenance Tasks

### Regular Tasks

**Daily**:
- Check pod health: `kubectl get pods -n starknet`
- Verify Juno sync progress
- Review error logs in Grafana

**Weekly**:
- Check disk usage: `kubectl get pvc -n starknet`
- Review Grafana dashboards for anomalies
- Check for new Juno releases

**Monthly**:
- Backup Grafana dashboards
- Review and cleanup old logs (if needed)
- Update container images to latest stable versions

### Upgrade Procedure

**Example: Upgrading Juno**

1. Check release notes for breaking changes
2. Update image tag in `k8s/deployments/juno.yaml`
3. Apply change:
   ```bash
   kubectl apply -f k8s/deployments/juno.yaml
   ```
4. Monitor rollout:
   ```bash
   kubectl rollout status deployment/juno -n starknet
   ```
5. Verify sync continues:
   ```bash
   kubectl logs -n starknet deployment/juno -f
   ```

**Rollback if needed**:
```bash
kubectl rollout undo deployment/juno -n starknet
```

---

## Appendix

### Useful kubectl Commands Cheat Sheet

```bash
# Namespace operations
kubectl create namespace starknet
kubectl delete namespace starknet

# Apply resources
kubectl apply -f <file.yaml>
kubectl apply -f <directory> --recursive

# Get resources
kubectl get all -n starknet
kubectl get pods -n starknet -o wide
kubectl get pvc -n starknet
kubectl get configmaps -n starknet

# Describe resources
kubectl describe pod <pod-name> -n starknet
kubectl describe pvc <pvc-name> -n starknet

# Logs
kubectl logs <pod-name> -n starknet
kubectl logs <pod-name> -n starknet -f
kubectl logs <pod-name> -n starknet --previous

# Execute commands
kubectl exec -it <pod-name> -n starknet -- /bin/sh
kubectl exec <pod-name> -n starknet -- curl http://juno:6060

# Port forwarding
kubectl port-forward -n starknet svc/grafana 3000:3000
kubectl port-forward -n starknet pod/<pod-name> 8080:8080

# Resource usage
kubectl top pods -n starknet
kubectl top nodes

# Scaling
kubectl scale deployment/grafana -n starknet --replicas=2

# Rollout management
kubectl rollout status deployment/juno -n starknet
kubectl rollout history deployment/juno -n starknet
kubectl rollout undo deployment/juno -n starknet

# Delete resources
kubectl delete pod <pod-name> -n starknet
kubectl delete deployment <name> -n starknet
kubectl delete -f <file.yaml>
```

### Environment Variables Reference

| Service | Variable | Purpose | Default |
|---------|----------|---------|---------|
| Grafana | `GF_SECURITY_ADMIN_PASSWORD` | Admin password | `admin` |
| Grafana | `GF_INSTALL_PLUGINS` | Additional plugins | `""` |
| Promtail | `HOSTNAME` | Node name | From K8s |

### Resource Files Index

```
k8s/
├── namespace.yaml                              # Starknet namespace
├── rbac.yaml                                   # Promtail RBAC
├── configmaps/
│   ├── grafana-dashboard-providers.yaml        # Grafana dashboard provisioning
│   ├── grafana-dashboards.yaml                 # Generated dashboard JSON
│   ├── grafana-datasources.yaml                # Prometheus + Loki datasources
│   ├── loki.yaml                               # Loki configuration
│   ├── prometheus.yaml                         # Prometheus scrape config
│   ├── promtail.yaml                           # Promtail scrape config
│   └── staking.yaml                            # Generated staking config
├── secrets/
│   ├── staking.yaml.example                    # Staking credentials template
│   └── staking.yaml                            # Actual secrets (not in Git)
├── pvcs/
│   ├── juno.yaml                               # Juno blockchain data (400Gi)
│   ├── prometheus.yaml                         # Prometheus metrics (20Gi)
│   ├── loki.yaml                               # Loki logs (20Gi)
│   └── grafana.yaml                            # Grafana storage (2Gi)
├── deployments/
│   ├── juno.yaml                               # Juno Starknet client
│   ├── staking.yaml                            # Staking service
│   ├── prometheus.yaml                         # Prometheus deployment
│   ├── loki.yaml                               # Loki deployment
│   ├── grafana.yaml                            # Grafana deployment
│   └── promtail.yaml                           # Promtail DaemonSet
└── services/
    ├── juno.yaml                               # Juno service (RPC, WS, metrics)
    ├── staking.yaml                            # Staking metrics service
    ├── prometheus.yaml                         # Prometheus service
    ├── loki.yaml                               # Loki service
    └── grafana.yaml                            # Grafana service (NodePort)
```

---

## Conclusion

This infrastructure provides a production-ready, self-sufficient Kubernetes setup for running Juno Starknet node with complete observability. All metrics and logs are collected, stored, and visualized within the cluster without external dependencies.

For questions or issues, refer to the troubleshooting section or check the logs using Grafana's Loki datasource.
