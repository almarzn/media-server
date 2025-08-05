#!/bin/bash

# Test script to verify Infisical integration and secret synchronization
# This script creates test secrets and verifies they sync correctly
# Designed to be idempotent and reusable across different Kubernetes distributions

set -euo pipefail

echo "=== Testing Infisical Integration and Secret Synchronization ==="

# Configuration variables
MEDIA_NAMESPACE="media-server"
ESO_NAMESPACE="external-secrets-system"

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

# Function to check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    # Detect and set kubeconfig
    detect_kubernetes_config
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo "ERROR: kubectl is not installed or not in PATH"
        echo "Please install kubectl or run the installation script first"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        echo "ERROR: Cannot connect to Kubernetes cluster"
        echo "Please ensure:"
        echo "1. Kubernetes cluster is running"
        echo "2. KUBECONFIG is set correctly"
        echo "3. You have appropriate permissions"
        exit 1
    fi
    
    # Check if External Secrets Operator is installed
    if ! kubectl get namespace "$ESO_NAMESPACE" &> /dev/null; then
        echo "ERROR: External Secrets Operator namespace does not exist."
        echo "Please run: ./scripts/setup/05-install-external-secrets.sh first"
        exit 1
    fi
    
    # Check if ESO controllers are running
    if ! kubectl get deployment external-secrets -n "$ESO_NAMESPACE" &> /dev/null; then
        echo "ERROR: External Secrets Operator controllers are not installed."
        echo "Please run: ./scripts/setup/05-install-external-secrets.sh first"
        exit 1
    fi
    
    # Check if media-server namespace exists
    if ! kubectl get namespace "$MEDIA_NAMESPACE" &> /dev/null; then
        echo "ERROR: $MEDIA_NAMESPACE namespace does not exist."
        echo "Please run: ./scripts/setup/05-install-external-secrets.sh first"
        exit 1
    fi
    
    # Check if infisical-auth secret exists
    if ! kubectl get secret infisical-auth -n "$MEDIA_NAMESPACE" &> /dev/null; then
        echo "ERROR: Infisical authentication secret does not exist."
        echo "Please run: ./scripts/setup/05-install-external-secrets.sh first"
        exit 1
    fi
    
    echo "✓ Prerequisites check completed"
}

# Function to create test SecretStore and ExternalSecret (idempotent)
create_test_resources() {
    echo "Creating test SecretStore and ExternalSecret..."
    
    # Prompt for Infisical Project ID
    if [[ -z "${INFISICAL_PROJECT_ID:-}" ]]; then
        echo "ERROR: INFISICAL_PROJECT_ID environment variable is required"
        echo "Please set it with: export INFISICAL_PROJECT_ID=<your-project-id>"
        echo "You can find your project ID in the Infisical dashboard"
        exit 1
    fi
    
    # Get environment from infisical-auth secret, default to dev if not found
    INFISICAL_ENVIRONMENT=$(kubectl get secret infisical-auth -n "$MEDIA_NAMESPACE" -o jsonpath='{.data.environment}' 2>/dev/null | base64 -d 2>/dev/null || echo "dev")
    echo "Using Infisical environment: $INFISICAL_ENVIRONMENT"
    echo "Using Infisical project: $INFISICAL_PROJECT_ID"
    
    # Check if test resources already exist
    if kubectl get secretstore test-infisical-secret-store -n "$MEDIA_NAMESPACE" &> /dev/null; then
        echo "✓ Test SecretStore already exists"
    else
        echo "Creating test SecretStore..."
        # Create test SecretStore
        cat > /tmp/test-secret-store.yaml << EOF
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: test-infisical-secret-store
  namespace: $MEDIA_NAMESPACE
  labels:
    app: external-secrets-test
spec:
  provider:
    infisical:
      hostAPI: https://eu.infisical.com/api
      auth:
        universalAuthCredentials:
          clientId:
            name: infisical-auth
            key: clientId
          clientSecret:
            name: infisical-auth
            key: clientSecret
      secretsScope:
        projectSlug: $INFISICAL_PROJECT_ID
        environmentSlug: $INFISICAL_ENVIRONMENT
EOF
        kubectl apply -f /tmp/test-secret-store.yaml
        rm -f /tmp/test-secret-store.yaml
        echo "✓ Test SecretStore created"
    fi
    
    if kubectl get externalsecret simple-test -n "$MEDIA_NAMESPACE" &> /dev/null; then
        echo "✓ Test ExternalSecret already exists"
    else
        echo "Creating test ExternalSecret..."
        # Create test ExternalSecret
        cat > /tmp/test-external-secret.yaml << EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: simple-test
  namespace: $MEDIA_NAMESPACE
  labels:
    app: external-secrets-test
spec:
  refreshInterval: 30s
  secretStoreRef:
    name: test-infisical-secret-store
    kind: SecretStore
  target:
    name: simple-test-synced
    creationPolicy: Owner
  data:
  - secretKey: message
    remoteRef:
      key: test/simple-test
EOF
        kubectl apply -f /tmp/test-external-secret.yaml
        rm -f /tmp/test-external-secret.yaml
        echo "✓ Test ExternalSecret created"
    fi
    
    echo "✓ Test resources are ready"
    echo "Note: Create a secret named 'simple-test' in folder '/media-server/test/' in Infisical for this test to pass"
}

