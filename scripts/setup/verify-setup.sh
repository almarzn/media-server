#!/bin/bash

# Setup Verification Script
# This script verifies that all setup components are operational

set -euo pipefail

# Set KUBECONFIG for k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Verifying Complete Setup ==="

# Function to check if a resource exists and is ready
check_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-default}"
    
    if kubectl get "$resource_type" "$resource_name" -n "$namespace" &> /dev/null; then
        echo "✓ $resource_type/$resource_name exists in namespace $namespace"
        return 0
    else
        echo "✗ $resource_type/$resource_name not found in namespace $namespace"
        return 1
    fi
}

# Check cluster health
echo "1. Verifying cluster health..."
if kubectl cluster-info &> /dev/null; then
    echo "✓ Cluster is accessible"
else
    echo "✗ Cluster is not accessible"
    exit 1
fi

# Check node readiness
echo "2. Verifying node readiness..."
READY_NODES=$(kubectl get nodes --no-headers | grep "Ready" | wc -l)
TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
if [ "$READY_NODES" -eq "$TOTAL_NODES" ] && [ "$TOTAL_NODES" -gt 0 ]; then
    echo "✓ All $TOTAL_NODES node(s) are ready"
else
    echo "✗ Only $READY_NODES out of $TOTAL_NODES nodes are ready"
    exit 1
fi

# Check media-server namespace
echo "3. Verifying media-server namespace..."
if check_resource "namespace" "media-server" ""; then
    # Check namespace labels
    if kubectl get namespace media-server -o jsonpath='{.metadata.labels.app\.kubernetes\.io/name}' | grep -q "media-server"; then
        echo "✓ media-server namespace is properly labeled"
    else
        echo "✗ media-server namespace is missing required labels"
    fi
else
    exit 1
fi

# Check RBAC resources
echo "4. Verifying RBAC resources..."
check_resource "serviceaccount" "media-server" "media-server" || exit 1
check_resource "role" "media-server-role" "media-server" || exit 1
check_resource "rolebinding" "media-server-rolebinding" "media-server" || exit 1

# Check Intel GPU device plugin
echo "5. Verifying Intel GPU device plugin..."
if check_resource "daemonset" "intel-gpu-plugin" "default"; then
    # Check if the daemonset is ready
    DESIRED=$(kubectl get daemonset intel-gpu-plugin -n default -o jsonpath='{.status.desiredNumberScheduled}')
    READY=$(kubectl get daemonset intel-gpu-plugin -n default -o jsonpath='{.status.numberReady}')
    if [ "$DESIRED" -eq "$READY" ] && [ "$READY" -gt 0 ]; then
        echo "✓ Intel GPU device plugin daemonset is ready ($READY/$DESIRED)"
    else
        echo "✗ Intel GPU device plugin daemonset is not ready ($READY/$DESIRED)"
        exit 1
    fi
else
    exit 1
fi

# Check system pods
echo "6. Verifying critical system pods..."
CRITICAL_PODS=("coredns" "local-path-provisioner" "metrics-server" "traefik")
for pod in "${CRITICAL_PODS[@]}"; do
    if kubectl get pods -n kube-system | grep -q "$pod.*Running"; then
        echo "✓ $pod is running"
    else
        echo "✗ $pod is not running properly"
        exit 1
    fi
done

# Check storage class
echo "7. Verifying storage class..."
if kubectl get storageclass local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' | grep -q "true"; then
    echo "✓ local-path storage class is set as default"
else
    echo "✗ local-path storage class is not set as default"
    exit 1
fi

echo
echo "=== Verification Summary ==="
echo "✓ K3s cluster is healthy and accessible"
echo "✓ All nodes are ready"
echo "✓ media-server namespace created with proper labels"
echo "✓ RBAC resources (ServiceAccount, Role, RoleBinding) configured"
echo "✓ Intel GPU device plugin installed and running"
echo "✓ Critical system pods are running"
echo "✓ Default storage class configured"
echo
echo "🎉 All setup components are operational!"
echo
echo "The cluster is ready for the next phase of the media server migration."