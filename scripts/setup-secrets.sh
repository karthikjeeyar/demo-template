#!/bin/bash

# =============================================================================
# Sealed Secrets Setup Script
# =============================================================================
# This script generates sealed secrets for the RHDH demo:
#   1. Verifies cluster login
#   2. Verifies kubeseal CLI is installed
#   3. Generates sealed secrets for git, registry, and ArgoCD credentials
#   4. Updates Values.yaml with sealed secrets
#
# PREREQUISITES:
#   - Run ./setup-operators.sh first to install Sealed Secrets controller
#
# ENVIRONMENT VARIABLES:
#   Create a .env file in the project root:
#     cp .env.example .env
#     # Edit .env with your values
#     ./scripts/setup-secrets.sh
#
#   Supported variables:
#     GIT_USERNAME, GIT_TOKEN, REGISTRY_SERVER, REGISTRY_USERNAME,
#     REGISTRY_PASSWORD, ARGOCD_NAMESPACE, ARGOCD_PASSWORD
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


# =============================================================================
# Helper Functions
# =============================================================================

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

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    local is_secret="$4"
    
    # Check if variable is already set (e.g., from .env file)
    local current_value="${!var_name}"
    if [ -n "$current_value" ]; then
        if [ "$is_secret" = "true" ]; then
            print_success "$prompt: [loaded from .env]"
        else
            print_success "$prompt: $current_value [from .env]"
        fi
        return
    fi
    
    if [ -n "$default" ]; then
        prompt="$prompt [$default]"
    fi
    
    if [ "$is_secret" = "true" ]; then
        read -s -p "$prompt: " value
        echo ""
    else
        read -p "$prompt: " value
    fi
    
    if [ -z "$value" ] && [ -n "$default" ]; then
        value="$default"
    fi
    
    eval "$var_name='$value'"
}

# Load environment variables from .env file if it exists
load_env_file() {
    local env_file="${1:-.env}"
    
    if [ -f "$env_file" ]; then
        print_info "Loading variables from $env_file..."
        
        # Read .env file line by line
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty lines and comments
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            
            # Only process lines that contain = and start with a valid variable name
            if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                
                # Remove surrounding quotes from value
                value="${value%\"}"
                value="${value#\"}"
                value="${value%\'}"
                value="${value#\'}"
                
                # Export the variable
                if [ -n "$key" ]; then
                    export "$key=$value"
                    print_success "  Loaded: $key"
                fi
            fi
        done < "$env_file"
        
        echo ""
    else
        print_warning ".env file not found at: $env_file"
        print_info "Create one with: cp .env.example .env"
        echo ""
    fi
}

# =============================================================================
# Step 1: Verify Cluster Login
# =============================================================================

check_cluster_login() {
    print_header "Step 1: Verifying Cluster Login"
    
    if ! command -v oc &> /dev/null; then
        print_error "OpenShift CLI (oc) not found. Please install it first."
        echo "  brew install openshift-cli"
        exit 1
    fi
    
    if ! oc whoami &> /dev/null; then
        print_error "Not logged into OpenShift cluster."
        echo ""
        echo "Please login first:"
        echo "  oc login --server=<cluster-api-url> --token=<token>"
        echo ""
        echo "Or use username/password:"
        echo "  oc login --server=<cluster-api-url> -u <username> -p <password>"
        exit 1
    fi
    
    CURRENT_USER=$(oc whoami)
    CURRENT_CLUSTER=$(oc whoami --show-server)
    
    print_success "Logged in as: $CURRENT_USER"
    print_success "Cluster: $CURRENT_CLUSTER"
}

# =============================================================================
# Step 2: Verify Sealed Secrets Controller
# =============================================================================

verify_sealed_secrets_controller() {
    print_header "Step 2: Verifying Sealed Secrets Controller"
    
    # Check if installed
    if ! oc get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
        print_error "Sealed Secrets controller not found!"
        echo ""
        echo "Please run setup-operators.sh first to install the controller:"
        echo "  ./setup-operators.sh"
        exit 1
    fi
    
    print_success "Sealed Secrets controller is installed"
}

# =============================================================================
# Step 3: Verify kubeseal CLI
# =============================================================================

verify_kubeseal() {
    print_header "Step 3: Verifying kubeseal CLI"
    
    if ! command -v kubeseal &> /dev/null; then
        print_error "kubeseal CLI not found!"
        echo ""
        echo "Please run setup-operators.sh first to install kubeseal:"
        echo "  ./setup-operators.sh"
        exit 1
    fi
    
    KUBESEAL_VERSION=$(kubeseal --version 2>/dev/null || echo "unknown")
    print_success "kubeseal installed: $KUBESEAL_VERSION"
}

