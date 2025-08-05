#!/bin/bash

# FluxCD Installation and GitOps Setup Script
# This script installs FluxCD controllers and sets up GitOps infrastructure

set -euo pipefail

# Set KUBECONFIG for k3s
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo "=== Installing FluxCD and Setting up GitOps Infrastructure ==="

# Configuration variables
FLUX_NAMESPACE="flux-system"
GIT_REPO_URL="${GIT_REPO_URL:-}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_PATH="${GIT_PATH:-clusters/production}"
GIT_TOKEN="${GIT_TOKEN:-}"

# Function to check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
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
    
    # Check if flux CLI is available, if not install it
    if ! command -v flux &> /dev/null; then
        echo "Installing Flux CLI..."
        curl -s https://fluxcd.io/install.sh | sudo bash
        
        # Verify installation
        if ! command -v flux &> /dev/null; then
            echo "ERROR: Failed to install Flux CLI"
            exit 1
        fi
    fi
    
    echo "✓ Prerequisites check completed"
}

# Function to install FluxCD controllers
install_flux_controllers() {
    echo "Installing FluxCD controllers..."
    
    # Check if FluxCD is already installed
    if kubectl get namespace "$FLUX_NAMESPACE" &> /dev/null; then
        echo "FluxCD namespace already exists, checking installation..."
        if flux check --pre; then
            echo "✓ FluxCD is already installed and healthy"
            return 0
        else
            echo "FluxCD installation appears incomplete, reinstalling..."
            kubectl delete namespace "$FLUX_NAMESPACE" --ignore-not-found=true
            sleep 10
        fi
    fi
    
    # Install FluxCD controllers
    flux install --namespace="$FLUX_NAMESPACE"
    
    # Wait for controllers to be ready
    echo "Waiting for FluxCD controllers to be ready..."
    kubectl wait --for=condition=available deployment --all -n "$FLUX_NAMESPACE" --timeout=300s
    
    # Verify installation
    flux check
    
    echo "✓ FluxCD controllers installed successfully"
}

# Function to create Git repository structure
create_git_repo_structure() {
    echo "Creating Git repository structure in current repository..."
    
    # Create directory structure for GitOps
    mkdir -p clusters/production/{infrastructure,apps}
    mkdir -p infrastructure/{external-secrets,intel-device-plugin}
    mkdir -p apps/media-server
    
    echo "✓ Git repository structure created"
    echo "Note: Helm charts and manifests should be created as separate files in the repository"
}

# Function to bootstrap Git repository (if URL provided)
bootstrap_git_repository() {
    if [ -z "$GIT_REPO_URL" ]; then
        echo "No Git repository URL provided, skipping Git bootstrap"
        echo "To bootstrap with a Git repository later, run:"
        echo "flux bootstrap git --url=<your-repo-url> --branch=$GIT_BRANCH --path=$GIT_PATH"
        return 0
    fi
    
    echo "Bootstrapping Git repository: $GIT_REPO_URL"
    
    # Check if Git token is provided
    if [ -z "$GIT_TOKEN" ]; then
        echo "WARNING: No Git token provided. You may need to authenticate manually."
    else
        export GITHUB_TOKEN="$GIT_TOKEN"
    fi
    
    # Bootstrap FluxCD with Git repository
    flux bootstrap git \
        --url="$GIT_REPO_URL" \
        --branch="$GIT_BRANCH" \
        --path="$GIT_PATH" \
        --namespace="$FLUX_NAMESPACE"
    
    echo "✓ Git repository bootstrapped successfully"
}

