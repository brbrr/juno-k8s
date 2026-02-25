#!/bin/bash
set -e

echo "Creating namespace..."
kubectl apply -f k8s/namespace.yaml

echo "Creating RBAC resources..."
kubectl apply -f k8s/rbac.yaml

echo "Creating secrets..."
kubectl apply -f k8s/secrets/ --recursive

echo "Generating dynamic ConfigMaps..."
kubectl create configmap staking \
  --from-file=config.json=./configs/staking.json \
  -n starknet \
  --dry-run=client -o yaml >k8s/configmaps/staking.yaml

kubectl create configmap grafana-dashboards \
  --from-file=configs/juno_grafana.json \
  --from-file=configs/staking_grafana.json \
  -n starknet \
  -o yaml --dry-run=client >k8s/configmaps/grafana-dashboards.yaml

echo "Applying ConfigMaps..."
kubectl apply -f k8s/configmaps/ --recursive

echo "Creating PersistentVolumeClaims..."
kubectl apply -f k8s/pvcs/ --recursive

echo "Deploying services..."
kubectl apply -f k8s/services/ --recursive

echo "Deploying applications..."
kubectl apply -f k8s/deployments/ --recursive

echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=juno -n starknet --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=prometheus -n starknet --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=loki -n starknet --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=grafana -n starknet --timeout=120s || true

echo ""
echo "Deployment status:"
kubectl get pods -n starknet -o wide

echo ""
echo "Services:"
kubectl get svc -n starknet

echo ""
echo "PersistentVolumeClaims:"
kubectl get pvc -n starknet

echo ""
echo "========================================="
echo "Setup complete!"
echo "========================================="
echo ""
echo "Access Grafana dashboard:"
echo "  kubectl -n starknet port-forward svc/grafana 3000:3000"
echo "  URL: http://localhost:3000 (admin/admin)"
echo ""
echo "Access Prometheus:"
echo "  kubectl -n starknet port-forward svc/prometheus 9090:9090"
echo "  URL: http://localhost:9090"
echo ""
echo "View Juno logs:"
echo "  kubectl logs -n starknet deployment/juno -f"
echo ""
echo "View Staking logs:"
echo "  kubectl logs -n starknet deployment/staking -f"
echo ""
