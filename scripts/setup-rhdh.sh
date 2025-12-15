#!/bin/bash

# RHDH Instance Setup Script
# =============================================================================
# Deploys or patches an RHDH instance with:
#   - GitHub App authentication
#   - Dynamic plugins (ArgoCD, Tekton, Kubernetes, etc.)
#   - Catalog integration
#
# This script is idempotent - safe to run multiple times.
#
# Usage: ./setup-rhdh.sh
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFESTS_DIR="$PROJECT_ROOT/manifests/rhdh"

# Default values
RHDH_NAMESPACE="${RHDH_NAMESPACE:-rhdh}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-openshift-gitops}"
ARGOCD_USERNAME="${ARGOCD_USERNAME:-admin}"

# Helper Functions

print_header() {
    echo ""
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}=============================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if resource exists
resource_exists() {
    local type="$1"
    local name="$2"
    local namespace="$3"
    
    if [ -n "$namespace" ]; then
        oc get "$type" "$name" -n "$namespace" &>/dev/null
    else
        oc get "$type" "$name" &>/dev/null
    fi
}

# Load environment file
load_env_file() {
    local env_file="$PROJECT_ROOT/.env"
    
    if [ ! -f "$env_file" ]; then
        print_error ".env file not found at: $env_file"
        echo ""
        echo "Please create it from the example:"
        echo "  cp .env.example .env"
        echo "  vim .env"
        exit 1
    fi
    
    print_info "Loading configuration from .env..."
    
    # Source the env file (handle values with = in them)
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse key=value
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Remove surrounding quotes if present
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            export "$key=$value"
        fi
    done < "$env_file"
}

# Validate required variables
validate_env() {
    print_header "Validating Configuration"
    
    local missing=0
    
    # Required GitHub App variables
    for var in GITHUB_APP_ID GITHUB_APP_CLIENT_ID GITHUB_APP_CLIENT_SECRET GITHUB_ORG; do
        if [ -z "${!var}" ]; then
            print_error "Missing required variable: $var"
            missing=1
        else
            print_success "$var is set"
        fi
    done
    
    # Check private key file
    if [ -z "$GITHUB_APP_PRIVATE_KEY_FILE" ]; then
        print_warning "GITHUB_APP_PRIVATE_KEY_FILE not set - GitHub App integration may not work"
    elif [ ! -f "$GITHUB_APP_PRIVATE_KEY_FILE" ]; then
        # Try relative to project root
        if [ -f "$PROJECT_ROOT/$GITHUB_APP_PRIVATE_KEY_FILE" ]; then
            GITHUB_APP_PRIVATE_KEY_FILE="$PROJECT_ROOT/$GITHUB_APP_PRIVATE_KEY_FILE"
            print_success "GITHUB_APP_PRIVATE_KEY_FILE found"
        else
            print_warning "Private key file not found: $GITHUB_APP_PRIVATE_KEY_FILE"
            print_info "GitHub App integration may not work without private key"
        fi
    else
        print_success "GITHUB_APP_PRIVATE_KEY_FILE found"
    fi
    
    if [ $missing -eq 1 ]; then
        echo ""
        print_error "Please update your .env file with the missing values"
        exit 1
    fi
}

# Auto-detect cluster domain
detect_cluster_domain() {
    if [ -z "$CLUSTER_DOMAIN" ]; then
        print_info "Auto-detecting cluster domain..."
        CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
        
        if [ -z "$CLUSTER_DOMAIN" ]; then
            print_error "Could not detect cluster domain"
            echo "Please set CLUSTER_DOMAIN in .env file"
            exit 1
        fi
    fi
    
    print_success "Cluster domain: $CLUSTER_DOMAIN"
    export CLUSTER_DOMAIN
}

# Auto-detect ArgoCD password
detect_argocd_password() {
    if [ -z "$ARGOCD_PASSWORD" ]; then
        print_info "Auto-detecting ArgoCD password..."
        
        ARGOCD_PASSWORD=$(oc get secret openshift-gitops-cluster -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d || echo "")
        
        if [ -z "$ARGOCD_PASSWORD" ]; then
            print_warning "Could not detect ArgoCD password"
            print_info "ArgoCD integration may not work. Set ARGOCD_PASSWORD in .env"
        else
            print_success "ArgoCD password detected"
        fi
    else
        print_success "ArgoCD password provided"
    fi
    
    export ARGOCD_PASSWORD
}

