#!/bin/bash

# Main Cluster Setup Script
# This script orchestrates the complete cluster setup for the media server migration

set -euo pipefail

# Set KUBECONFIG for k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Media Server Cluster Setup ==="
echo "This script will set up the k3s cluster infrastructure for the media server migration"
echo

# Function to run a script and handle errors
run_script() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"
    
    echo "Running $script_name..."
    if [ -f "$script_path" ]; then
        chmod +x "$script_path"
        if "$script_path"; then
            echo "✓ $script_name completed successfully"
            echo
        else
            echo "✗ $script_name failed"
            exit 1
        fi
    else
        echo "ERROR: Script $script_path not found"
        exit 1
    fi
}

# Step 1: Verify cluster health first
run_script "02-verify-cluster-health.sh"

# Step 2: Create namespace and RBAC
run_script "03-create-namespace-rbac.sh"

# Step 3: Install Intel GPU device plugin
run_script "01-intel-gpu-device-plugin.sh"

echo "=== Final Verification ==="

# Final verification of all components
echo "Performing final verification of all components..."

# Check namespace
echo "Checking media-server namespace..."
kubectl get namespace media-server -o wide

# Check RBAC
echo "Checking RBAC resources..."
kubectl get serviceaccount,role,rolebinding -n media-server

# Check Intel GPU device plugin
echo "Checking Intel GPU device plugin..."
kubectl get pods -n default -l app=intel-gpu-plugin

# Check for GPU resources on nodes
echo "Checking for GPU resources..."
kubectl describe nodes | grep -A 3 "Allocatable:" | grep "gpu.intel.com" || echo "No Intel GPU resources found (normal if no Intel GPU present)"

# Summary
echo
echo "=== Setup Summary ==="
echo "✓ K3s cluster health verified"
echo "✓ media-server namespace created"
echo "✓ RBAC resources configured"
echo "✓ Intel GPU device plugin installed"
echo
echo "Cluster is ready for media server deployment!"
echo
echo "Next steps:"
echo "1. Install External Secrets Operator"
echo "2. Install FluxCD for GitOps"
echo "3. Deploy media server applications"