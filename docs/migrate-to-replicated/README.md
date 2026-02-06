# Migration Guide to Replicated Portal

## Step 1: Database Backup

Ensure you take a backup of all databases required for the Composio stack:

- composiodb
- temporal
- temporal_visibility
- thermosdb

Run the following commands to create backups:

```bash
pg_dump -h <host> -U <user> -Fc composiodb > composiodb.backup
pg_dump -h <host> -U <user> -Fc temporal > temporal.backup
pg_dump -h <host> -U <user> -Fc temporal_visibility > temporal_visibility.backup
pg_dump -h <host> -U <user> -Fc thermosdb > thermosdb.backup
```

**Restore commands for reference:**

```bash
pg_restore -h <host> -U <user> -d composiodb composiodb.backup
pg_restore -h <host> -U <user> -d temporal temporal.backup
pg_restore -h <host> -U <user> -d temporal_visibility temporal_visibility.backup
pg_restore -h <host> -U <user> -d thermosdb thermosdb.backup
```

## Step 2: Secrets Backup

Run the following command to back up your secrets:

```bash
kubectl get secrets -n composio -o yaml > composio-secrets-backup.yaml
```

## Step 3: Replicated Secret Requirements

Replicated requires `composio-composio-secrets` to be created before installation. The following keys are required:

```bash
kubectl create secret generic composio-composio-secrets \
  --from-literal=COMPOSIO_ADMIN_TOKEN=<token> \
  --from-literal=ENCRYPTION_KEY=<key> \
  --from-literal=TEMPORAL_TRIGGER_ENCRYPTION_KEY=<key> \
  --from-literal=JWT_SECRET=<secret> \
  --from-literal=POSTGRES_URL="<url from external-postgres-secret, example: postgresql://<user>:<password>@<host>:<port>/composiodb?sslmode=require>" \
  --from-literal=THERMOS_DATABASE_URL="<url from external-thermos-postgres-secret, example: postgresql://<user>:<password>@<host>:<port>/thermosdb?sslmode=require>" \
  --from-literal=password="<password>" \
  -n <namespace>
```

You can run the following script to generate `composio-composio-secrets`:

**Note:** The command below will also create `REDIS_URL` from `external-redis-secret`. Check the [override.yaml](./override.yaml) value file for reference.

```bash
./migrate.sh -r composio -n "composio"
```

This script will read all secrets created by `secret-setup.sh` and create a new `composio-composio-secrets` with the following mappings:

- `COMPOSIO_ADMIN_TOKEN`: `APOLLO_ADMIN_TOKEN` from `composio-apollo-admin-token`
- `ENCRYPTION_KEY`: `ENCRYPTION_KEY` from `composio-encryption-key`
- `JWT_SECRET`: `JWT_SECRET` from `composio-jwt-secret`
- `POSTGRES_URL`: URL from `external-postgres-secret`
- `REDIS_URL`: URL from `external-redis-secret`
- `TEMPORAL_TRIGGER_ENCRYPTION_KEY`: `TEMPORAL_TRIGGER_ENCRYPTION_KEY` from `composio-temporal-encryption-key`
- `THERMOS_DATABASE_URL`: URL from `external-thermos-postgres-secret`
- `password`: Password from `external-postgres-secret`

## Step 4: Helm Template Pre-flight Check

Ensure you run the Helm template pre-flight check in the Replicated Enterprise portal for validation.

Once secrets are created, refer to the current [override.yaml](./override.yaml) file for Helm override values. Also check [example-override.yaml](./example-override.yaml) for reference.

**Example:**

```bash
helm template composio oci://registry.composio.io/composio-rodent/unstable/composio --version 0.1.40 --values ./overrides-values.yaml -n composio | kubectl preflight -

helm upgrade --install composio oci://registry.composio.io/composio-rodent/unstable/composio --version 0.1.40 --values ./overrides-values.yaml -n composio --debug --timeout 15m
```
