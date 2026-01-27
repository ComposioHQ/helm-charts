### OpenTelemetry (OTEL) Configuration

The chart includes built-in OpenTelemetry support for collecting metrics and traces from all services.

#### Enabling/Disabling OTEL

```yaml
otel:
  enabled: true  # Set to false to disable OTEL completely
  
  traces:
    enabled: true  # Enable trace collection
    sampler: "always_on"  # Options: always_on, always_off, traceidratio
    samplerArg: 1.0  # Sampling ratio (0.0 to 1.0) for traceidratio
  
  metrics:
    enabled: true  # Enable metrics collection
    exportInterval: 60000  # Export interval in milliseconds
```

#### OTEL Collector Configuration

The OTEL collector receives telemetry from services and exports to backends like Google Cloud Monitoring, Prometheus, or other OTLP-compatible systems.

```yaml
otel:
  collector:
    enabled: true
    replicaCount: 1
    
    # Configure exporters
    config:
      exporters:
        # Debug exporter (logs to console)
        debug:
          verbosity: basic
        
        # Prometheus exporter for metrics
        prometheus:
          endpoint: "0.0.0.0:8889"
        
        # Google Cloud exporter for metrics and traces
        googlecloud:
          project: "your-gcp-project-id"
          metric:
            # IMPORTANT: Custom metrics MUST use custom.googleapis.com/ prefix
            prefix: "custom.googleapis.com/composio/"
          trace: {}
      
      # Configure pipelines
      service:
        pipelines:
          traces:
            receivers: [otlp, jaeger]
            processors: [memory_limiter, batch]
            exporters: [debug, googlecloud]
          metrics:
            receivers: [otlp]
            processors: [memory_limiter, batch]
            exporters: [debug, prometheus, googlecloud]
```

#### Service Endpoint Configuration

**IMPORTANT: Endpoint Format Rules**

- **gRPC endpoints (port 4317)**: Do NOT include protocol prefix
  - ✅ Correct: `composio-otel-collector:4317`
  - ❌ Incorrect: `http://composio-otel-collector:4317`
  - ❌ Incorrect: `grpc://composio-otel-collector:4317`

- **HTTP endpoints (port 4318)**: Must include `http://` prefix
  - ✅ Correct: `http://composio-otel-collector:4318/v1/metrics`
  - ❌ Incorrect: `composio-otel-collector:4318/v1/metrics`

```yaml
otel:
  exporter:
    otlp:
      # gRPC endpoint - NO protocol prefix
      endpoint: "composio-otel-collector:4317"
      tracesEndpoint: "composio-otel-collector:4317"
      metricsEndpoint: "composio-otel-collector:4317"
      insecure: true  # Set to false for TLS
  
  # Service-specific configurations
  apollo:
    serviceName: "apollo"
    serviceVersion: "1.0.0"
    # HTTP endpoint for metrics (with http:// prefix)
    metricsEndpoint: "http://composio-otel-collector:4318/v1/metrics"
  
  mercury:
    serviceName: "mercury-openapi"
    serviceVersion: "1.0.0"
    metricsEndpoint: "http://composio-otel-collector:4318/v1/metrics"
  
  thermos:
    serviceName: "thermos"
    serviceVersion: "1.0.0"
    metricsEndpoint: "http://composio-otel-collector:4318/v1/metrics"
```

#### Google Cloud Monitoring Setup

To export metrics and traces to Google Cloud:

**1. Create GCP Service Account:**
```bash
gcloud iam service-accounts create otel-collector \
  --display-name="OTEL Collector"
```

**2. Grant Required Permissions:**
```bash
# For metrics
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:otel-collector@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/monitoring.metricWriter"

# For traces
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:otel-collector@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudtrace.agent"
```

**3. Configure Workload Identity (for GKE):**
```bash
gcloud iam service-accounts add-iam-policy-binding \
  otel-collector@YOUR_PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:YOUR_PROJECT_ID.svc.id.goog[composio/composio-otel-collector]"
```

**4. Update values.yaml:**
```yaml
otel:
  collector:
    googleCloud:
      enabled: true
      projectId: "YOUR_PROJECT_ID"
      serviceAccount:
        create: true
        name: "otel-collector"
        annotations:
          iam.gke.io/gcp-service-account: "otel-collector@YOUR_PROJECT_ID.iam.gserviceaccount.com"
    
    config:
      exporters:
        googlecloud:
          project: "YOUR_PROJECT_ID"
          metric:
            prefix: "custom.googleapis.com/composio/"
          trace: {}
```

**Important Notes:**
- Google Cloud custom metrics **must** use the `custom.googleapis.com/` prefix
- The prefix format is: `custom.googleapis.com/<your-namespace>/`
- Without the correct prefix, you'll get `PermissionDenied` errors

