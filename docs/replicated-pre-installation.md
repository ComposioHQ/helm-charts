# Installation Prerequisites

Please ensure you have the following before installation:

1. Sufficient compute resources for the Composio Helm chart deployment. Check compute requirement docs [docs](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/prerequisites/compute.md).

2. A self-hosted PostgreSQL database instance (Recommended version 17+)

3. Kubernetes Namespace to install Composio Helm chart



# Kubernetes Secrets Configuration

## Create Composio Application Secrets

Replace the placeholder values:

Based on your database configured change `sslmode=require` for **POSTGRES_URL** **THERMOS_DATABASE_URL**

```bash
kubectl create secret generic composio-composio-secrets \
  --from-literal=APOLLO_ADMIN_TOKEN=<CREATE_RANDOM_TOKEN-A> \
  --from-literal=ENCRYPTION_KEY=<ENCRYPTION_KEY_FOR_DATABASE> \
  --from-literal=TEMPORAL_TRIGGER_ENCRYPTION_KEY=<ENCRYPTION_KEY_FOR_DATABASE_TEMPORAL> \
  --from-literal=COMPOSIO_API_KEY=<CREATE_RANDOM_TOKEN-B> \
  --from-literal=JWT_SECRET=<CREATE_RANDOM_TOKEN-C> \
  --from-literal=POSTGRES_URL="postgresql://<DATABASE_USER>:<DATABASE_PASSWORD>@<DATABASE_HOST>:5432/composiodb?sslmode=require" \
  --from-literal=THERMOS_DATABASE_URL="postgresql://<DATABASE_USER>:<DATABASE_PASSWORD>@<DATABASE_HOST>:5432/thermosdb?sslmode=require" \
  --from-literal=password="<DATABASE_PASSWORD>" \
  -n <RELEASE_NAMESPACE>
```

**NOTE**: These secrets are required. The recommended secret name is `composio-composio-secret`. If you want to use another secret name, please reference it in your override values file as `secret.name: <your-custom-secret-name>`.

**CRITICAL**: Please store the following keys securely. If they are lost, **all data will be permanently inaccessible**.

## Sensitive Keys and Secrets
1. **ENCRYPTION_KEY**  
   Used by the Composio application for database encryption.
2. **TEMPORAL_TRIGGER_ENCRYPTION_KEY**  
   Used by Temporal for database encryption.
3. **APOLLO_ADMIN_TOKEN**  
   API token for the Composio Apollo application.
4. **COMPOSIO_API_KEY**  
   API key for Composio applications.
5. **JWT_SECRET**  
   Secret key used for signing and verifying JWT tokens.
6. **POSTGRES_URL**  
   Database connection URI for the Composio Apollo database.
7. **THERMOS_DATABASE_URL**  
   Database connection URI for the Composio Thermos database.
8. **OPENAI_API_KEY**  
   OpenAI API key.
9. **password**  
   Database password used by the Composio and Temporal applications.