# Function to test secret synchronization with timeout
test_secret_synchronization() {
    echo "Testing secret synchronization..."
    
    local timeout=120
    local interval=10
    local elapsed=0
    
    echo "Waiting up to ${timeout} seconds for secret synchronization..."
    
    while [ $elapsed -lt $timeout ]; do
        # Check if the synced secret was created
        if kubectl get secret simple-test-synced -n "$MEDIA_NAMESPACE" &> /dev/null; then
            echo "✓ Test secret synchronized successfully!"
            
            # Show the secret content (base64 decoded)
            echo "Secret content:"
            kubectl get secret simple-test-synced -n "$MEDIA_NAMESPACE" -o jsonpath='{.data.message}' | base64 -d
            echo
            
            return 0
        fi
        
        echo "Waiting... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo "⚠ Test secret not synchronized within ${timeout} seconds"
    return 1
}

# Function to check ExternalSecret status
check_external_secret_status() {
    echo "Checking ExternalSecret status..."
    
    # Get ExternalSecret status
    echo "ExternalSecret 'simple-test' status:"
    kubectl get externalsecret simple-test -n "$MEDIA_NAMESPACE" -o wide
    
    echo
    echo "ExternalSecret 'simple-test' detailed status:"
    kubectl describe externalsecret simple-test -n "$MEDIA_NAMESPACE"
}

# Function to check SecretStore status
check_secret_store_status() {
    echo "Checking SecretStore status..."
    
    # Get SecretStore status
    echo "SecretStore 'test-infisical-secret-store' status:"
    kubectl get secretstore test-infisical-secret-store -n "$MEDIA_NAMESPACE" -o wide
    
    echo
    echo "SecretStore 'test-infisical-secret-store' detailed status:"
    kubectl describe secretstore test-infisical-secret-store -n "$MEDIA_NAMESPACE"
}

# Function to check ESO controller logs
check_eso_logs() {
    echo "Checking External Secrets Operator logs..."
    
    # Get recent logs from ESO controller
    echo "Recent ESO controller logs:"
    kubectl logs -n "$ESO_NAMESPACE" -l app.kubernetes.io/name=external-secrets --tail=20
}

# Function to cleanup test resources (idempotent)
cleanup_test_resources() {
    echo "Cleaning up test resources..."
    
    # Delete test resources by label selector for better cleanup
    kubectl delete externalsecret,secretstore -l app=external-secrets-test -n "$MEDIA_NAMESPACE" --ignore-not-found=true
    kubectl delete secret simple-test-synced -n "$MEDIA_NAMESPACE" --ignore-not-found=true
    
    # Clean up any temporary files
    rm -f /tmp/test-secret-store.yaml /tmp/test-external-secret.yaml
    
    echo "✓ Test resources cleaned up"
}

