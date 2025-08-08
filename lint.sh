#!/bin/bash
set -e

echo "Linting Helm chart..."
helm lint ./charts/media-server

echo "Building Kustomizations..."
echo "  ESO"
kustomize build ./clusters/media-server/external-secrets > /dev/null
echo "  intel-plugin"
kustomize build ./clusters/media-server/intel-plugin > /dev/null
echo "  flux-system "
kustomize build ./clusters/media-server/flux-system > /dev/null
echo "  media-server"
kustomize build ./clusters/media-server/media-server > /dev/null

echo "Validating manifests with kubectl dry-run..."
kubectl apply --dry-run=client -f ./clusters/media-server/flux-system
kubectl apply --dry-run=client -f ./clusters/media-server/media-server
kubectl apply --dry-run=client -f ./clusters/media-server/intel-plugin
kubectl apply --dry-run=client -f ./clusters/media-server/external-secrets

echo "All linting checks passed!"
