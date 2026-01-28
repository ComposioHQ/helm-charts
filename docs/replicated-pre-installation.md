# Installation Prerequisites

Please ensure you have the following before installation:

1. Sufficient compute resources for the Composio Helm chart deployment. Check compute requirement docs [docs](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/prerequisites/compute.md).

2. A self-hosted PostgreSQL database instance (Recommended version 17+)

3. Kubernetes Namespace to install Composio Helm chart



# Kubernetes Secrets Configuration

## Create Composio Application Secrets

Replace the placeholder values:

```bash
kubectl create secret generic composio-composio-secrets \
  --from-literal=COMPOSIO_ADMIN_TOKEN=<CREATE_RANDOM_TOKEN-A> \
  --from-literal=ENCRYPTION_KEY=<ENCRYPTION_KEY_FOR_DATABASE> \
  --from-literal=TEMPORAL_TRIGGER_ENCRYPTION_KEY=<ENCRYPTION_KEY_FOR_DATABASE_TEMPORAL> \
  --from-literal=JWT_SECRET=<CREATE_RANDOM_TOKEN-C> \
  --from-literal=DATABASE_HOST=<DATABASE_HOST> \
  --from-literal=DATABASE_PORT=5432 \
  --from-literal=DATABASE_USERNAME=<DATABASE_USER> \
  --from-literal=DATABASE_PASSWORD=<DATABASE_PASSWORD> \
  -n <RELEASE_NAMESPACE>
```

**NOTE**: These secrets are required. The recommended secret name is `composio-composio-secret`. If you want to use another secret name, please reference it in your override values file as `secret.name: <your-custom-secret-name>`.

**CRITICAL**: Please store the following keys securely. If they are lost, **all data will be permanently inaccessible**.

## Sensitive Keys and Secrets
1. **ENCRYPTION_KEY**
   Used by the Composio application for database encryption.
2. **TEMPORAL_TRIGGER_ENCRYPTION_KEY**
   Used by Temporal for database encryption.
3. **COMPOSIO_ADMIN_TOKEN**
   API token for the Composio Apollo application.
4. **JWT_SECRET**
   Secret key used for signing and verifying JWT tokens.
5. **DATABASE_HOST**
   PostgreSQL database host.
6. **DATABASE_PORT**
   PostgreSQL database port.
7. **DATABASE_USERNAME**
   PostgreSQL database username.
8. **DATABASE_PASSWORD**
   PostgreSQL database password.
9. **OPENAI_API_KEY**
   OpenAI API key (optional).

