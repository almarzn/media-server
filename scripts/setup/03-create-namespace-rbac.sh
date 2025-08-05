#!/bin/bash

# Media Server Namespace and RBAC Setup Script
# This script creates the media-server namespace and required RBAC

set -euo pipefail

# Set KUBECONFIG for k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Creating Media Server Namespace and RBAC ==="

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

# Create media-server namespace
echo "Creating media-server namespace..."
kubectl create namespace media-server --dry-run=client -o yaml | kubectl apply -f -

# Verify namespace was created
if kubectl get namespace media-server &> /dev/null; then
    echo "✓ media-server namespace created successfully"
else
    echo "ERROR: Failed to create media-server namespace"
    exit 1
fi

# Create service account for media server applications
echo "Creating service account..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: media-server
  namespace: media-server
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: media-server
  name: media-server-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: media-server-rolebinding
  namespace: media-server
subjects:
- kind: ServiceAccount
  name: media-server
  namespace: media-server
roleRef:
  kind: Role
  name: media-server-role
  apiGroup: rbac.authorization.k8s.io
EOF

# Verify RBAC resources were created
echo "Verifying RBAC resources..."
kubectl get serviceaccount media-server -n media-server
kubectl get role media-server-role -n media-server
kubectl get rolebinding media-server-rolebinding -n media-server

echo "✓ Service account and RBAC created successfully"

# Label the namespace for easier management
echo "Labeling namespace..."
kubectl label namespace media-server app.kubernetes.io/name=media-server --overwrite

# Show namespace details
echo "Namespace details:"
kubectl describe namespace media-server

echo "✓ Media server namespace and RBAC setup completed successfully"