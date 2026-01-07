
Before installing the Helm chart, create the required Kubernetes secrets in the `composio` namespace. These secrets provide credentials and encryption keys needed by the platform and its dependencies.

---

## Database Setup

### Create PostgreSQL Databases and Users

Below are the SQL queries for self hosted postgres. Check below docs for cloud managed database 

1. [AWS RDS PostgreSQL](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/aws-init.sql)
2. [GCP Cloud SQL PostgreSQL](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/gcp-init.sql)
3. [Azure Flexible Server PostgreSQL](https://github.com/ComposioHQ/helm-charts/blob/release-stable/docs/azure-init.sql
)

> **Kindly update the DATABASE_PASSWORD for composio user**

```sql
CREATE USER composio WITH PASSWORD '<DATABASE_PASSWORD>';

-- Create databases
CREATE DATABASE composiodb OWNER composio;
CREATE DATABASE temporal OWNER composio;
CREATE DATABASE temporal_visibility OWNER composio;
CREATE DATABASE thermosdb OWNER composio;

-- Grant privileges on thermosdb
\c thermosdb
GRANT ALL PRIVILEGES ON DATABASE thermosdb TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;

-- Grant privileges on composiodb
\c composiodb
GRANT ALL PRIVILEGES ON DATABASE composiodb TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;

-- Grant privileges on temporal
\c temporal
GRANT ALL PRIVILEGES ON DATABASE temporal TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;

-- Grant privileges on temporal_visibility
\c temporal_visibility
GRANT ALL PRIVILEGES ON DATABASE temporal_visibility TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;

-- Grant database creation privilege
ALTER ROLE composio CREATEDB;
```

---

## Kubernetes Secrets Configuration

### Step 1: Create Composio Application Secrets

Replace the placeholder values with your actual tokens, keys, and connection strings:


```bash
kubectl create secret generic composio-composio-secrets \
  --from-literal=APOLLO_ADMIN_TOKEN=dummy-token \
  --from-literal=ENCRYPTION_KEY=dummy-key \
  --from-literal=TEMPORAL_TRIGGER_ENCRYPTION_KEY=dummy-key \
  --from-literal=COMPOSIO_API_KEY=dummy-key \
  --from-literal=JWT_SECRET=dummy-key \
  --from-literal=POSTGRES_URL=postgresql://composio:<DATABASE_PASSWORD>@<DATABASE_HOST>:5432/composiodb?sslmode=disable \
  --from-literal=THERMOS_DATABASE_URL=postgresql://composio:<DATABASE_PASSWORD>@<DATABASE_HOST>:5432/thermosdb?sslmode=disable \
  --from-literal=OPENAI_API_KEY=dummy-key \
  --from-literal=password=<DATABASE_PASSWORD> \
  -n composio
```