# Function to run comprehensive diagnostics
run_diagnostics() {
    echo "Running comprehensive diagnostics..."
    
    echo "=== External Secrets Operator Status ==="
    kubectl get pods -n "$ESO_NAMESPACE"
    
    echo
    echo "=== SecretStore Resources ==="
    kubectl get secretstore -n "$MEDIA_NAMESPACE" || echo "No SecretStore resources found"
    
    echo
    echo "=== ExternalSecret Resources ==="
    kubectl get externalsecret -n "$MEDIA_NAMESPACE"
    
    echo
    echo "=== Synced Secrets ==="
    kubectl get secrets -n "$MEDIA_NAMESPACE" | grep -v "default-token\|Opaque.*3"
    
    echo
    echo "=== Infisical Authentication Secret ==="
    if kubectl get secret infisical-auth -n "$MEDIA_NAMESPACE" &> /dev/null; then
        echo "✓ Infisical authentication secret exists"
        kubectl get secret infisical-auth -n "$MEDIA_NAMESPACE" -o yaml | grep -E "name:|namespace:|clientId:|clientSecret:" | sed 's/clientSecret:.*/clientSecret: [REDACTED]/'
    else
        echo "✗ Infisical authentication secret missing"
    fi
    
    echo "✓ Diagnostics completed"
}

# Function to run Infisical authentication diagnostics
run_infisical_diagnostics() {
    echo "=== Infisical Authentication Diagnostics ==="
    
    # Get credentials from secret
    CLIENT_ID=$(kubectl get secret infisical-auth -n "$MEDIA_NAMESPACE" -o jsonpath='{.data.clientId}' | base64 -d)
    CLIENT_SECRET=$(kubectl get secret infisical-auth -n "$MEDIA_NAMESPACE" -o jsonpath='{.data.clientSecret}' | base64 -d)
    ENVIRONMENT=$(kubectl get secret infisical-auth -n "$MEDIA_NAMESPACE" -o jsonpath='{.data.environment}' | base64 -d)
    
    echo "Configuration:"
    echo "  Client ID: ${CLIENT_ID:0:8}...${CLIENT_ID: -8}"
    echo "  Environment: $ENVIRONMENT"
    echo "  Project ID: $INFISICAL_PROJECT_ID"
    echo
    
    # Test API connectivity
    echo "Testing Infisical API connectivity..."
    if curl -s --connect-timeout 10 https://eu.infisical.com/api/v1/auth/universal-auth/login > /dev/null; then
        echo "✓ Can reach Infisical API (EU region)"
    else
        echo "✗ Cannot reach Infisical API (EU region)"
        return 1
    fi
    
    # Test authentication
    echo "Testing authentication..."
    AUTH_RESPONSE=$(curl -s -X POST https://eu.infisical.com/api/v1/auth/universal-auth/login \
        -H "Content-Type: application/json" \
        -d "{\"clientId\":\"$CLIENT_ID\",\"clientSecret\":\"$CLIENT_SECRET\"}")
    
    if echo "$AUTH_RESPONSE" | grep -q "accessToken"; then
        echo "✓ Authentication successful"
        
        # Extract access token and test project access
        ACCESS_TOKEN=$(echo "$AUTH_RESPONSE" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
        
        echo "Testing project access..."
        PROJECT_RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
            "https://app.infisical.com/api/v3/secrets?workspaceId=$INFISICAL_PROJECT_ID&environment=$ENVIRONMENT&secretPath=/media-server/test")
        
        if echo "$PROJECT_RESPONSE" | grep -q "secrets"; then
            echo "✓ Project access successful"
            
            # Check if simple-test secret exists
            if echo "$PROJECT_RESPONSE" | grep -q "simple-test"; then
                echo "✓ Found 'simple-test' secret in project"
            else
                echo "⚠ 'simple-test' secret not found in project"
                echo "Please create a secret named 'simple-test' in folder '/media-server/test/' in Infisical"
            fi
        else
            echo "✗ Cannot access project or environment"
            echo "Response: $PROJECT_RESPONSE"
        fi
    else
        echo "✗ Authentication failed"
        echo "Response: $AUTH_RESPONSE"
        
        if echo "$AUTH_RESPONSE" | grep -q "404"; then
            echo "Error: Machine Identity not found (404)"
            echo "Please verify the Client ID exists in Infisical"
        elif echo "$AUTH_RESPONSE" | grep -q "401"; then
            echo "Error: Invalid credentials (401)"
            echo "Please verify the Client ID and Client Secret are correct"
        fi
    fi
}

