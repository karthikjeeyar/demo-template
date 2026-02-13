#!/bin/bash

# Operator Installation Script
# =============================================================================
# Installs all required operators for the RHDH demo:
#   1. OpenShift Pipelines (Tekton)
#   2. OpenShift GitOps (ArgoCD)
#   3. Red Hat Developer Hub (RHDH)
#   4. Sealed Secrets Controller
#
# Usage: ./setup-operators.sh
#
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Versions
SEALED_SECRETS_VERSION="v0.24.0"

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

wait_for_operator() {
    local subscription_name="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    
    print_info "Waiting for $subscription_name to be ready (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        # Check if CSV is installed
        local csv=$(oc get subscription "$subscription_name" -n "$namespace" -o jsonpath='{.status.installedCSV}' 2>/dev/null || echo "")
        
        if [ -n "$csv" ]; then
            local phase=$(oc get csv "$csv" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            if [ "$phase" = "Succeeded" ]; then
                print_success "$subscription_name is ready (CSV: $csv)"
                return 0
            fi
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    
    echo ""
    print_error "Timeout waiting for $subscription_name"
    return 1
}

# Check Prerequisites

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check oc CLI
    if ! command -v oc &> /dev/null; then
        print_error "OpenShift CLI (oc) not found. Please install it first."
        echo "  brew install openshift-cli"
        exit 1
    fi
    print_success "oc CLI found"
    
    # Check cluster login
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into OpenShift cluster."
        echo ""
        echo "Please login first:"
        echo "  oc login --server=<cluster-api-url> --token=<token>"
        exit 1
    fi
    
    CURRENT_USER=$(oc whoami)
    CURRENT_CLUSTER=$(oc whoami --show-server)
    
    print_success "Logged in as: $CURRENT_USER"
    print_success "Cluster: $CURRENT_CLUSTER"
}

# Install OpenShift Pipelines (Tekton)

install_openshift_pipelines() {
    print_header "Installing OpenShift Pipelines (Tekton)"
    
    # Check if already installed
    if oc get subscription openshift-pipelines-operator-rh -n openshift-operators &> /dev/null; then
        print_warning "OpenShift Pipelines subscription already exists"
        wait_for_operator "openshift-pipelines-operator-rh" "openshift-operators" 60
        return 0
    fi
    
    print_info "Creating OpenShift Pipelines subscription..."
    
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator-rh
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
    
    wait_for_operator "openshift-pipelines-operator-rh" "openshift-operators"
    print_success "OpenShift Pipelines installed"
}

# Install OpenShift GitOps (ArgoCD)

install_openshift_gitops() {
    print_header "Installing OpenShift GitOps (ArgoCD)"
    
    # # Create namespace if needed
    # if ! oc get namespace openshift-gitops-operator &> /dev/null; then
    #     oc create namespace openshift-gitops-operator
    # fi
    
    # Check if already installed
    if oc get subscription openshift-gitops-operator -n openshift-operators &> /dev/null; then
        print_warning "OpenShift GitOps subscription already exists"
        wait_for_operator "openshift-gitops-operator" "openshift-operators" 60
    else
        print_info "Creating OpenShift GitOps subscription..."
        
        cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: openshift-gitops-operator.v1.19.1
EOF
        
        wait_for_operator "openshift-gitops-operator" "openshift-operators"
    fi
    
    # Wait for ArgoCD CR to be created
    print_info "Waiting for ArgoCD instance to be ready..."
    sleep 10
    
    local elapsed=0
    while [ $elapsed -lt 120 ]; do
        if oc get argocd openshift-gitops -n openshift-gitops &> /dev/null; then
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    echo ""
    
    # Configure ArgoCD with custom instanceLabelKey
    print_info "Configuring ArgoCD with custom instanceLabelKey..."
    
    oc patch argocd openshift-gitops -n openshift-gitops --type=merge -p '
{
  "spec": {
    "extraConfig": {
      "application.instanceLabelKey": "argocd.argoproj.io/instance"
    }
  }
}'
    
    print_success "OpenShift GitOps installed and configured"
}

# Install Red Hat Developer Hub (RHDH)

install_rhdh() {
    print_header "Installing Red Hat Developer Hub"
    
    # Check if already installed
    if oc get subscription rhdh -n openshift-operators &> /dev/null; then
        print_warning "RHDH subscription already exists"
        wait_for_operator "rhdh" "openshift-operators" 60
        return 0
    fi
    
    print_info "Creating RHDH subscription..."
    
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhdh
  namespace: openshift-operators
spec:
  channel: fast-1.8
  installPlanApproval: Automatic
  name: rhdh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
    
    wait_for_operator "rhdh" "openshift-operators"
    print_success "Red Hat Developer Hub installed"
    
    print_info "Note: You'll need to create a Backstage CR to deploy RHDH instance"
}

# Install Sealed Secrets Controller

install_sealed_secrets() {
    print_header "Installing Sealed Secrets Controller"
    
    # Check if already installed
    if oc get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
        print_warning "Sealed Secrets controller already installed"
        return 0
    fi
    
    print_info "Installing Sealed Secrets controller ${SEALED_SECRETS_VERSION}..."
    
    oc apply -f "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/controller.yaml"
    
    print_info "Waiting for controller to be ready..."
    oc rollout status deployment/sealed-secrets-controller -n kube-system --timeout=120s
    
    print_success "Sealed Secrets controller installed"
}

# Install kubeseal CLI

