#!/bin/bash
set -e

echo "Deleting deployments..."
kubectl delete -f k8s/deployments/ --ignore-not-found --recursive

echo "Deleting services..."
kubectl delete -f k8s/services/ --ignore-not-found --recursive

echo "Deleting configmaps..."
kubectl delete -f k8s/configmaps/ --ignore-not-found --recursive

echo "Deleting secrets..."
kubectl delete -f k8s/secrets/ --ignore-not-found --recursive

echo "Deleting PVCs..."
kubectl delete -f k8s/pvcs/ --ignore-not-found --recursive

echo "Deleting RBAC resources..."
kubectl delete -f k8s/rbac.yaml --ignore-not-found

echo "Deleting namespace..."
kubectl delete -f k8s/namespace.yaml --ignore-not-found

echo "Cleanup complete!"
