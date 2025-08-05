#!/bin/bash

# External Secrets Operator Installation Script
# This script installs External Secrets Operator controllers and creates Infisical authentication secret
# Designed to be idempotent and reusable across different Kubernetes distributions

set -euo pipefail

echo "=== Installing External Secrets Operator Controllers ==="

# Configuration variables
ESO_NAMESPACE="external-secrets-system"
MEDIA_NAMESPACE="media-server"

# Auto-detect Kubernetes distribution and set KUBECONFIG
detect_kubernetes_config() {
    if [[ -n "${KUBECONFIG:-}" ]]; then
        echo "Using existing KUBECONFIG: $KUBECONFIG"
    elif [[ -f "/etc/rancher/k3s/k3s.yaml" ]]; then
        export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
        echo "Detected k3s, using KUBECONFIG: $KUBECONFIG"
    elif [[ -f "$HOME/.kube/config" ]]; then
        export KUBECONFIG="$HOME/.kube/config"
        echo "Using default kubeconfig: $KUBECONFIG"
    else
        echo "WARNING: No kubeconfig found. Please set KUBECONFIG environment variable."
        echo "For k3s: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
        echo "For standard k8s: export KUBECONFIG=~/.kube/config"
    fi
}

# Parse command line arguments
INFISICAL_CLIENT_ID=""
INFISICAL_CLIENT_SECRET=""
INFISICAL_ENVIRONMENT="dev"
FORCE_REINSTALL=false

# Function to show usage
usage() {
    echo "Usage: $0 --client-id <client-id> --client-secret <client-secret> [OPTIONS]"
    echo "Install External Secrets Operator and configure Infisical authentication"
    echo
    echo "Required Arguments:"
    echo "  --client-id       Infisical Machine Identity Client ID"
    echo "  --client-secret   Infisical Machine Identity Client Secret"
    echo
    echo "Options:"
    echo "  --environment     Infisical environment (default: dev)"
    echo "  --force           Force reinstallation even if already installed"
    echo "  -h, --help        Show this help message"
    echo
    echo "Environment Variables:"
    echo "  KUBECONFIG        Optional: Path to kubeconfig file"
    echo
    echo "Examples:"
    echo "  $0 --client-id 931a9617-e5ca-4d1a-8396-75a40973e699 --client-secret 5c92d34ffe5436b93947326c0bce52fa0b5002ca70e42555ecf00b48728c77cf"
    echo "  $0 --client-id <id> --client-secret <secret> --environment prod"
    echo "  $0 --client-id <id> --client-secret <secret> --force"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --client-id)
            INFISICAL_CLIENT_ID="$2"
            shift 2
            ;;
        --client-secret)
            INFISICAL_CLIENT_SECRET="$2"
            shift 2
            ;;
        --environment)
            INFISICAL_ENVIRONMENT="$2"
            shift 2
            ;;
        --force)
            FORCE_REINSTALL=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$INFISICAL_CLIENT_ID" || -z "$INFISICAL_CLIENT_SECRET" ]]; then
    echo "ERROR: Both --client-id and --client-secret are required"
    usage
fi

# Function to install kubectl if not present (for Fedora CoreOS compatibility)
ensure_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "kubectl not found, attempting to install..."
        
        # Detect OS and install kubectl accordingly
        if [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then
            # Fedora/RHEL/CentOS
            if command -v dnf &> /dev/null; then
                sudo dnf install -y kubernetes-client
            elif command -v yum &> /dev/null; then
                sudo yum install -y kubernetes-client
            else
                # Fallback to direct download
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                chmod +x kubectl
                sudo mv kubectl /usr/local/bin/
            fi
        else
            # Generic Linux - direct download
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            chmod +x kubectl
            sudo mv kubectl /usr/local/bin/
        fi
        
        # Verify installation
        if ! command -v kubectl &> /dev/null; then
            echo "ERROR: Failed to install kubectl"
            exit 1
        fi
        echo "✓ kubectl installed successfully"
    fi
}

