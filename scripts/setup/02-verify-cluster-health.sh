#!/bin/bash

# K3s Cluster Health Verification Script
# This script verifies k3s cluster health and node readiness

set -euo pipefail

# Set KUBECONFIG for k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Verifying K3s Cluster Health ==="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster info
echo "Checking cluster info..."
kubectl cluster-info

# Check node status
echo "Checking node status..."
kubectl get nodes -o wide

# Verify all nodes are ready
echo "Verifying all nodes are ready..."
NOT_READY_NODES=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l || true)
if [ "$NOT_READY_NODES" -gt 0 ]; then
    echo "ERROR: $NOT_READY_NODES node(s) are not ready"
    kubectl get nodes
    exit 1
fi
echo "✓ All nodes are ready"

# Check system pods
echo "Checking system pods status..."
kubectl get pods -n kube-system

# Verify critical system pods are running
echo "Verifying critical system pods..."
CRITICAL_PODS=("coredns" "local-path-provisioner" "metrics-server" "traefik")
for pod in "${CRITICAL_PODS[@]}"; do
    if kubectl get pods -n kube-system | grep -q "$pod.*Running"; then
        echo "✓ $pod is running"
    else
        echo "WARNING: $pod may not be running properly"
        kubectl get pods -n kube-system | grep "$pod" || echo "  $pod not found"
    fi
done

# Check cluster resources
echo "Checking cluster resource usage..."
kubectl top nodes 2>/dev/null || echo "Note: Metrics server may not be ready yet"

# Verify storage class
echo "Checking storage classes..."
kubectl get storageclass

# Check if local-path is the default storage class
if kubectl get storageclass | grep -q "local-path.*default"; then
    echo "✓ local-path storage class is set as default"
else
    echo "WARNING: local-path storage class may not be set as default"
fi

echo "✓ K3s cluster health verification completed"