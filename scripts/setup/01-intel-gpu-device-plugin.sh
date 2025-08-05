#!/bin/bash

# Intel GPU Device Plugin Installation Script
# This script installs the Intel GPU device plugin for hardware acceleration support

set -euo pipefail

# Set KUBECONFIG for k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Installing Intel GPU Device Plugin ==="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✓ Kubernetes cluster is accessible"

# Apply Intel GPU Device Plugin using the correct manifest
echo "Installing Intel GPU Device Plugin..."
kubectl apply -k https://github.com/intel/intel-device-plugins-for-kubernetes/deployments/gpu_plugin?ref=main

# Wait for the device plugin to be ready
echo "Waiting for Intel GPU Device Plugin to be ready..."
kubectl wait --for=condition=ready pod -l app=intel-gpu-plugin -n default --timeout=300s

# Verify the device plugin is running
echo "Verifying Intel GPU Device Plugin status..."
kubectl get pods -n default -l app=intel-gpu-plugin

# Check if GPU resources are available on nodes
echo "Checking for GPU resources on nodes..."
kubectl describe nodes | grep -A 5 "gpu.intel.com" || echo "No Intel GPU resources found yet (this may be normal if no Intel GPU is present)"

echo "✓ Intel GPU Device Plugin installation completed successfully"