#### Verification

```bash
# Check OTEL collector logs
kubectl logs -n composio -l app.kubernetes.io/component=otel-collector --tail=50

# Verify service OTEL configuration
kubectl exec -n composio deployment/composio-apollo -- env | grep OTEL

# View Prometheus metrics (if enabled)
kubectl port-forward -n composio svc/composio-otel-collector 8889:8889
# Access http://localhost:8889/metrics

# Check Google Cloud Monitoring
# Navigate to: Cloud Console > Monitoring > Metrics Explorer
# Search for: custom.googleapis.com/composio/
```

#### Disabling OTEL

To disable OTEL completely:

```yaml
otel:
  enabled: false  # Disables instrumentation in services
  collector:
    enabled: false  # Disables the collector
```

Or disable only service instrumentation while keeping the collector:

```yaml
otel:
  enabled: false  # Services won't send telemetry
  collector:
    enabled: true  # Collector still available for other workloads
```

### External Dependencies

| Parameter | Description | Required |
|-----------|-------------|----------|
| `externalSecrets.ecr.token` | AWS ECR authentication token | ✅ Yes |

#### External Services Configuration

**Supported Environment Variables:**
- `POSTGRES_URL`: PostgreSQL connection URL
- `REDIS_URL`: External Redis connection URL (optional, uses built-in Redis if not provided)
- `OPENAI_API_KEY`: OpenAI API key for AI functionality (optional)

**Redis URL Format Examples:**
- With authentication: `redis://username:password@host:6379/0`
- Without authentication: `redis://host:6379/0`
- With SSL: `rediss://username:password@host:6380/0`


### Initial Admin Email

Set the initial admin user's email used by the database init jobs. Update `values.yaml`:

```yaml
dbInit:
  adminEmail: "your-admin@example.com"
```

This value is consumed by init jobs (maps to `ADMIN_EMAIL`) to create/configure the admin user.


### Knative-Specific Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mercury.autoscaling.minScale` | Minimum replicas | `1` |
| `mercury.autoscaling.maxScale` | Maximum replicas | `10` |
| `mercury.autoscaling.target` | Target CPU utilization | `80` |
| `mercury.containerConcurrency` | Max concurrent requests per container | `0` (unlimited) |
| `mercury.timeoutSeconds` | Request timeout | `300` |

## 🔍 Service Access


### Port Forwarding (Development/Debugging)

```bash
# Apollo (Main API)
kubectl port-forward -n composio svc/composio-apollo 8080:9900

# MCP (Management Portal)  
kubectl port-forward -n composio svc/composio-mcp 8081:3000

# Temporal Web UI
kubectl port-forward -n composio svc/composio-temporal-web 8082:8080

```


### Access URLs

- **Apollo API**: http://localhost:8080
- **MCP Portal**: http://localhost:8081  
- **Temporal UI**: http://localhost:8082

## 🔐 Secret Management

Composio uses a comprehensive secret management system that handles both auto-generated and user-provided secrets. All secrets are protected from recreation during Helm upgrades.

### Secret Types


| Secret Name | Purpose | Key |
|-------------|---------|-----|
| `{release}-composio-secrets` | Consolidated chart-managed secrets | `APOLLO_ADMIN_TOKEN`, `ENCRYPTION_KEY`, `TEMPORAL_TRIGGER_ENCRYPTION_KEY`, `COMPOSIO_API_KEY`, `JWT_SECRET` |

To create or rotate the consolidated secret manually:

```bash
kubectl create secret generic <release>-composio-secrets \
  --from-literal=APOLLO_ADMIN_TOKEN=<token> \
  --from-literal=ENCRYPTION_KEY=<encryption-key> \
  --from-literal=TEMPORAL_TRIGGER_ENCRYPTION_KEY=<temporal-key> \
  --from-literal=COMPOSIO_API_KEY=<api-key> \
  --from-literal=JWT_SECRET=<jwt-secret> \
  --from-literal=POSTGRES_URL=<postgres_url> \
  --from-literal=THERMOS_DATABASE_URL=<thermos_database_url> \
  # --from-literal=REDIS_URL=<redis_url> \
  --from-literal=OPENAI_API_KEY=<openai_api_key> \
  -n <namespace>
```

#### User-Provided Secrets
These secrets are created from environment variables you provide:

| Secret Name | Environment Variable | Purpose |
|-------------|---------------------|---------|
| `{release}-composio-secrets` | `POSTGRES_URL` | Apollo database connection |
| `{release}-composio-secrets` | `THERMOS_DATABASE_URL` | Thermos database connection |
| `{release}-composio-secrets` | `REDIS_URL` | Redis cache connection |
| `{release}-composio-secrets` | `OPENAI_API_KEY` | OpenAI API integration |

### Retrieving Secrets