install_kubeseal() {
    print_header "Installing kubeseal CLI"
    
    if command -v kubeseal &> /dev/null; then
        KUBESEAL_VERSION=$(kubeseal --version 2>/dev/null || echo "unknown")
        print_warning "kubeseal already installed: $KUBESEAL_VERSION"
        return 0
    fi
    
    # Detect OS
    OS=$(uname -s)
    ARCH=$(uname -m)
    
    if [ "$OS" = "Darwin" ]; then
        if command -v brew &> /dev/null; then
            print_info "Installing kubeseal via Homebrew..."
            brew install kubeseal
        else
            print_info "Installing kubeseal manually..."
            if [ "$ARCH" = "arm64" ]; then
                KUBESEAL_ARCH="arm64"
            else
                KUBESEAL_ARCH="amd64"
            fi
            curl -L "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/kubeseal-${SEALED_SECRETS_VERSION#v}-darwin-${KUBESEAL_ARCH}.tar.gz" | tar xz
            sudo mv kubeseal /usr/local/bin/
        fi
    elif [ "$OS" = "Linux" ]; then
        print_info "Installing kubeseal for Linux..."
        if [ "$ARCH" = "x86_64" ]; then
            KUBESEAL_ARCH="amd64"
        else
            KUBESEAL_ARCH="$ARCH"
        fi
        curl -L "https://github.com/bitnami-labs/sealed-secrets/releases/download/${SEALED_SECRETS_VERSION}/kubeseal-${SEALED_SECRETS_VERSION#v}-linux-${KUBESEAL_ARCH}.tar.gz" | tar xz
        sudo mv kubeseal /usr/local/bin/
    else
        print_error "Unsupported OS: $OS"
        exit 1
    fi
    
    print_success "kubeseal installed"
}

# Summary

print_summary() {
    print_header "Installation Summary"
    
    echo ""
    echo "Installed Operators:"
    echo ""
    
    # Check each operator
    if oc get subscription openshift-pipelines-operator-rh -n openshift-operators &> /dev/null; then
        print_success "OpenShift Pipelines (Tekton)"
    else
        print_error "OpenShift Pipelines (Tekton)"
    fi
    
    if oc get subscription openshift-gitops-operator -n openshift-operators &> /dev/null; then
        print_success "OpenShift GitOps (ArgoCD)"
    else
        print_error "OpenShift GitOps (ArgoCD)"
    fi
    
    if oc get subscription rhdh -n openshift-operators &> /dev/null; then
        print_success "Red Hat Developer Hub"
    else
        print_error "Red Hat Developer Hub"
    fi
    
    if oc get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
        print_success "Sealed Secrets Controller"
    else
        print_error "Sealed Secrets Controller"
    fi
    
    if command -v kubeseal &> /dev/null; then
        print_success "kubeseal CLI"
    else
        print_error "kubeseal CLI"
    fi
    
    echo ""
}

# Configure Cluster Domain

configure_cluster_domain() {
    print_header "Configuring Cluster Domain"
    
    # Get script directory and project root
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    
    # Try to get cluster domain from .env file first
    if [ -f "$PROJECT_ROOT/.env" ]; then
        CLUSTER_DOMAIN=$(grep -E "^CLUSTER_DOMAIN=" "$PROJECT_ROOT/.env" | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
    
    # If not set, auto-detect from cluster
    if [ -z "$CLUSTER_DOMAIN" ]; then
        print_info "Auto-detecting cluster domain..."
        
        # Get the cluster domain from OpenShift ingress config
        CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
        
        if [ -z "$CLUSTER_DOMAIN" ]; then
            print_warning "Could not auto-detect cluster domain"
            print_info "Set CLUSTER_DOMAIN in .env file manually"
            return 0
        fi
    fi
    
    print_success "Cluster domain: $CLUSTER_DOMAIN"
    
    # Update template.yaml with the cluster domain
    TEMPLATE_FILE="$PROJECT_ROOT/template.yaml"
    
    if [ -f "$TEMPLATE_FILE" ]; then
        print_info "Updating template.yaml with cluster domain..."
        
        # Update the default value for cluster_domain
        if grep -q "default: apps.cluster.example.com" "$TEMPLATE_FILE"; then
            sed -i.bak "s|default: apps.cluster.example.com|default: $CLUSTER_DOMAIN|g" "$TEMPLATE_FILE"
            rm -f "${TEMPLATE_FILE}.bak"
            print_success "Updated template.yaml cluster_domain default"
        elif grep -q "default: $CLUSTER_DOMAIN" "$TEMPLATE_FILE"; then
            print_warning "template.yaml already configured with this domain"
        else
            print_warning "Could not find cluster_domain default to update"
        fi
    else
        print_warning "template.yaml not found at: $TEMPLATE_FILE"
    fi
    
    # Export for other scripts
    export CLUSTER_DOMAIN
}

# Main

main() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       RHDH Demo - Operator Installation                        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_prerequisites
    install_openshift_pipelines
    install_openshift_gitops
    install_rhdh
    install_sealed_secrets
    install_kubeseal
    configure_cluster_domain
    print_summary
    
    print_header "Operators Installed Successfully! 🎉"
    
    echo ""
    echo "Next steps:"
    echo "  1. Create RHDH Backstage instance (if not already done)"
    echo "  2. Run ./setup-secrets.sh to configure credentials"
    echo "  3. Register template in RHDH"
    echo ""
}

# Run main
main "$@"