# Function to set up image update automation
setup_image_automation() {
    echo "Setting up image update automation..."
    
    # Install image automation controllers
    echo "Installing image automation controllers..."
    flux install --components-extra=image-reflector-controller,image-automation-controller
    
    # Wait for image automation controllers to be ready
    echo "Waiting for image automation controllers to be ready..."
    kubectl wait --for=condition=available deployment -l app.kubernetes.io/component=image-reflector-controller -n "$FLUX_NAMESPACE" --timeout=300s
    kubectl wait --for=condition=available deployment -l app.kubernetes.io/component=image-automation-controller -n "$FLUX_NAMESPACE" --timeout=300s
    
    # Create image update automation resources
    cat > /tmp/image-automation.yaml << 'EOF'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: plex
  namespace: flux-system
spec:
  image: ghcr.io/onedr0p/plex
  interval: 1h
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: sonarr
  namespace: flux-system
spec:
  image: ghcr.io/onedr0p/sonarr
  interval: 1h
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: radarr
  namespace: flux-system
spec:
  image: ghcr.io/onedr0p/radarr
  interval: 1h
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: prowlarr
  namespace: flux-system
spec:
  image: ghcr.io/linuxserver/prowlarr
  interval: 1h
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: qbittorrent
  namespace: flux-system
spec:
  image: ghcr.io/onedr0p/qbittorrent
  interval: 1h
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: postgresql
  namespace: flux-system
spec:
  image: postgres
  interval: 1h
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: protonvpn
  namespace: flux-system
spec:
  image: ghcr.io/tprasadtp/protonwire
  interval: 1h
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: configarr
  namespace: flux-system
spec:
  image: ghcr.io/raydak-labs/configarr
  interval: 1h
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: flaresolverr
  namespace: flux-system
spec:
  image: ghcr.io/flaresolverr/flaresolverr
  interval: 1h
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: byparr
  namespace: flux-system
spec:
  image: ghcr.io/thephaseless/byparr
  interval: 1h
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: samba
  namespace: flux-system
spec:
  image: quay.io/samba.org/samba-server
  interval: 1h
EOF
    
    # Apply image repositories
    kubectl apply -f /tmp/image-automation.yaml
    
    # Create image policies
    cat > /tmp/image-policies.yaml << 'EOF'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: plex
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: plex
  policy:
    semver:
      range: '>=1.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: sonarr
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: sonarr
  policy:
    semver:
      range: '>=4.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: radarr
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: radarr
  policy:
    semver:
      range: '>=5.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: prowlarr
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: prowlarr
  policy:
    semver:
      range: '>=1.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: qbittorrent
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: qbittorrent
  policy:
    semver:
      range: '>=5.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: postgresql
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: postgresql
  policy:
    semver:
      range: '>=16.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: protonvpn
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: protonvpn
  policy:
    semver:
      range: '>=7.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: configarr
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: configarr
  policy:
    alphabetical:
      order: asc
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: flaresolverr
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: flaresolverr
  policy:
    semver:
      range: '>=3.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: byparr
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: byparr
  policy:
    semver:
      range: '>=1.0.0'
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: samba
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: samba
  policy:
    alphabetical:
      order: asc
EOF
    
    # Apply image policies
    kubectl apply -f /tmp/image-policies.yaml
    
    # Clean up temporary files
    rm -f /tmp/image-automation.yaml /tmp/image-policies.yaml
    
    echo "✓ Image update automation configured"
}

# Function to verify GitOps functionality
verify_gitops_functionality() {
    echo "Verifying GitOps functionality..."
    
    # Check FluxCD status
    echo "Checking FluxCD status..."
    flux check
    
    # List FluxCD resources
    echo "FluxCD controllers:"
    kubectl get pods -n "$FLUX_NAMESPACE"
    
    echo "Image repositories:"
    kubectl get imagerepository -n "$FLUX_NAMESPACE"
    
    echo "Image policies:"
    kubectl get imagepolicy -n "$FLUX_NAMESPACE"
    
    # Check if any GitRepository sources exist
    if kubectl get gitrepository -n "$FLUX_NAMESPACE" &> /dev/null; then
        echo "Git repositories:"
        kubectl get gitrepository -n "$FLUX_NAMESPACE"
    else
        echo "No Git repositories configured (normal if not bootstrapped with Git)"
    fi
    
    echo "✓ GitOps functionality verification completed"
}

# Main execution
main() {
    echo "Starting FluxCD installation and GitOps setup..."
    echo
    
    check_prerequisites
    echo
    
    install_flux_controllers
    echo
    
    create_git_repo_structure
    echo
    
    bootstrap_git_repository
    echo
    
    setup_image_automation
    echo
    
    verify_gitops_functionality
    echo
    
    echo "=== FluxCD Installation Summary ==="
    echo "✓ FluxCD controllers installed"
    echo "✓ Git repository structure created"
    if [ -n "$GIT_REPO_URL" ]; then
        echo "✓ Git repository bootstrapped"
    else
        echo "- Git repository bootstrap skipped (no URL provided)"
    fi
    echo "✓ Image update automation configured"
    echo "✓ GitOps functionality verified"
    echo
    echo "FluxCD is ready for GitOps operations!"
    echo
    echo "Next steps:"
    echo "1. Push Kubernetes manifests to your Git repository"
    echo "2. Install External Secrets Operator"
    echo "3. Deploy media server applications"
    echo
    if [ -z "$GIT_REPO_URL" ]; then
        echo "To bootstrap with a Git repository later:"
        echo "export GIT_REPO_URL=<your-repo-url>"
        echo "export GIT_TOKEN=<your-git-token>  # optional"
        echo "flux bootstrap git --url=\$GIT_REPO_URL --branch=$GIT_BRANCH --path=$GIT_PATH"
    fi
}

# Run main function
main "$@"