# =============================================================================
# Step 4: Collect Credentials
# =============================================================================

collect_credentials() {
    print_header "Step 4: Collecting Credentials"
    
    echo ""
    echo "Please provide the following credentials:"
    echo ""
    
    # Git credentials
    echo -e "${YELLOW}--- Git Credentials (GitHub) ---${NC}"
    prompt_input "GitHub username" GIT_USERNAME ""
    prompt_input "GitHub Personal Access Token (PAT)" GIT_TOKEN "" "true"
    
    echo ""
    
    # Registry credentials
    echo -e "${YELLOW}--- Registry Credentials (Quay.io) ---${NC}"
    prompt_input "Registry server" REGISTRY_SERVER "quay.io"
    prompt_input "Registry username" REGISTRY_USERNAME ""
    prompt_input "Registry password/token" REGISTRY_PASSWORD "" "true"
    
    echo ""
    
    # ArgoCD credentials
    echo -e "${YELLOW}--- ArgoCD Credentials ---${NC}"
    prompt_input "ArgoCD namespace" ARGOCD_NAMESPACE "openshift-gitops"
    
    # Try to get ArgoCD password automatically from multiple possible sources
    print_info "Attempting to retrieve ArgoCD admin password..."
    ARGOCD_PASSWORD=""
    
    # Try 1: argocd-initial-admin-secret (standard ArgoCD)
    if [ -z "$ARGOCD_PASSWORD" ]; then
        ARGOCD_PASSWORD=$(oc get secret argocd-initial-admin-secret -n "$ARGOCD_NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d) || true
        [ -n "$ARGOCD_PASSWORD" ] && print_success "Password retrieved from argocd-initial-admin-secret"
    fi
    
    # Try 2: openshift-gitops-cluster with admin.password key
    if [ -z "$ARGOCD_PASSWORD" ]; then
        ARGOCD_PASSWORD=$(oc get secret openshift-gitops-cluster -n "$ARGOCD_NAMESPACE" -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d) || true
        [ -n "$ARGOCD_PASSWORD" ] && print_success "Password retrieved from openshift-gitops-cluster"
    fi
    
    # Try 3: <namespace>-cluster secret (named after the namespace)
    if [ -z "$ARGOCD_PASSWORD" ]; then
        ARGOCD_PASSWORD=$(oc get secret "${ARGOCD_NAMESPACE}-cluster" -n "$ARGOCD_NAMESPACE" -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d) || true
        [ -n "$ARGOCD_PASSWORD" ] && print_success "Password retrieved from ${ARGOCD_NAMESPACE}-cluster"
    fi
    
    # Fallback: prompt user
    if [ -z "$ARGOCD_PASSWORD" ]; then
        print_warning "Could not retrieve ArgoCD password automatically"
        print_info "Available secrets in $ARGOCD_NAMESPACE namespace:"
        oc get secrets -n "$ARGOCD_NAMESPACE" 2>/dev/null | grep -E "(argocd|gitops|cluster)" || echo "  (none found)"
        echo ""
        prompt_input "ArgoCD admin password" ARGOCD_PASSWORD "" "true"
    fi
    
    echo ""
    print_success "All credentials collected"
}

# =============================================================================
# Step 5: Generate Sealed Secrets
# =============================================================================

generate_sealed_secrets() {
    print_header "Step 5: Generating Sealed Secrets"
    
    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    echo ""
    print_info "Using cluster-wide scope (secrets will work in any namespace)"
    echo ""
    
    # --- Git Credentials ---
    print_info "Generating sealed git credentials..."
    
    cat > "$TEMP_DIR/git-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: git-credentials
type: Opaque
stringData:
  username: "$GIT_USERNAME"
  token: "$GIT_TOKEN"
EOF
    
    # Use --scope cluster-wide so secrets work in any namespace
    kubeseal --format yaml --scope cluster-wide < "$TEMP_DIR/git-secret.yaml" > "$TEMP_DIR/sealed-git.yaml"
    
    # Extract encrypted data from spec.encryptedData section
    # Format: "    username: AgXXX..." (indented with spaces)
    GIT_SEALED_USERNAME=$(sed -n '/encryptedData:/,/template:/p' "$TEMP_DIR/sealed-git.yaml" | grep "username:" | sed 's/.*username: //')
    GIT_SEALED_TOKEN=$(sed -n '/encryptedData:/,/template:/p' "$TEMP_DIR/sealed-git.yaml" | grep "token:" | sed 's/.*token: //')
    
    print_success "Git credentials sealed"
    
    # --- Registry Credentials ---
    print_info "Generating sealed registry credentials..."
    
    oc create secret docker-registry registry-credentials \
        --docker-server="$REGISTRY_SERVER" \
        --docker-username="$REGISTRY_USERNAME" \
        --docker-password="$REGISTRY_PASSWORD" \
        --dry-run=client -o yaml > "$TEMP_DIR/registry-secret.yaml"
    
    # Use --scope cluster-wide so secrets work in any namespace
    kubeseal --format yaml --scope cluster-wide < "$TEMP_DIR/registry-secret.yaml" > "$TEMP_DIR/sealed-registry.yaml"
    
    # Extract encrypted dockerconfigjson
    REGISTRY_SEALED=$(sed -n '/encryptedData:/,/template:/p' "$TEMP_DIR/sealed-registry.yaml" | grep ".dockerconfigjson:" | sed 's/.*\.dockerconfigjson: //')
    
    print_success "Registry credentials sealed"
    
    # --- ArgoCD Credentials ---
    print_info "Generating sealed ArgoCD credentials..."
    
    cat > "$TEMP_DIR/argocd-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: argocd-credentials
type: Opaque
stringData:
  username: "admin"
  password: "$ARGOCD_PASSWORD"
EOF
    
    # Use --scope cluster-wide so secrets work in any namespace
    kubeseal --format yaml --scope cluster-wide < "$TEMP_DIR/argocd-secret.yaml" > "$TEMP_DIR/sealed-argocd.yaml"
    
    # Extract encrypted data from spec.encryptedData section
    ARGOCD_SEALED_USERNAME=$(sed -n '/encryptedData:/,/template:/p' "$TEMP_DIR/sealed-argocd.yaml" | grep "username:" | sed 's/.*username: //')
    ARGOCD_SEALED_PASSWORD=$(sed -n '/encryptedData:/,/template:/p' "$TEMP_DIR/sealed-argocd.yaml" | grep "password:" | sed 's/.*password: //')
    
    print_success "ArgoCD credentials sealed"
    
    # ==========================================================================
    # Validate extracted values
    # ==========================================================================
    
    echo ""
    print_info "Validating extracted sealed values..."
    
    VALIDATION_FAILED=false
    
    if [ -z "$REGISTRY_SEALED" ]; then
        print_error "Registry sealed value is empty"
        VALIDATION_FAILED=true
    else
        print_success "Registry: extracted (${#REGISTRY_SEALED} chars)"
    fi
    
    if [ -z "$GIT_SEALED_USERNAME" ]; then
        print_error "Git username sealed value is empty"
        VALIDATION_FAILED=true
    else
        print_success "Git username: extracted (${#GIT_SEALED_USERNAME} chars)"
    fi
    
    if [ -z "$GIT_SEALED_TOKEN" ]; then
        print_error "Git token sealed value is empty"
        VALIDATION_FAILED=true
    else
        print_success "Git token: extracted (${#GIT_SEALED_TOKEN} chars)"
    fi
    
    if [ -z "$ARGOCD_SEALED_USERNAME" ]; then
        print_error "ArgoCD username sealed value is empty"
        VALIDATION_FAILED=true
    else
        print_success "ArgoCD username: extracted (${#ARGOCD_SEALED_USERNAME} chars)"
    fi
    
    if [ -z "$ARGOCD_SEALED_PASSWORD" ]; then
        print_error "ArgoCD password sealed value is empty"
        VALIDATION_FAILED=true
    else
        print_success "ArgoCD password: extracted (${#ARGOCD_SEALED_PASSWORD} chars)"
    fi
    
    if [ "$VALIDATION_FAILED" = true ]; then
        echo ""
        print_warning "Some values could not be extracted. Showing sealed secret files for manual extraction:"
        echo ""
        echo "=== sealed-git.yaml ==="
        cat "$TEMP_DIR/sealed-git.yaml"
        echo ""
        echo "=== sealed-registry.yaml ==="
        cat "$TEMP_DIR/sealed-registry.yaml"
        echo ""
        echo "=== sealed-argocd.yaml ==="
        cat "$TEMP_DIR/sealed-argocd.yaml"
        echo ""
        print_info "Copy the values from 'encryptedData:' section manually"
    fi
    
    # ==========================================================================
    # Update Values.yaml
    # ==========================================================================
    
    print_header "Step 6: Updating Values.yaml"
    
    # Determine Values.yaml path
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VALUES_FILE="${SCRIPT_DIR}/../manifests/helm/build/Values.yaml"
    
    # Create the new sealedSecrets section
    SEALED_SECRETS_CONTENT=$(cat << INNEREOF
# ===========================================
# Sealed Secrets Configuration
# ===========================================
# Generated by setup-secrets.sh on $(date)

sealedSecrets:
  # Registry credentials (docker config json)
  registry:
    enabled: true
    secretName: registry-credentials
    encryptedData: "$REGISTRY_SEALED"

  # Git credentials (username + token)
  git:
    enabled: true
    secretName: git-credentials
    encryptedData: |
      username: $GIT_SEALED_USERNAME
      token: $GIT_SEALED_TOKEN

  # ArgoCD credentials (username + password)
  argocd:
    enabled: true
    secretName: argocd-credentials
    encryptedData: |
      username: $ARGOCD_SEALED_USERNAME
      password: $ARGOCD_SEALED_PASSWORD
INNEREOF
)
    
    # Check if Values.yaml exists
    if [ -f "$VALUES_FILE" ]; then
        print_info "Updating $VALUES_FILE..."
        
        # Create backup
        cp "$VALUES_FILE" "${VALUES_FILE}.bak"
        print_info "Backup saved to ${VALUES_FILE}.bak"
        
        # Remove existing sealedSecrets section and everything after it
        # Then append the new section
        if grep -q "^sealedSecrets:" "$VALUES_FILE"; then
            # Find line number of sealedSecrets: and keep everything before it
            SEALED_LINE=$(grep -n "^sealedSecrets:" "$VALUES_FILE" | head -1 | cut -d: -f1)
            # Also check for the comment header before sealedSecrets
            HEADER_LINE=$(grep -n "^# .*Sealed Secrets" "$VALUES_FILE" | tail -1 | cut -d: -f1)
            
            if [ -n "$HEADER_LINE" ] && [ "$HEADER_LINE" -lt "$SEALED_LINE" ]; then
                # Use the header line as the cut point
                head -n $((HEADER_LINE - 1)) "$VALUES_FILE" > "${VALUES_FILE}.tmp"
            else
                # Use the sealedSecrets line as the cut point
                head -n $((SEALED_LINE - 1)) "$VALUES_FILE" > "${VALUES_FILE}.tmp"
            fi
            
            # Append the new sealed secrets section
            echo "" >> "${VALUES_FILE}.tmp"
            echo "$SEALED_SECRETS_CONTENT" >> "${VALUES_FILE}.tmp"
            
            # Replace the original file
            mv "${VALUES_FILE}.tmp" "$VALUES_FILE"
            print_success "Updated sealedSecrets section in Values.yaml"
        else
            # sealedSecrets section doesn't exist, append it
            echo "" >> "$VALUES_FILE"
            echo "$SEALED_SECRETS_CONTENT" >> "$VALUES_FILE"
            print_success "Added sealedSecrets section to Values.yaml"
        fi
        
        # Show the updated sealedSecrets section
        echo ""
        echo -e "${GREEN}Updated sealedSecrets configuration:${NC}"
        echo "============================================="
        echo "$SEALED_SECRETS_CONTENT"
        echo "============================================="
    else
        # Fallback: save to separate file
        print_warning "Values.yaml not found at: $VALUES_FILE"
        print_info "Saving to sealed-secrets-values.yaml instead..."
        
        OUTPUT_FILE="sealed-secrets-values.yaml"
        echo "$SEALED_SECRETS_CONTENT" > "$OUTPUT_FILE"
        
        print_success "Configuration saved to: $OUTPUT_FILE"
        echo ""
        echo -e "${GREEN}Generated configuration:${NC}"
        echo "============================================="
        cat "$OUTPUT_FILE"
        echo "============================================="
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       RHDH Demo - Sealed Secrets Setup                         ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Determine script directory and project root
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    
    # Load .env file from project root if present
    load_env_file "$PROJECT_ROOT/.env"
    
    check_cluster_login
    verify_sealed_secrets_controller
    verify_kubeseal
    collect_credentials
    generate_sealed_secrets
    
    print_header "Sealed Secrets Generated! 🎉"
    
    echo ""
    echo "Next steps:"
    echo "  1. Review the updated Values.yaml (backup saved as .bak)"
    echo "  2. Commit and push your gitops repository:"
    echo "       git add manifests/helm/build/Values.yaml"
    echo "       git commit -m 'Update sealed secrets configuration'"
    echo "       git push"
    echo "  3. ArgoCD will sync and create the secrets"
    echo "  4. Start using the demo!"
    echo ""
    echo -e "${BLUE}Tip:${NC} To re-run with the same credentials, edit the .env file:"
    echo "       vim $PROJECT_ROOT/.env"
    echo ""
}

# Run main
main "$@"

