# API Reference

This document describes the REST API endpoints provided by ${{values.component_id}}.

## Base URL

| Environment | Base URL |
|-------------|----------|
| Development | `https://${{values.component_id}}-${{values.component_id}}-dev.${{values.cluster_domain}}` |
| Staging | `https://${{values.component_id}}-${{values.component_id}}-staging.${{values.cluster_domain}}` |
| Production | `https://${{values.component_id}}-${{values.component_id}}-prod.${{values.cluster_domain}}` |

---

## Endpoints

### Health Check

Check if the application is running and healthy.

```
GET /health
```

#### Response

```json
{
  "status": "UP",
  "service": "RHDH Demo Application",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | Health status (`UP` or `DOWN`) |
| `service` | string | Service name |
| `timestamp` | string | ISO 8601 timestamp |

#### Example

```bash
curl https://${{values.component_id}}-${{values.component_id}}-dev.${{values.cluster_domain}}/health
```

---

### Readiness Check

Check if the application is ready to receive traffic.

```
GET /ready
```

#### Response

```json
{
  "status": "UP",
  "ready": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | Readiness status |
| `ready` | boolean | Whether the app is ready |

#### Example

```bash
curl https://${{values.component_id}}-${{values.component_id}}-dev.${{values.cluster_domain}}/ready
```

---

### Environment Info

Get the current deployment environment.

```
GET /env
```

#### Response

```json
{
  "environment": "dev"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `environment` | string | Current environment (`dev`, `staging`, or `prod`) |

#### Example

```bash
curl https://${{values.component_id}}-${{values.component_id}}-dev.${{values.cluster_domain}}/env
```

---

## Response Codes

| Code | Description |
|------|-------------|
| `200` | Success |
| `404` | Endpoint not found |
| `500` | Internal server error |

## OpenAPI Specification

The full OpenAPI 3.0 specification is available at:

- [openapi.yaml](https://github.com/${{values.repository_owner}}/${{values.component_id}}/blob/main/api/openapi.yaml)

You can also view it in the Backstage API catalog.

## Rate Limiting

Currently, there are no rate limits applied to these endpoints.

## Authentication

These endpoints are publicly accessible and do not require authentication.

!!! note "Production Consideration"
    In a production environment, you may want to add authentication to sensitive endpoints.