# Function to ensure helm is available
ensure_helm() {
    if ! command -v helm &> /dev/null; then
        echo "Helm not found, installing..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        
        # Verify installation
        if ! command -v helm &> /dev/null; then
            echo "ERROR: Failed to install Helm"
            exit 1
        fi
        echo "✓ Helm installed successfully"
    else
        echo "✓ Helm already available"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    # Detect and set kubeconfig
    detect_kubernetes_config
    
    # Ensure kubectl is available
    ensure_kubectl
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        echo "ERROR: Cannot connect to Kubernetes cluster"
        echo "Please ensure:"
        echo "1. Kubernetes cluster is running"
        echo "2. KUBECONFIG is set correctly"
        echo "3. You have appropriate permissions"
        exit 1
    fi
    
    # Create media-server namespace if it doesn't exist (idempotent)
    if ! kubectl get namespace "$MEDIA_NAMESPACE" &> /dev/null; then
        echo "Creating $MEDIA_NAMESPACE namespace..."
        kubectl create namespace "$MEDIA_NAMESPACE"
        echo "✓ $MEDIA_NAMESPACE namespace created"
    else
        echo "✓ $MEDIA_NAMESPACE namespace already exists"
    fi
    
    echo "✓ Prerequisites check completed"
}

# Function to install External Secrets Operator controllers only (idempotent)
install_external_secrets_operator() {
    echo "Installing External Secrets Operator controllers..."
    
    # Create namespace if it doesn't exist (idempotent)
    kubectl create namespace "$ESO_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Ensure helm is available
    ensure_helm
    
    # Add helm repository (idempotent)
    echo "Adding External Secrets Helm repository..."
    helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
    helm repo update
    
    # Check if ESO is already installed and healthy (unless force reinstall)
    if [[ "$FORCE_REINSTALL" == "false" ]] && helm list -n "$ESO_NAMESPACE" | grep -q "external-secrets"; then
        echo "External Secrets Operator Helm release already exists, checking status..."
        
        # Check if deployment is healthy
        if kubectl get deployment external-secrets -n "$ESO_NAMESPACE" &> /dev/null && \
           kubectl wait --for=condition=available deployment external-secrets -n "$ESO_NAMESPACE" --timeout=30s &> /dev/null; then
            echo "✓ External Secrets Operator is already installed and healthy"
            return 0
        else
            echo "External Secrets Operator installation appears unhealthy, upgrading..."
            # Upgrade existing installation
            helm upgrade external-secrets external-secrets/external-secrets \
                --namespace "$ESO_NAMESPACE" \
                --set installCRDs=true \
                --set replicaCount=1 \
                --set resources.limits.cpu=100m \
                --set resources.limits.memory=128Mi \
                --set resources.requests.cpu=10m \
                --set resources.requests.memory=64Mi \
                --wait
        fi
    elif [[ "$FORCE_REINSTALL" == "true" ]] && helm list -n "$ESO_NAMESPACE" | grep -q "external-secrets"; then
        echo "Force reinstall requested, uninstalling existing release..."
        helm uninstall external-secrets -n "$ESO_NAMESPACE"
        # Wait for resources to be cleaned up
        echo "Waiting for cleanup to complete..."
        sleep 10
        
        echo "Installing External Secrets Operator via Helm..."
        # Fresh installation
        helm install external-secrets external-secrets/external-secrets \
            --namespace "$ESO_NAMESPACE" \
            --set installCRDs=true \
            --set replicaCount=1 \
            --set resources.limits.cpu=100m \
            --set resources.limits.memory=128Mi \
            --set resources.requests.cpu=10m \
            --set resources.requests.memory=64Mi \
            --wait
    else
        echo "Installing External Secrets Operator via Helm..."
        # Fresh installation
        helm install external-secrets external-secrets/external-secrets \
            --namespace "$ESO_NAMESPACE" \
            --set installCRDs=true \
            --set replicaCount=1 \
            --set resources.limits.cpu=100m \
            --set resources.limits.memory=128Mi \
            --set resources.requests.cpu=10m \
            --set resources.requests.memory=64Mi \
            --wait
    fi
    
    # Wait for controllers to be ready
    echo "Waiting for External Secrets Operator controllers to be ready..."
    kubectl wait --for=condition=available deployment --all -n "$ESO_NAMESPACE" --timeout=300s
    
    # Verify installation
    echo "External Secrets Operator controllers:"
    kubectl get pods -n "$ESO_NAMESPACE"
    
    echo "✓ External Secrets Operator controllers installed successfully"
}