# Function to provide troubleshooting guidance
provide_troubleshooting_guidance() {
    echo
    echo "=== Troubleshooting Guidance ==="
    echo
    echo "Based on the diagnostics above, here are the most common issues:"
    echo
    echo "1. Machine Identity not found (404 error):"
    echo "   - The Client ID doesn't exist in Infisical"
    echo "   - Create a new Machine Identity in Infisical"
    echo "   - Update the credentials using the installation script"
    echo
    echo "2. Invalid credentials (401 error):"
    echo "   - The Client Secret is incorrect"
    echo "   - Regenerate the Client Secret in Infisical"
    echo "   - Update the credentials using the installation script"
    echo
    echo "3. Project access denied:"
    echo "   - The Machine Identity doesn't have access to project $INFISICAL_PROJECT_ID"
    echo "   - Add the Machine Identity to the project in Infisical"
    echo "   - Ensure it has access to the '$INFISICAL_ENVIRONMENT' environment"
    echo
    echo "4. Secret not found:"
    echo "   - Create a folder structure '/media-server/test/' in Infisical"
    echo "   - Create a secret named 'simple-test' in that folder"
    echo "   - Ensure it's in the correct project and environment"
    echo
    echo "5. Network connectivity issues:"
    echo "   - Ensure the cluster can reach eu.infisical.com"
    echo "   - Check firewall and proxy settings"
    echo
    echo "To update credentials, run:"
    echo "  ./scripts/setup/05-install-external-secrets.sh \\"
    echo "    --client-id <new-client-id> \\"
    echo "    --client-secret <new-client-secret> \\"
    echo "    --environment $INFISICAL_ENVIRONMENT"
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Test External Secrets Operator integration with Infisical"
    echo
    echo "Options:"
    echo "  --cleanup-only    Only cleanup test resources and exit"
    echo "  --no-interactive  Skip interactive cleanup prompt"
    echo "  -h, --help        Show this help message"
    echo
    echo "Environment Variables:"
    echo "  INFISICAL_PROJECT_ID    Required: Your Infisical project ID"
    echo "  KUBECONFIG             Optional: Path to kubeconfig file"
    echo
    echo "Examples:"
    echo "  export INFISICAL_PROJECT_ID=your-project-id"
    echo "  $0"
    echo "  $0 --cleanup-only"
    echo "  $0 --no-interactive"
}

# Parse command line arguments
CLEANUP_ONLY=false
NO_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --cleanup-only)
            CLEANUP_ONLY=true
            shift
            ;;
        --no-interactive)
            NO_INTERACTIVE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo "Starting Infisical integration test..."
    echo
    
    check_prerequisites
    echo
    
    # If cleanup-only mode, just cleanup and exit
    if [[ "$CLEANUP_ONLY" == "true" ]]; then
        cleanup_test_resources
        echo "Cleanup completed."
        exit 0
    fi
    
    create_test_resources
    echo
    
    if test_secret_synchronization; then
        echo "✓ Secret synchronization test PASSED"
        success=true
    else
        echo "✗ Secret synchronization test FAILED"
        success=false
    fi
    echo
    
    check_external_secret_status
    echo
    
    check_secret_store_status
    echo
    
    if [ "$success" = false ]; then
        check_eso_logs
        echo
    fi
    
    run_diagnostics
    echo
    
    if [ "$success" = true ]; then
        echo "=== Test Summary ==="
        echo "✓ All tests passed successfully!"
        echo "✓ Infisical integration is working correctly"
        echo "✓ External Secrets Operator is ready for production use"
    else
        echo "=== Test Summary ==="
        echo "✗ Some tests failed"
        echo "✗ Infisical integration needs troubleshooting"
        echo
        run_infisical_diagnostics
        provide_troubleshooting_guidance
    fi
    echo
    
    # Handle cleanup based on mode
    if [[ "$NO_INTERACTIVE" == "true" ]]; then
        echo "Non-interactive mode: leaving test resources in place"
        echo "To cleanup later, run: $0 --cleanup-only"
    else
        # Ask if user wants to cleanup test resources
        read -p "Do you want to cleanup test resources? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cleanup_test_resources
        else
            echo "Test resources left in place for further investigation"
            echo "To cleanup later, run: $0 --cleanup-only"
        fi
    fi
}

# Run main function
main "$@"