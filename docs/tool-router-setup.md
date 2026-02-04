# Tool Router Setup (Weaviate)

Tool router requires Weaviate as its vector database. Both `weaviate.enabled` and `apollo.search.enabled` must be set to `true`.

## Prerequisites

- A running Composio deployment
- An OpenAI API key configured in `composio-composio-secrets` (used for embeddings)

## Setup

Add the following to your `overwrite-values.yaml`:

```yaml
weaviate:
  enabled: true

openAI:
  enabled: true

apollo:
  search:
    enabled: true
```

Then apply:

```bash
helm upgrade composio composio/ -f overwrite-values.yaml -n composio
```

## Verify

```bash
# Check Weaviate is running
kubectl get pods -n composio -l app.kubernetes.io/component=weaviate

# Confirm Apollo has Weaviate env vars
kubectl exec -n composio deploy/composio-apollo -- env | grep WEAVIATE
```

You should see `WEAVIATE_URL`, `WEAVIATE_HOST`, `WEAVIATE_PORT`, and `WEAVIATE_COLLECTION` set in Apollo config map.

## Resource Requirements

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 1 core | 2 cores |
| Memory | 2 GiB | 4 GiB |

## Production Notes

- Set `weaviate.auth.anonymousAccess` to `"false"` and configure `apollo.search.weaviate.apiKey`
- Enable persistence (`weaviate.persistence.enabled: true`) to survive pod restarts
- Ensure your OpenAI API key is present in the `composio-composio-secrets` secret
