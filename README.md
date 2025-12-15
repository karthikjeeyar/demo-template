# RHDH Software Template Demo

A complete software template for Red Hat Developer Hub demonstrating automated CI/CD with GitOps.

## What This Repository Contains

```
demo-templates/
├── template.yaml          # Backstage software template definition
├── skeleton/              # Application source code template
│   ├── server.js          # Node.js Express application
│   ├── public/            # Frontend (HTML, CSS, JS)
│   ├── docs/              # TechDocs documentation
│   ├── api/               # OpenAPI specification
│   └── catalog-info.yaml  # Backstage catalog entity
└── manifests/
    ├── helm/
    │   ├── app/           # Application Helm chart (deployment, service, route)
    │   └── build/         # CI/CD Helm chart (pipelines, triggers, tasks)
    └── argocd/            # ArgoCD Application manifests (dev, staging, prod
    ├── rhdh/              # RHDH Application manifests
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
- GitHub account + Personal Access Token
- Container registry (Quay.io)

### 2. Setup Cluster

```bash
# Configure credentials
cp .env.example .env
vim .env

# Install operators and configure secrets
./scripts/setup-cluster.sh
```

### 3. Register Template in RHDH

Add this URL to your RHDH catalog:
```
https://github.com/YOUR_ORG/demo-templates/blob/main/template.yaml
```

### 4. Create an Application

1. Open RHDH → **Create** → Select the template
2. Fill in the form → Click **Create**
3. Application deploys to DEV automatically

### 5. Promote to Environments

```bash
# Push to main → auto-deploys to DEV
git push origin main

# Tag for staging
git tag staging-v1 && git push origin staging-v1

# Tag for production
git tag v1.0.0 && git push origin v1.0.0
```

## Features

| Feature | Description |
|---------|-------------|
| **TechDocs** | Auto-generated documentation in RHDH |
| **API Catalog** | OpenAPI spec registered in Backstage |
| **Tekton CI/CD** | Automated build and promote pipelines |
| **ArgoCD GitOps** | Declarative deployments to 3 environments |
| **Sealed Secrets** | Encrypted credentials in Git |
| **OpenShift Support** | Works with internal registry or Quay |


## License

Apache License 2.0
