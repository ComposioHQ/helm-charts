# Redis Sentinel Setup for Apollo

This guide explains how to run Apollo with Redis Sentinel after the Hermes Redis Sentinel support landed.

Use this guide if you want one of these setups:

1. External Redis with a single direct `REDIS_URL`
2. External Redis with Sentinel-managed failover
3. Bundled Bitnami Redis in replication mode with Sentinel

## How Apollo behaves

Apollo supports two Redis connection modes:

- Direct mode: the chart sets `REDIS_URL`
- Sentinel mode: the chart sets `REDIS_SENTINEL_HOSTS`, `REDIS_SENTINEL_MASTER_NAME`, and optional auth/TLS env vars, and does **not** set `REDIS_URL`

In Sentinel mode, Hermes expects these env vars:

- `REDIS_SENTINEL_HOSTS`
- `REDIS_SENTINEL_MASTER_NAME`
- `REDIS_SENTINEL_PASSWORD` (optional)
- `REDIS_USERNAME` (optional)
- `REDIS_PASSWORD` (optional)
- `REDIS_DB` (optional)
- `REDIS_TLS_ENABLED`

## Prerequisites

- A Kubernetes cluster with access to the namespace where Composio is installed
- `helm` and `kubectl`
- A Helm values override file
- A decision on whether you are using external Redis or the bundled Redis subchart

## Option 1: External Redis with a direct URL

Use this when your Redis provider gives you a single endpoint and you do not need Sentinel failover.

### 1. Create the Redis secret

Example:

```bash
kubectl create secret generic composio-composio-secrets \
  -n composio \
  --from-literal=REDIS_URL="redis://:password@redis.example.com:6379"
```

### 2. Set Helm values

```yaml
externalRedis:
  enabled: true
  secretRef: composio-composio-secrets
  key: REDIS_URL

redis:
  enabled: false
```

### 3. Upgrade the release

```bash
helm upgrade <release-name> ./composio -n <namespace> -f values-override.yaml
```

### 4. Verify Apollo

```bash
kubectl exec deploy/<release-name>-apollo -n <namespace> -- printenv | grep '^REDIS'
```

You should see `REDIS_URL`.

## Option 2: External Redis with Sentinel

Use this when your provider exposes Sentinel nodes and a master set name.

### 1. Gather the required Sentinel information

You need:

- Sentinel hosts, as a comma-separated `host:port` list
- Sentinel master set name
- Whether Redis/Sentinel connections require TLS
- Optional Redis DB index
- Optional Redis username/password
- Optional Sentinel password

### 2. Create the auth secret

Only include the keys your provider actually requires.

Example:

```bash
kubectl create secret generic redis-sentinel-credentials \
  -n composio \
  --from-literal=REDIS_USERNAME="default" \
  --from-literal=REDIS_PASSWORD="your-master-password" \
  --from-literal=REDIS_SENTINEL_PASSWORD="your-sentinel-password"
```

### 3. Set Helm values

```yaml
externalRedis:
  enabled: true
  secretRef: composio-composio-secrets
  sentinel:
    enabled: true
    hosts: "sentinel-0.redis.example.com:26379,sentinel-1.redis.example.com:26379,sentinel-2.redis.example.com:26379"
    masterName: "mymaster"
    tlsEnabled: true
    db: "0"
    secretRef: redis-sentinel-credentials
    usernameKey: REDIS_USERNAME
    passwordKey: REDIS_PASSWORD
    sentinelPasswordKey: REDIS_SENTINEL_PASSWORD

redis:
  enabled: false
```

### 4. Important rules

- `externalRedis.sentinel.enabled` switches Apollo into Sentinel mode
- `externalRedis.sentinel.hosts` and `externalRedis.sentinel.masterName` are required
- `externalRedis.key` / `REDIS_URL` is ignored in Sentinel mode
- `externalRedis.sentinel.secretRef` defaults to `externalRedis.secretRef` if you leave it empty
- Preflight checks validate whichever Sentinel secret keys you configure

### 5. Upgrade the release

```bash
helm upgrade <release-name> ./composio -n <namespace> -f values-override.yaml
```

### 6. Verify Apollo

```bash
kubectl exec deploy/<release-name>-apollo -n <namespace> -- printenv | grep '^REDIS'
```

You should see the Sentinel env vars and should **not** see `REDIS_URL`.

## Option 3: Bundled Bitnami Redis with Sentinel

Use this when you want the Helm chart to manage Redis for you, but still want Sentinel-based failover.

### 1. Set Helm values

```yaml
redis:
  enabled: true
  architecture: replication
  sentinel:
    enabled: true
    masterSet: mymaster
  auth:
    enabled: true
    sentinel: true
    password: "replace-me"
  tls:
    enabled: false

externalRedis:
  enabled: false
```

### 2. Important rules

- `redis.architecture` must be `replication` when `redis.sentinel.enabled=true`
- Apollo will automatically use the bundled Sentinel service at `<release-name>-redis:26379`
- If you enable TLS in the Redis subchart, also set `redis.tls.enabled: true`
- If you want Sentinel auth on the bundled Redis deployment, keep `redis.auth.sentinel: true`
- If `redis.auth.password` changes, you must rotate the bundled Redis secret/pod during upgrade

### 3. Upgrade the release

```bash
helm upgrade <release-name> ./composio -n <namespace> -f values-override.yaml
```

### 4. Verify Apollo

```bash
kubectl exec deploy/<release-name>-apollo -n <namespace> -- printenv | grep '^REDIS'
```

You should see:

- `REDIS_SENTINEL_HOSTS`
- `REDIS_SENTINEL_MASTER_NAME`
- `REDIS_PASSWORD` if auth is enabled
- `REDIS_SENTINEL_PASSWORD` if Sentinel auth is enabled

You should not see `REDIS_URL`.

## Validation and troubleshooting

### Check rendered manifests before upgrade

```bash
helm template <release-name> ./composio -f values-override.yaml | grep -n "REDIS"
```

### Check Apollo pod env after upgrade

```bash
kubectl exec deploy/<release-name>-apollo -n <namespace> -- printenv | grep '^REDIS'
```

### Check Apollo logs

```bash
kubectl logs deploy/<release-name>-apollo -n <namespace> --tail=200
```

### Common mistakes

- Enabling both `redis.enabled` and `externalRedis.enabled`
- Enabling Sentinel mode without setting both `hosts` and `masterName`
- Leaving `redis.architecture` as `standalone` while enabling bundled Sentinel
- Expecting `REDIS_URL` to be used in Sentinel mode
- Forgetting to rotate the bundled Redis secret/pod after changing `redis.auth.password`