# Read GitHub App private key
read_private_key() {
    if [ -n "$GITHUB_APP_PRIVATE_KEY_FILE" ] && [ -f "$GITHUB_APP_PRIVATE_KEY_FILE" ]; then
        print_info "Reading GitHub App private key..."
        GITHUB_APP_PRIVATE_KEY=$(cat "$GITHUB_APP_PRIVATE_KEY_FILE")
        
        if [ -z "$GITHUB_APP_PRIVATE_KEY" ]; then
            print_warning "Private key file is empty"
        else
            print_success "Private key loaded"
        fi
    else
        print_warning "No private key file - skipping"
        GITHUB_APP_PRIVATE_KEY=""
    fi
    
    export GITHUB_APP_PRIVATE_KEY
}

# Generate backend secret
generate_backend_secret() {
    if [ -z "$BACKEND_SECRET" ]; then
        BACKEND_SECRET=$(openssl rand -hex 32)
        print_success "Generated backend secret"
    fi
    export BACKEND_SECRET
}

# Create or update namespace
setup_namespace() {
    print_header "Setting up Namespace"
    
    if resource_exists namespace "$RHDH_NAMESPACE"; then
        print_warning "Namespace $RHDH_NAMESPACE already exists"
    else
        print_info "Creating namespace $RHDH_NAMESPACE..."
        oc create namespace "$RHDH_NAMESPACE"
        print_success "Namespace created"
    fi
}

# Create or update secrets
setup_secrets() {
    print_header "Setting up Secrets"
    
    local secret_name="rhdh-secrets"
    
    # Delete existing secret to recreate with new values
    if resource_exists secret "$secret_name" "$RHDH_NAMESPACE"; then
        print_info "Updating existing secret..."
        oc delete secret "$secret_name" -n "$RHDH_NAMESPACE"
    fi
    
    print_info "Creating secret $secret_name..."
    
    oc create secret generic "$secret_name" -n "$RHDH_NAMESPACE" \
        --from-literal=GITHUB_APP_ID="$GITHUB_APP_ID" \
        --from-literal=GITHUB_APP_CLIENT_ID="$GITHUB_APP_CLIENT_ID" \
        --from-literal=GITHUB_APP_CLIENT_SECRET="$GITHUB_APP_CLIENT_SECRET" \
        --from-literal=GITHUB_APP_WEBHOOK_URL="${GITHUB_APP_WEBHOOK_URL:-}" \
        --from-literal=GITHUB_APP_WEBHOOK_SECRET="${GITHUB_APP_WEBHOOK_SECRET:-}" \
        --from-literal=GITHUB_APP_PRIVATE_KEY="$GITHUB_APP_PRIVATE_KEY" \
        --from-literal=GITHUB_ORG="$GITHUB_ORG" \
        --from-literal=ARGOCD_USERNAME="$ARGOCD_USERNAME" \
        --from-literal=ARGOCD_PASSWORD="${ARGOCD_PASSWORD:-}" \
        --from-literal=BACKEND_SECRET="$BACKEND_SECRET"
    
    print_success "Secret created"
}

# Apply ConfigMap with selective variable substitution
# Only substitute infrastructure variables, leave credential variables for RHDH runtime resolution
apply_configmap() {
    local template_file="$1"
    local configmap_name="$2"
    
    print_info "Applying ConfigMap: $configmap_name..."
    
    # Only substitute infrastructure variables (not credentials)
    # RHDH will resolve credential variables like ${GITHUB_APP_CLIENT_ID} from secrets at runtime
    envsubst '${RHDH_NAMESPACE} ${CLUSTER_DOMAIN} ${GITHUB_ORG} ${ARGOCD_NAMESPACE}' < "$template_file" | oc apply -f -
    
    print_success "ConfigMap applied"
}

# Setup ConfigMaps
setup_configmaps() {
    print_header "Setting up ConfigMaps"
    
    # Export infrastructure variables for envsubst
    # Credential variables are left as ${VAR} for RHDH to resolve from secrets at runtime
    export RHDH_NAMESPACE CLUSTER_DOMAIN GITHUB_ORG ARGOCD_NAMESPACE
    
    apply_configmap "$MANIFESTS_DIR/app-config-template.yaml" "app-config-rhdh"
    apply_configmap "$MANIFESTS_DIR/dynamic-plugins-template.yaml" "dynamic-plugins-rhdh"
}

