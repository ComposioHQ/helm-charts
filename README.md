[![Helm Chart](https://img.shields.io/badge/Helm-Chart-0f1689?logo=helm)](https://helm.sh/)
[![Documentation](https://img.shields.io/badge/Docs-Online-blue)](https://composiohq.github.io/helm-charts/index.html)

# Composio Helm Charts

https://composio.dev

Production-ready Helm charts to deploy Composio on any Kubernetes cluster.

**📖 [Complete Documentation](https://composiohq.github.io/helm-charts/index.html)** | [Architecture](https://composiohq.github.io/helm-charts/architecture.html) | [Configuration](https://composiohq.github.io/helm-charts/configuration.html) | [Cloud Guides](https://composiohq.github.io/helm-charts/guides.html) | [Troubleshooting](https://composiohq.github.io/helm-charts/troubleshooting.html) 

## 🏗️ Architecture

The following diagram illustrates the Composio Kubernetes architecture, showing the flow of requests, interactions between services, and auxiliary components:

```mermaid
graph TB
    Internet[🌐 Internet] --> HTTPS[HTTPS]
    HTTPS --> PublicIngress[Public Ingress<br/>Optional]
    
    subgraph "KUBERNETES CLUSTER"
        PublicIngress --> Apollo[Apollo<br/>OAuth callbacks/business logic]
        
        Apollo <--> Redis[Redis<br/>Cache/Data Store]
        Apollo --> Thermos[Thermos<br/>Tools Management]
        
        Redis --> Temporal[Temporal.io<br/>Workflows Management]
        Thermos --> Temporal
        Thermos --> Mercury[Mercury<br/>Knative Service]
        
        Temporal <--> Postgres[Postgres<br/>Primary Database]
        Apollo <--> Postgres
        
        Mercury --> ToolsAPIs[Tools/LLM APIs<br/>External Services]
        
        subgraph "AUXILIARY SERVICES"
            KubeSecrets[kube-secrets<br/>Secret Management]
            OtherK8s[Other Necessary K8s<br/>Components]
            ECR[ECR<br/>Docker Images]
        end
        
        Apollo --> OtelCollector[Otel Collector<br/>Metrics/Traces]
        Thermos --> OtelCollector
        Mercury --> OtelCollector
    end
    
    ToolsAPIs -.->|Outbound Actions<br/>egress internet| Internet
    
    classDef coreService fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    classDef database fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef external fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef auxiliary fill:#e8f5e8,stroke:#1b5e20,stroke-width:2px
    classDef monitoring fill:#fce4ec,stroke:#880e4f,stroke-width:2px
    
    class Apollo,Thermos,Mercury coreService
    class Redis,Postgres,Temporal database
    class Internet,ToolsAPIs external
    class KubeSecrets,OtherK8s,ECR auxiliary
    class OtelCollector monitoring
```

### Component Descriptions

- **Core Services**: Apollo (main API), Thermos (tools management), Mercury (Knative service)
- **Data Layer**: Redis (caching), Postgres (primary database), Temporal.io (workflow orchestration)
- **External Integration**: Tools/LLM APIs for AI functionality
- **Auxiliary Services**: kube-secrets, ECR, other Kubernetes components
- **Monitoring**: Otel Collector for observability and telemetry

For additional architectural details, see our [Architecture Diagram](./docs/architecture-diagram.md).

## 📋 Prerequisites
- Kubernetes cluster (GKE, EKS, AKS, or self-managed)
- Helm 3.x installed
- `kubectl` configured for your cluster
- External PostgreSQL database
- AWS ECR access (or equivalent container registry)

> **Detailed guides available**: See our [cloud provider guides](https://composiohq.github.io/helm-charts/guides.html) for GKE, EKS, and AKS specific setup instructions.


## Pre-Installation SQL 
Run below sql queries before deploying helm chart

```sh 
CREATE USER composio WITH PASSWORD 'superuserpassword';

-- Create databases
CREATE DATABASE composiodb OWNER composio;
CREATE DATABASE temporal OWNER composio;
CREATE DATABASE temporal_visibility OWNER composio;
CREATE DATABASE thermosdb OWNER composio;


\c thermosdb
GRANT ALL PRIVILEGES ON DATABASE thermosdb TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;



-- Connect to composiodb and grant privileges
\c composiodb
GRANT ALL PRIVILEGES ON DATABASE composiodb TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;

-- Connect to temporal and grant privileges
\c temporal
GRANT ALL PRIVILEGES ON DATABASE temporal TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;

-- Connect to temporal_visibility and grant privileges
\c temporal_visibility
GRANT ALL PRIVILEGES ON DATABASE temporal_visibility TO composio;
GRANT ALL PRIVILEGES ON SCHEMA public TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO composio;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO composio;

ALTER ROLE composio CREATEDB;

```

## 🚀 Installation Steps

### Step 1: Prerequisites Setup
Ensure you have the following ready:
- Kubernetes cluster with at least **9 CPUs** and **24GB RAM** (recommended: 12+ CPUs, 32GB RAM)
- External PostgreSQL database
- AWS ECR access configured
- `kubectl` and Helm 3.x installed

### Step 2: Install Knative Components
# Install Knative Serving CRDs (latest: v1.19.6)
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.19.6/serving-crds.yaml

# Install Knative Serving Core (latest: v1.19.6)
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.19.6/serving-core.yaml

# Install Kourier networking layer (latest: v1.19.5)
kubectl apply -f https://github.com/knative-extensions/net-kourier/releases/download/knative-v1.19.5/kourier.yaml

# Configure Kourier as default ingress
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

### Step 3: Configure Secrets
Set up your database and API credentials using the comprehensive secret management system:

Kindly ensure above Kubernetes exists so they can be referenced in values file. 

```yaml 
smtp: 
  username: "test"
  host: "host.smtp.io"
  port: "5432"
  password: 
    secretRef: "smtppassword"
    key: "password"

# Credentials should be in same namespace
database: 
  apollo: 
    database: "composiodb"
    port: "5432"
    sslmode: "disable"
    user: "composio"
    host: "postgres-new.db"
    password: 
      secretRef: "dbpassword"
      key: "password"
  thermos: 
    database: "thermosdb"
    port: "5432"
    sslmode: "disable"
    user: "composio"
    host: "postgres-new.db"
    password: 
      secretRef: "dbpassword"
      key: "password"

redisConnection:
  host: "redis-0.redis.db.svc.cluster.local"
  port: "6379"
  password:
    secretRef: "redispassword"
    key: "password"

apollo:
    objectStorage:
        # Supported: "s3", "azure_blob_storage"
        backend: "s3"
        accessKey: 
          secretName: "s3-cred"
          key: "S3_ACCESS_KEY_ID"
        secretKey: 
          secretName: "s3-cred"
          key: "S3_SECRET_ACCESS_KEY"
        azureConnectionString: 
          secretName: "azure-cred"
          key: "AZURE_CONNECTION_STRING"
```
Please check below commond to create kubernetes secrets if you don't have 
 
```yaml 
kubectl create secret generic smtppassword \
  --from-literal=password='random' \
  -n composio

kubectl create secret generic dbpassword \
  --from-literal=password='devtesting123' \
  -n composio

kubectl create secret generic redispassword \
  --from-literal=password='' \
  -n composio

# Based on objectStorage backend
kubectl create secret generic s3-cred \
  --from-literal=S3_ACCESS_KEY_ID='YOUR_S3_ACCESS_KEY_ID' \
  --from-literal=S3_SECRET_ACCESS_KEY='YOUR_S3_SECRET_ACCESS_KEY' \
  -n composio

# Based on objectStorage backend
kubectl create secret generic azure-cred \
  --from-literal=AZURE_CONNECTION_STRING='YOUR_AZURE_CONNECTION_STRING' \
  -n composio

# Optional
kubectl create secret generic openai-cred \
  --from-literal=API_KEY='OPENAI_API_KEY' \
  -n composio
```

### Step 3.1: Temporal Configuration 

You need to configure Temporal with the database host 

```yaml
temporal:
  server:
    enabled: true
    config:
        default:
          driver: "sql"
          sql:
            driver: "postgres12"
            host: "<YOUR DATABASE HOST>"
            port: 5432
            database: "temporal"
            user: "postgres"
            existingSecret: "external-postgres-secret"
            maxConns: 20
            maxIdleConns: 20
            maxConnLifetime: "1h"
        visibility:
          driver: "sql" 
          sql:
            driver: "postgres12"
            host: "<YOUR DATABASE HOST>"
            port: 5432
            database: "temporal_visibility"
            user: "postgres"
            existingSecret: "external-postgres-secret"
            maxConns: 20
            maxIdleConns: 20
            maxConnLifetime: "1h"
```

### Step 3.2⚙️ Configure TLS for Temporal

To enable TLS for Temporal when connecting to a managed database (for example, **AWS RDS**), follow the steps below.

---

#### 3.2a. Download the RDS CA Certificate

Download the AWS RDS CA bundle to establish a trusted connection between Temporal and your database:

```bash
curl -O https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
````

---

#### 3.2b. Create a Kubernetes Secret

Create a Kubernetes secret containing the downloaded CA private key:

```bash
kubectl create secret generic temporal-db-tls-secret \
  --from-file=rds-ca.crt=./global-bundle.pem \
  -n composio
```

This secret will be used by Temporal for TLS host verification.

---

#### 3.2c. Update the Temporal Values File

Update your `values.yaml` file to enable TLS and reference the mounted certificate.

```yaml
default:
  driver: "sql"
  sql:
    driver: "postgres12"
    host: "HOST"
    port: 5432
    database: "temporal"
    user: "composio"
    existingSecret: "external-postgres-secret"
    maxConns: 20
    maxIdleConns: 20
    maxConnLifetime: "1h"
    tls:
      enabled: true
      disableHostVerification: true
      caFile: /etc/certs/rds-ca.crt

# Visibility database (created by schema setup)
visibility:
  driver: "sql"
  sql:
    driver: "postgres12"
    host: "HOST"
    port: 5432
    database: "temporal_visibility"
    user: "composio"
    existingSecret: "external-postgres-secret"
    maxConns: 20
    maxIdleConns: 20
    maxConnLifetime: "1h"
    tls:
      enabled: true
      disableHostVerification: true
      caFile: /etc/certs/rds-ca.crt
```

#### 3.2d. Mount the Secret in AdminTools

Mount the Kubernetes secret into the `admintools` pod by adding the following configuration:

```yaml
admintools:
  nodeSelector: {}
  tolerations: []
  affinity: {}
  additionalVolumes:
    - name: temporal-db-tls
      secret:
        secretName: temporal-db-tls-secret
  additionalVolumeMounts:
    - name: temporal-db-tls
      mountPath: /etc/certs
      readOnly: true
```

### Step 4: Deploy Composio with Helm
```bash
# Install the Helm chart
helm install composio ./composio \
  --create-namespace \
  --namespace composio \
  --set namespace.name=composio \
  --set externalSecrets.ecr.token="$(aws ecr get-login-password --region us-east-1)" \
  -f ./custom-values-file.yaml
  --debug
```

### Step 5: Verify Installation
```bash
# Check all pods are running (may take 5-10 minutes)
kubectl get pods -n composio

# Verify Knative services
kubectl get ksvc -n composio

# Check Knative infrastructure
kubectl get pods -n knative-serving
```



## 🔄 Upgrade Deployment

To upgrade an existing Composio deployment:

```bash
# Secrets are automatically preserved during upgrades
# Only update secrets if you need to change external dependencies
POSTGRES_URL="postgresql://<username>:<password>@<host_ip>:5432/<database_name>?sslmode=require" \
REDIS_URL="redis://<username>:<password>@<host>:6379/0" \
OPENAI_API_KEY="sk-1234567890abcdef..." \
./secret-setup.sh -r composio -n composio

# Upgrade Helm release (secrets are preserved)
helm upgrade composio ./composio -n composio --debug
```

> **Secret Protection**: All existing secrets are automatically preserved during Helm upgrades. The `secret-setup.sh` script only creates new secrets if they don't exist, ensuring your existing configuration remains intact.

## ⚙️ Configuration Options

> **Full configuration reference**: See the [complete configuration guide](https://composiohq.github.io/helm-charts/configuration.html) for detailed parameter documentation.

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

External services (PostgreSQL, Redis, OpenAI) are configured via the `secret-setup.sh` script before deploying. See **Quick Installation** section above for details.

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

#### Auto-Generated Secrets
These secrets are automatically created by the `secret-setup.sh` script:

| Secret Name | Purpose | Key |
|-------------|---------|-----|
| `{release}-apollo-admin-token` | Apollo API admin authentication | `APOLLO_ADMIN_TOKEN` |
| `{release}-encryption-key` | Application data encryption | `ENCRYPTION_KEY` |
| `{release}-temporal-encryption-key` | Temporal workflow encryption | `TEMPORAL_TRIGGER_ENCRYPTION_KEY` |
| `{release}-composio-api-key` | Composio API authentication | `COMPOSIO_API_KEY` |
| `{release}-minio-credentials` | MinIO object storage credentials | `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD` |

#### User-Provided Secrets
These secrets are created from environment variables you provide:

| Secret Name | Environment Variable | Purpose |
|-------------|---------------------|---------|
| `external-postgres-secret` | `POSTGRES_URL` | Apollo database connection |
| `external-thermos-postgres-secret` | `THERMOS_POSTGRES_URL` | Thermos database connection |
| `external-redis-secret` | `REDIS_URL` | Redis cache connection |
| `{release}-openai-credentials` | `OPENAI_API_KEY` | OpenAI API integration (uses existing `openai-secret` if present for backward compatibility) |

#### Helm-Managed Secrets
These secrets are managed by Helm templates with existence checks:

| Secret Name | Purpose | When Created |
|-------------|---------|--------------|
| `ecr-secret` | AWS ECR authentication | When `externalSecrets.ecr.token` is provided |
| `{release}-support-bundle` | Troubleshoot.sh integration | When `supportBundle.enabled=true` |

> **⚠️ CRITICAL: ENCRYPTION_KEY Security**
> 
> The `ENCRYPTION_KEY` is **CRITICAL** and **MUST NOT BE LOST**:
> - **Encrypts database data**: All sensitive data in the database is encrypted with this key
> - **Cannot be recovered**: If lost, encrypted data becomes permanently inaccessible
> - **Must persist across deployments**: The same key must be used for all upgrades
> - **Backup required**: Always backup this key before any deployment changes
> - **Secure storage**: Store this key in a secure location (password manager, secure vault)
> 
> **If you lose the ENCRYPTION_KEY, you will lose access to all encrypted data in your database.**

### Secret Setup Process

#### Initial Setup
```bash
# Set up external secrets using the script (recommended)
export POSTGRES_URL="postgresql://user:pass@host:port/db"
export THERMOS_POSTGRES_URL="postgresql://user:pass@host:port/db"  # Optional
export REDIS_URL="redis://user:pass@host:port/db"  # Optional
export OPENAI_API_KEY="sk-..."  # Optional

# Run secret setup
./secret-setup.sh -r composio -n composio
```

#### Dry Run Mode
```bash
# Preview what secrets would be created
./secret-setup.sh -r composio -n composio --dry-run
```

#### Skip Generated Secrets
```bash
# Only create user-provided secrets
./secret-setup.sh -r composio -n composio --skip-generated
```

### Retrieving Secrets

#### Get Specific Secret Values
```bash
# Get Apollo admin token
kubectl get secret composio-apollo-admin-token -n composio -o jsonpath="{.data.APOLLO_ADMIN_TOKEN}" | base64 -d

# Get MinIO credentials
kubectl get secret composio-minio-credentials -n composio -o jsonpath="{.data.MINIO_ROOT_USER}" | base64 -d
kubectl get secret composio-minio-credentials -n composio -o jsonpath="{.data.MINIO_ROOT_PASSWORD}" | base64 -d

# Get external database URL
kubectl get secret external-postgres-secret -n composio -o jsonpath="{.data.url}" | base64 -d

# Get ENCRYPTION_KEY (CRITICAL - backup this immediately!)
kubectl get secret composio-encryption-key -n composio -o jsonpath="{.data.ENCRYPTION_KEY}" | base64 -d
```

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

- **Auto-generated secrets**: Never recreated by Helm, only by `secret-setup.sh`
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

### Secret Management Best Practices

#### 1. Production Deployment
- **Use external databases**: Always provide `POSTGRES_URL` for production
- **Separate databases**: Use different databases for Apollo and Thermos
- **External Redis**: Use `REDIS_URL` for better performance and persistence
- **Backup secrets**: Keep secure backups of all generated secrets
- **ENCRYPTION_KEY backup**: **CRITICAL** - Backup the ENCRYPTION_KEY immediately after first deployment

#### 2. Development Setup
- **Minimal configuration**: Only provide `POSTGRES_URL`, let script generate others
- **Local databases**: Use local PostgreSQL instances for development
- **Built-in services**: Use built-in Redis and MinIO for simplicity

#### 3. Security Considerations
- **Secret rotation**: Regularly rotate auto-generated secrets in production
- **Access control**: Use RBAC to limit secret access
- **External secret management**: Consider using AWS Secrets Manager or HashiCorp Vault
- **Network policies**: Implement network policies to restrict secret access

#### 4. Upgrade Strategy
- **Secrets are preserved**: All secrets survive Helm upgrades
- **New secrets**: Only new secrets are created, existing ones are never modified
- **Backup before upgrade**: Always backup critical secrets before major upgrades
- **Test upgrades**: Test secret management in non-production environments

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
kubectl get secret external-postgres-secret -n composio
kubectl get secret external-thermos-postgres-secret -n composio

# Test database connection manually
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "$(kubectl get secret external-postgres-secret -n composio -o jsonpath='{.data.url}' | base64 -d)"
```

#### Secret Management Issues
```bash
# Check if secrets exist
kubectl get secrets -n composio | grep -E "(composio-|external-|openai-)"

# Verify secret contents (base64 encoded)
kubectl get secret composio-apollo-admin-token -n composio -o yaml

# Check secret setup script logs
./secret-setup.sh -r composio -n composio --dry-run

# Recreate missing secrets
./secret-setup.sh -r composio -n composio
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
kubectl get secret composio-encryption-key -n composio

# Verify ENCRYPTION_KEY value (backup this!)
kubectl get secret composio-encryption-key -n composio -o jsonpath="{.data.ENCRYPTION_KEY}" | base64 -d

# If ENCRYPTION_KEY is missing, recreate it (WARNING: This will make existing encrypted data inaccessible!)
./secret-setup.sh -r composio -n composio

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

#### Container Registry Issues
```bash
# Verify ECR access from GKE
kubectl create secret docker-registry ecr-secret \
  --docker-server=AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region us-east-1)" \
  --namespace=composio --dry-run=client -o yaml

# Test image pull
kubectl run test-pull --image=AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/composio-self-host/apollo:v2.5 \
  --dry-run=client -o yaml
```

### Resource Requirements

#### Minimum Cluster Requirements
- **Minimum**: 9 CPUs, 24GB RAM (based on actual resource requests)
- **Recommended**: 12+ CPUs, 32GB RAM (for buffer and temporal)
- **Storage**: 20GB minimum for persistent volumes

#### Recommended Resource Limits (Per Service)

| Service | CPU Request | Memory Request | CPU Limit | Memory Limit |
|---------|-------------|----------------|-----------|--------------|
| **Apollo** | 1 | 5Gi | 1 | 6Gi |
| **MCP** | 1 | 5Gi | 1 | 6Gi |
| **Thermos** | 2 | 4Gi | 2 | 5Gi |
| **Mercury** | 1 | 2Gi | 2 | 4Gi |
| **Minio** | 2 | 4Gi | 2 | 4Gi |
| **Redis** (if enabled) | 2 | 4Gi | 2 | 4Gi |
| **Temporal** | Default | Default | Default | Default |

**Total Recommended Resources**: 9+ CPUs, 24+ GB RAM

> **Note**: All values are configurable via values.yaml

### 📚 Documentation

- **Documentation Website**: https://composiohq.github.io/helm-charts/index.html
- **Architecture Guide**: https://composiohq.github.io/helm-charts/architecture.html
- **Configuration Reference**: https://composiohq.github.io/helm-charts/configuration.html
- **Cloud Provider Guides**: https://composiohq.github.io/helm-charts/guides.html
- **Troubleshooting**: https://composiohq.github.io/helm-charts/troubleshooting.html
- **Secret Management**: [SECRETS.md](./SECRETS.md) - Detailed secret management documentation
- **GCS via S3 Storage Guide**: [docs/gcs-s3-storage.md](./docs/gcs-s3-storage.md)
 - **SMTP Setup Guide**: [docs/smtp-setup.md](./docs/smtp-setup.md)
 - **Frontend Setup Guide**: [docs/frontend-setup.md](./docs/frontend-setup.md)
- **Composio Docs**: https://docs.composio.dev
- **GitHub**: https://github.com/composio/helm-charts
- **Support**: https://discord.gg/composio

### Uninstall Composio

```bash
# Uninstall Helm release
helm uninstall composio -n composio

# Delete namespace (optional)
kubectl delete namespace composio
```

### Delete GKE Resources

```bash
# Delete Cloud SQL instance (optional)
gcloud sql instances delete composio-postgres --quiet

# Delete GKE cluster
gcloud container clusters delete $CLUSTER_NAME --region=$REGION --quiet

# Remove kubectl context
kubectl config delete-context gke_${PROJECT_ID}_${REGION}_${CLUSTER_NAME}
```

### Clean up local resources

```bash
# Remove Helm dependencies
rm -rf ./composio/charts/
rm -f ./composio/Chart.lock

# Clean up environment variables
unset PROJECT_ID REGION CLUSTER_NAME CLOUD_SQL_CONNECTION_NAME POSTGRES_IP
```

## 🔖 Version Compatibility

| Composio Version | Knative Version | Kubernetes Version | GKE Version |
|------------------|-----------------|-------------------|-------------|
| 1.0.0 | 1.15.0 | 1.28+ | 1.28+ |

Contact our team for enterprise support and advanced deployment configurations.

