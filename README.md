# RHDH Software Template Demo

A complete software template for Red Hat Developer Hub demonstrating automated CI/CD with GitOps.

## What This Repository Contains

```
demo-templates/
├── template.yaml              # Backstage software template definition
├── skeleton/                  # Application source code template
│   ├── server.js              # Node.js Express application
│   ├── public/                # Frontend (HTML, CSS, JS)
│   ├── docs/                  # TechDocs documentation
│   ├── api/                   # OpenAPI specification
│   └── catalog-info.yaml      # Backstage catalog entity
├── manifests/
│   ├── helm/
│   │   ├── app/               # Application Helm chart (deployment, service, route)
│   │   └── build/             # CI/CD Helm chart (pipelines, triggers, tasks)
│   ├── argocd/                # ArgoCD Application manifests (dev, staging, prod)
│   └── rhdh/                  # RHDH instance configuration
└── scripts/                   # Setup and configuration scripts
    ├── setup-cluster.sh       # Main setup script
    ├── setup-operators.sh     # Operator installation
    ├── setup-secrets.sh       # Sealed secrets generation
    └── setup-rhdh.sh          # RHDH instance deployment
```

## How It Works

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    RHDH     │────▶│   GitHub    │────▶│   Tekton    │────▶│   ArgoCD    │
│  Template   │     │    Repos    │     │  Pipelines  │     │   GitOps    │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                          │                    │                    │
                          ▼                    ▼                    ▼
                    Source Code +         Build & Push         Deploy to
                    GitOps Config         Container Image      OpenShift
```

**When you use this template, it creates:**
- **Source Repository** - Your application code
- **GitOps Repository** - Kubernetes manifests managed by ArgoCD

## Quick Start

### 1. Prerequisites

- OpenShift cluster with `oc` CLI access
- GitHub account with a [GitHub App](#2-create-github-app) + PAT (for pipelines)
- Container registry (Quay.io)

### 2. Create GitHub App

RHDH requires a GitHub App for authentication and integration.

1. **Create a GitHub App** at `https://github.com/settings/apps/new`:
   - **App name**: `RHDH Demo` (or your preferred name)
   - **Homepage URL**: `https://backstage-demo-rhdh.apps.YOUR_CLUSTER_DOMAIN`
   - **Callback URL**: `https://backstage-demo-rhdh.apps.YOUR_CLUSTER_DOMAIN/api/auth/github/handler/frame`
   - **Webhook URL**: Create one at [smee.io](https://smee.io)
   - **Permissions**: 
     - Repository: `Read & Write` (Contents, Pull requests)
     - Organization: `Read` (Members)

2. **After creating the app**:
   - Note the `App ID` and `Client ID`
   - Generate a `Client Secret`
   - Generate and download the `Private Key` (.pem file)

3. **Place the private key in the project root** (it's gitignored):
   ```bash
   mv ~/Downloads/your-app-name.*.pem ./github-app-private-key.pem
   ```

### 3. Configure Environment

```bash
# Copy the example config
cp .env.example .env

# Edit and fill in your credentials (see .env.example for all required values)
vim .env
```

### 4. Run Setup

```bash
# Install operators, configure secrets, and deploy RHDH
./scripts/setup-cluster.sh
```

This script will:
- Install OpenShift Pipelines, GitOps, RHDH operators
- Install Sealed Secrets controller
- Deploy RHDH instance with your GitHub App
- Output the RHDH URL and GitHub App callback URLs

### 5. Register Template in RHDH

After setup completes, register this template in your RHDH catalog:

1. Open RHDH → **Catalog** → **Register Existing Component**
2. Enter the template URL from your GitHub repository

### 6. Create an Application

1. Open RHDH → **Create** → Select the template
2. Fill in the form → Click **Create**
3. Application deploys to DEV automatically

### 7. Promote to Environments

```bash
# Push to main → auto-deploys to DEV
git push origin main

# Tag for staging
git tag staging-v1 && git push origin staging-v1

# Tag for production (requires manual sync in ArgoCD)
git tag v1.0.0 && git push origin v1.0.0
```

## Features

| Feature | Description |
|---------|-------------|
| **TechDocs** | Auto-generated documentation in RHDH |
| **API Catalog** | OpenAPI spec registered in Backstage |
| **Tekton CI/CD** | Automated build and promote pipelines |
| **ArgoCD GitOps** | Declarative deployments to 3 environments |
| **Sealed Secrets** | Encrypted credentials safe to commit |
| **GitHub App** | Secure authentication and integration |


## License

Apache License 2.0