# Function to create Infisical authentication secret (secret zero) - idempotent
create_infisical_auth_secret() {
    echo "Creating Infisical authentication secret (secret zero)..."
    
    # Check if secret already exists
    if kubectl get secret infisical-auth -n "$MEDIA_NAMESPACE" &> /dev/null; then
        echo "infisical-auth secret already exists, checking if update is needed..."
        
        # Get current environment from secret
        CURRENT_ENV=$(kubectl get secret infisical-auth -n "$MEDIA_NAMESPACE" -o jsonpath='{.data.environment}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        CURRENT_CLIENT_ID=$(kubectl get secret infisical-auth -n "$MEDIA_NAMESPACE" -o jsonpath='{.data.clientId}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
        
        # Check if update is needed
        if [[ "$CURRENT_ENV" != "$INFISICAL_ENVIRONMENT" ]] || [[ "$CURRENT_CLIENT_ID" != "$INFISICAL_CLIENT_ID" ]]; then
            echo "Updating infisical-auth secret with new values..."
            kubectl delete secret infisical-auth -n "$MEDIA_NAMESPACE"
        else
            echo "✓ infisical-auth secret is up to date"
            return 0
        fi
    fi
    
    # Create or recreate the secret
    echo "Creating infisical-auth secret in $MEDIA_NAMESPACE namespace..."
    echo "Using Infisical environment: $INFISICAL_ENVIRONMENT"
    kubectl create secret generic infisical-auth \
        --from-literal=clientId="$INFISICAL_CLIENT_ID" \
        --from-literal=clientSecret="$INFISICAL_CLIENT_SECRET" \
        --from-literal=environment="$INFISICAL_ENVIRONMENT" \
        --namespace="$MEDIA_NAMESPACE"
    
    echo "✓ Infisical authentication secret (secret zero) created successfully"
}

# Function to verify ESO installation
verify_eso_installation() {
    echo "Verifying External Secrets Operator installation..."
    
    # Check External Secrets Operator status
    echo "External Secrets Operator controllers:"
    kubectl get pods -n "$ESO_NAMESPACE" -o wide
    
    # Check CRDs are installed
    echo "External Secrets CRDs:"
    ESO_CRDS=$(kubectl get crd | grep external-secrets | wc -l)
    if [[ $ESO_CRDS -gt 0 ]]; then
        echo "✓ Found $ESO_CRDS External Secrets CRDs"
        kubectl get crd | grep external-secrets | head -5
        if [[ $ESO_CRDS -gt 5 ]]; then
            echo "... and $((ESO_CRDS - 5)) more CRDs"
        fi
    else
        echo "⚠ No External Secrets CRDs found"
    fi
    
    # Check Helm release status
    echo "Helm release status:"
    helm list -n "$ESO_NAMESPACE"
    
    # Test basic functionality
    echo "Testing basic API access:"
    if kubectl get secretstores -A &> /dev/null; then
        echo "✓ SecretStore API is accessible"
    else
        echo "⚠ SecretStore API is not accessible"
    fi
    
    if kubectl get externalsecrets -A &> /dev/null; then
        echo "✓ ExternalSecret API is accessible"
    else
        echo "⚠ ExternalSecret API is not accessible"
    fi
    
    echo "✓ External Secrets Operator installation verification completed"
}

# Main execution
main() {
    echo "Starting External Secrets Operator installation..."
    echo
    
    check_prerequisites
    echo
    
    install_external_secrets_operator
    echo
    
    create_infisical_auth_secret
    echo
    
    verify_eso_installation
    echo
    
    echo "=== External Secrets Operator Installation Summary ==="
    echo "✓ External Secrets Operator controllers and CRDs installed"
    echo "✓ Infisical authentication secret (secret zero) created"
    echo "✓ Installation is idempotent and reusable"
    echo
    echo "External Secrets Operator is ready for use!"
    echo
    echo "Configuration:"
    echo "  - Namespace: $ESO_NAMESPACE"
    echo "  - Target namespace: $MEDIA_NAMESPACE"
    echo "  - Infisical environment: $INFISICAL_ENVIRONMENT"
    echo
    echo "Next steps:"
    echo "1. Create SecretStore and ExternalSecret resources via Helm charts"
    echo "2. Create secrets in Infisical for your applications"
    echo "3. Deploy your applications that depend on External Secrets"
    echo
    echo "Note: SecretStore and ExternalSecret resources should be managed"
    echo "      through Helm charts in the charts/ directory, not this script."
    echo
    echo "Test the installation with:"
    echo "  export INFISICAL_PROJECT_ID=<your-project-id>"
    echo "  ./scripts/setup/test-infisical-integration.sh"
    echo
    echo "Troubleshooting:"
    echo "  - Re-run with --force to reinstall if needed"
    echo "  - Check logs: kubectl logs -n $ESO_NAMESPACE -l app.kubernetes.io/name=external-secrets"
}

# Run main function
main "$@"