#### List All Secrets
```bash
# List all secrets in namespace
kubectl get secrets -n composio

# List secrets with labels
kubectl get secrets -n composio -l app.kubernetes.io/name=composio
```

#### View Secret Details
```bash
# View complete secret (base64 encoded)
kubectl get secret <secret-name> -n composio -o yaml

# Decode specific key
kubectl get secret <secret-name> -n composio -o jsonpath="{.data.<key>}" | base64 -d
```

### Secret Protection

All secrets are protected from recreation during Helm upgrades:

- **User-provided secrets**: Only created if they don't exist
- **Helm-managed secrets**: Use existence checks to prevent recreation

### Manual Secret Management

You can still manage secrets manually using kubectl:

```bash
# Create secret manually
kubectl create secret generic my-secret \
  --from-literal=key=value \
  -n composio

# Update existing secret
kubectl patch secret my-secret -n composio \
  --type='json' \
  -p='[{"op": "replace", "path": "/data/key", "value": "'$(echo -n "new-value" | base64)'"}]'

# Delete secret
kubectl delete secret my-secret -n composio
```

## 🛠️ Troubleshooting

> **Comprehensive troubleshooting guide**: Visit [troubleshooting page](https://composiohq.github.io/helm-charts/troubleshooting.html) for detailed solutions.

### Common Issues

#### Knative Components Not Starting
```bash
# Check Knative installation jobs
kubectl get jobs -n composio -l app.kubernetes.io/component=knative-setup

# View job logs
kubectl logs -n composio job/knative-setup-<revision>
```

#### Mercury Service Not Ready
```bash
# Check Knative service status
kubectl describe ksvc composio-mercury -n composio

# View Mercury pod logs
kubectl logs -n composio -l serving.knative.dev/service=composio-mercury
```

#### Database Connection Issues
```bash
# Verify database connectivity
kubectl logs -n composio deployment/composio-apollo

# Check if database secrets exist
kubectl get secret composio-composio-secrets -n composio

# Test database connection manually
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "$(kubectl get secret composio-composio-secrets -n composio -o jsonpath='{.data.POSTGRES_URL}' | base64 -d)"
```

#### Secret Management Issues
```bash
# Check if secrets exist
kubectl get secrets -n composio | grep -E "(composio-|external-|openai-)"

# Verify secret contents (base64 encoded)
kubectl get secret composio-composio-secrets -n composio -o yaml

```

#### Secret Access Issues
```bash
# Check if pods can access secrets
kubectl describe pod -n composio -l app.kubernetes.io/name=apollo

# Verify secret mounts
kubectl get pod -n composio -l app.kubernetes.io/name=apollo -o jsonpath='{.items[0].spec.volumes}'

# Test secret access from pod
kubectl exec -n composio deployment/composio-apollo -- env | grep -E "(POSTGRES|REDIS|OPENAI)"
```

#### ENCRYPTION_KEY Issues
```bash
# Check if ENCRYPTION_KEY exists
kubectl get secret composio-composio-secrets -n composio

# Verify ENCRYPTION_KEY value (backup this!)
kubectl get secret composio-composio-secrets -n composio -o jsonpath="{.data.ENCRYPTION_KEY}" | base64 -d

# Check if pods can access ENCRYPTION_KEY
kubectl exec -n composio deployment/composio-apollo -- env | grep ENCRYPTION_KEY
```


### GKE-Specific Troubleshooting

#### Check GKE Cluster Status
```bash
# Check cluster status
gcloud container clusters describe $CLUSTER_NAME --region=$REGION

# Check node status
kubectl get nodes -o wide

# Check node pool status (for standard clusters)
gcloud container node-pools list --cluster=$CLUSTER_NAME --region=$REGION
```

#### GKE Autopilot Issues
```bash
# Check Autopilot events
kubectl get events --sort-by=.metadata.creationTimestamp -n composio

# View Autopilot recommendations
gcloud container clusters describe $CLUSTER_NAME --region=$REGION \
  --format="value(autopilot.workloadPolicyConfig)"

# Check resource quotas
kubectl describe quota -n composio
```

#### Cloud SQL Connectivity Issues
```bash
# Test Cloud SQL connectivity
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "postgresql://postgres:your_password@${POSTGRES_IP}:5432/composio?sslmode=require"

# Check Cloud SQL logs
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_id:composio-postgres" \
  --limit 50 --format json

# Verify Cloud SQL instance status
gcloud sql instances describe composio-postgres
```

#### Load Balancer and Ingress Issues
```bash
# Check load balancer status
kubectl get services -n composio -o wide

# Check ingress controller logs (if using ingress)
kubectl logs -n kube-system -l app=gke-ingress

# Check firewall rules
gcloud compute firewall-rules list --filter="name~composio"
```
