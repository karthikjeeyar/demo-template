#!/bin/bash

# =============================================================================
# RHDH Demo - Cluster Setup Script
# =============================================================================
# This master script runs all setup steps in the correct order:
#   1. Install operators (Tekton, ArgoCD, RHDH, Sealed Secrets)
#   2. Generate sealed secrets
#
# Usage:
#   cp .env.example .env
#   vim .env  # Fill in your credentials
#   ./scripts/setup-cluster.sh
# =============================================================================

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       RHDH Demo - Cluster Setup                               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Install Operators
echo -e "${BLUE}Step 1: Installing Operators...${NC}"
echo ""
"$SCRIPT_DIR/setup-operators.sh"

# Step 2: Generate Sealed Secrets
echo ""
echo -e "${BLUE}Step 2: Generating Sealed Secrets...${NC}"
echo ""
"$SCRIPT_DIR/setup-secrets.sh"

# Step 3: Deploy RHDH Instance (optional)
echo ""
echo -e "${BLUE}Step 3: Deploy RHDH Instance${NC}"
echo ""

# Check if GitHub App is configured
source "$SCRIPT_DIR/../.env" 2>/dev/null || true

if [ -n "$GITHUB_APP_ID" ] && [ -n "$GITHUB_APP_CLIENT_ID" ]; then
    echo "GitHub App configuration detected. Deploying RHDH..."
    "$SCRIPT_DIR/setup-rhdh.sh"
else
    echo "GitHub App not configured in .env - skipping RHDH deployment."
    echo ""
    echo "To deploy RHDH later, add GitHub App credentials to .env and run:"
    echo "  ./scripts/setup-rhdh.sh"
fi

# Done
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Cluster Setup Complete!                                 ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Your cluster is now ready for the RHDH demo!"
echo ""
echo "Next steps:"
echo "  1. Register the template in RHDH:"
echo "     https://github.com/YOUR_ORG/demo-templates/blob/main/template.yaml"
echo "  2. Create an application from the template"
echo ""

