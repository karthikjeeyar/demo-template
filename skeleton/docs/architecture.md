# Architecture

## System Overview

This application follows a GitOps deployment model with three environments: Development, Staging, and Production.

```mermaid
flowchart LR
    subgraph Development
        DEV[Developer]
        SRC[Source Repo]
        DEV -->|Push Code| SRC
    end

    subgraph CI[CI Pipeline - Tekton]
        BUILD[Build]
        TEST[Test]
        IMAGE[Build Image]
        SRC -->|Webhook| BUILD
        BUILD --> TEST
        TEST --> IMAGE
    end

    subgraph Registry
        QUAY[(Container Registry)]
        IMAGE -->|Push| QUAY
    end

    subgraph GitOps[GitOps Repository]
        GITOPS[Helm Values]
        IMAGE -->|Update Tag| GITOPS
    end

    subgraph CD[CD - ArgoCD]
        ARGO[ArgoCD]
        GITOPS -->|Sync| ARGO
    end

    subgraph Environments
        DEVNS[DEV Namespace]
        STAGNS[Staging Namespace]
        PRODNS[PROD Namespace]
        ARGO -->|Deploy| DEVNS
        ARGO -->|Promote| STAGNS
        ARGO -->|Promote| PRODNS
    end
```

## Deployment Flow

### 1. Code Commit

When a developer pushes code to the source repository:

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant TK as Tekton
    participant REG as Registry
    participant GO as GitOps Repo
    participant ARGO as ArgoCD
    participant K8S as Kubernetes

    Dev->>GH: Push commit
    GH->>TK: Webhook trigger
    TK->>TK: Build & Test
    TK->>REG: Push image
    TK->>GO: Update image tag
    GO->>ARGO: Sync notification
    ARGO->>K8S: Deploy to DEV
```

### 2. Environment Promotion

```mermaid
flowchart LR
    DEV[DEV] -->|Promote Pipeline| STAGING[Staging]
    STAGING -->|Promote Pipeline| PROD[Production]
    
    style DEV fill:#0066CC,color:#fff
    style STAGING fill:#F0AB00,color:#000
    style PROD fill:#3E8635,color:#fff
```

## Component Architecture

```mermaid
graph TB
    subgraph Pod
        APP[Node.js App]
        APP -->|:8080| SVC
    end

    subgraph Services
        SVC[ClusterIP Service]
        ROUTE[OpenShift Route]
        SVC --> ROUTE
    end

    subgraph Probes
        HEALTH[/health]
        READY[/ready]
        APP --> HEALTH
        APP --> READY
    end

    ROUTE -->|HTTPS| USER[User]
```

## Technology Stack

| Layer | Technology |
|-------|------------|
| **Runtime** | Node.js |
| **Web Framework** | Express |
| **Container** | Podman/Docker |
| **Orchestration** | Kubernetes/OpenShift |
| **CI** | Tekton Pipelines |
| **CD** | ArgoCD |
| **GitOps** | Helm + Kustomize |
| **Registry** | Quay / OpenShift Internal |

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | `8080` |
| `NODE_ENV` | Node environment | `production` |
| `APP_ENV` | Application environment | `dev` |

### Resource Allocation

| Environment | CPU Request | CPU Limit | Memory Request | Memory Limit | Replicas |
|-------------|-------------|-----------|----------------|--------------|----------|
| DEV | 100m | 500m | 128Mi | 512Mi | 1 |
| Staging | 200m | 1000m | 256Mi | 1Gi | 2 |
| Production | 500m | 2000m | 512Mi | 2Gi | 3+ |

## Security

- TLS termination at the route level
- Network policies isolate namespaces
- Service accounts with minimal permissions
- Image scanning via Quay (if enabled)
- GitOps ensures audit trail for all changes

