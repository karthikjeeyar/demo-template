# ${{values.component_id}}

${{values.description}}

## Overview

This application was created using a **Red Hat Developer Hub software template**. Everything you need to build, test, and deploy is already configured:

- ✅ Source code repository
- ✅ GitOps configuration repository
- ✅ CI/CD pipelines (Tekton)
- ✅ Deployment manifests (Helm)
- ✅ ArgoCD applications for all environments

## Quick Start

### Local Development

```bash
# Clone the repository
git clone https://github.com/${{values.repository_owner}}/${{values.component_id}}.git
cd ${{values.component_id}}

# Install dependencies
yarn install

# Start the development server
yarn start
```

The application will be available at `http://localhost:3000`.

### Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /` | Main application page |
| `GET /health` | Health check (liveness probe) |
| `GET /ready` | Readiness check |
| `GET /env` | Current environment info |

## Environments

| Environment | Namespace | URL |
|-------------|-----------|-----|
| Development | `${{values.component_id}}-dev` | [View in ArgoCD](https://openshift-gitops-server-${{values.argocd_namespace}}.${{values.cluster_domain}}/applications/${{values.component_id}}-dev) |
| Staging | `${{values.component_id}}-staging` | [View in ArgoCD](https://openshift-gitops-server-${{values.argocd_namespace}}.${{values.cluster_domain}}/applications/${{values.component_id}}-staging) |
| Production | `${{values.component_id}}-prod` | [View in ArgoCD](https://openshift-gitops-server-${{values.argocd_namespace}}.${{values.cluster_domain}}/applications/${{values.component_id}}-prod) |

## Repositories

| Repository | Purpose |
|------------|---------|
| [Source Code](https://github.com/${{values.repository_owner}}/${{values.component_id}}) | Application source code |
| [GitOps](https://github.com/${{values.repository_owner}}/${{values.component_id}}-gitops) | Kubernetes manifests and ArgoCD configs |

## Making Changes

1. **Edit code** in the source repository
2. **Push to main** branch
3. **Tekton pipeline** automatically builds and deploys to DEV
4. **Promote to staging** using the promote pipeline
5. **Promote to production** after validation

!!! tip "GitOps Workflow"
    All deployments are managed through Git. Changes to the GitOps repository automatically sync to the cluster via ArgoCD.

## Support

- **Owner**: ${{values.owner}}
- **Documentation**: You're reading it!
- **API Reference**: See the [API docs](api.md)