# Setup RBAC for Kubernetes plugin
setup_rbac() {
    print_header "Setting up RBAC"
    
    local sa_name="default"
    local binding_name="rhdh-cluster-reader"
    
    if resource_exists clusterrolebinding "$binding_name"; then
        print_warning "ClusterRoleBinding $binding_name already exists"
    else
        print_info "Creating ClusterRoleBinding for Kubernetes plugin..."
        
        cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $binding_name
subjects:
  - kind: ServiceAccount
    name: $sa_name
    namespace: $RHDH_NAMESPACE
roleRef:
  kind: ClusterRole
  name: cluster-reader
  apiGroup: rbac.authorization.k8s.io
EOF
        
        print_success "ClusterRoleBinding created"
    fi
}

# Deploy Backstage CR
deploy_backstage() {
    print_header "Deploying RHDH Instance"
    
    export RHDH_NAMESPACE
    
    if resource_exists backstage backstage "$RHDH_NAMESPACE"; then
        print_warning "Backstage CR already exists - patching..."
        
        # Add annotation to trigger reconciliation
        oc annotate backstage backstage -n "$RHDH_NAMESPACE" \
            "rhdh.redhat.com/updated-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --overwrite
        
        print_success "Backstage CR patched"
    else
        print_info "Creating Backstage CR..."
        envsubst < "$MANIFESTS_DIR/backstage-cr-template.yaml" | oc apply -f -
        print_success "Backstage CR created"
    fi
}

# Wait for deployment to be ready
wait_for_ready() {
    print_header "Waiting for RHDH to be Ready"
    
    print_info "Waiting for deployment (this may take a few minutes)..."
    
    local timeout=300
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        local ready=$(oc get deployment -n "$RHDH_NAMESPACE" -l app.kubernetes.io/name=backstage \
            -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
        
        if [ "$ready" = "1" ]; then
            print_success "RHDH is ready!"
            return 0
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        echo -n "."
    done
    
    echo ""
    print_warning "Timeout waiting for RHDH. Check deployment status:"
    echo "  oc get pods -n $RHDH_NAMESPACE"
}

# Print summary and URLs
print_summary() {
    local rhdh_url="https://backstage-demo-${RHDH_NAMESPACE}.${CLUSTER_DOMAIN}"
    
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}  RHDH Configuration Complete!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo -e "RHDH URL: ${BLUE}$rhdh_url${NC}"
    echo ""
    echo "GitHub App Configuration:"
    echo "  Update your GitHub App settings with these URLs:"
    echo ""
    echo "  Homepage URL:"
    echo -e "    ${BLUE}$rhdh_url${NC}"
    echo ""
    echo "  Authorization callback URL:"
    echo -e "    ${BLUE}$rhdh_url/api/auth/github/handler/frame${NC}"
    echo ""
    echo "  Webhook URL (optional):"
    echo -e "    ${BLUE}$rhdh_url/api/events/github${NC}"
    echo ""
    echo "Next Steps:"
    echo "  1. Update GitHub App with the URLs above"
    echo "  2. Open RHDH URL and login with GitHub"
    echo "  3. Register your software template in the catalog"
    echo ""
    echo -e "${GREEN}=============================================${NC}"
}

# Main
main() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       RHDH Instance Setup                                     ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check prerequisites
    if ! command -v oc &> /dev/null; then
        print_error "OpenShift CLI (oc) not found"
        exit 1
    fi
    
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into OpenShift cluster"
        exit 1
    fi
    
    if ! command -v envsubst &> /dev/null; then
        print_error "envsubst not found. Install gettext package."
        exit 1
    fi
    
    print_success "Logged in as: $(oc whoami)"
    print_success "Cluster: $(oc whoami --show-server)"
    
    # Run setup steps
    load_env_file
    validate_env
    detect_cluster_domain
    detect_argocd_password
    read_private_key
    generate_backend_secret
    setup_namespace
    setup_secrets
    setup_configmaps
    setup_rbac
    deploy_backstage
    wait_for_ready
    print_summary
}

# Run main
main "$@"

