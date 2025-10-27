[![Helm Chart](https://img.shields.io/badge/Helm-Chart-0f1689?logo=helm)](https://helm.sh/)
[![Documentation](https://img.shields.io/badge/Docs-Online-blue)](https://onprem.composio.dev)

# Composio Helm Charts

https://composio.dev

Production-ready Helm charts to deploy Composio on any Kubernetes cluster.

**📖 [Complete Documentation](https://onprem.composio.dev)** | [Architecture](https://onprem.composio.dev/architecture.html) | [Configuration](https://onprem.composio.dev/configuration.html) | [Cloud Guides](https://onprem.composio.dev/guides.html) | [Troubleshooting](https://onprem.composio.dev/troubleshooting.html) 


## 📋 Prerequisites
- Kubernetes cluster (GKE, EKS, AKS, or self-managed)
- Helm 3.x installed
- `kubectl` configured for your cluster
- External PostgreSQL database
- AWS ECR access (or equivalent container registry)

> **Detailed guides available**: See our [cloud provider guides](https://onprem.composio.dev/guides.html) for GKE, EKS, and AKS specific setup instructions.


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

#### Option A: Full External Dependencies (Recommended for Production)
```bash
# Required: PostgreSQL for Apollo
export POSTGRES_URL="postgresql://<username>:<password>@<host_ip>:5432/<database_name>?sslmode=require"

# Optional: Separate PostgreSQL for Thermos
export THERMOS_POSTGRES_URL="postgresql://<username>:<password>@<host_ip>:5432/<database_name>?sslmode=require"

# Optional: External Redis (uses built-in Redis if not provided)
export REDIS_URL="redis://<username>:<password>@<host>:6379/0"

# Optional: OpenAI API for AI functionality
export OPENAI_API_KEY="sk-1234567890abcdef..."

# Run the secret setup script
./secret-setup.sh -r composio -n composio
```

#### Option B: Minimal Setup (Development)
```bash
# Only provide required PostgreSQL, let script generate other secrets
export POSTGRES_URL="postgresql://<username>:<password>@<host_ip>:5432/<database_name>?sslmode=require"

# Run secret setup (will auto-generate missing secrets)
./secret-setup.sh -r composio -n composio
```

#### Option C: Dry Run (Preview)
```bash
# Preview what secrets would be created without making changes
./secret-setup.sh -r composio -n composio --dry-run
```

> **Secret Management**: The `secret-setup.sh` script handles both auto-generated secrets (tokens, keys) and user-provided secrets (database URLs, API keys). All secrets are protected from recreation during Helm upgrades.

### Step 4: Deploy Composio with Helm

NOTE: Below is an example on how to provide nodeselector, affinity and toleration to thermos and apollo application using values.yaml. 

```
thermos: 
    nodeSelector:
      kubernetes.io/os: linux
      env: dev

    tolerations:
      - key: "dedicated"
        operator: "Equal"
        value: "test"
        effect: "NoSchedule"

    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: kubernetes.io/hostname
                  operator: In
                  values:
                    - test-node-1
                    - test-node-2
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            preference:
              matchExpressions:
                - key: env
                  operator: In
                  values:
                    - dev


apollo:
    nodeSelector:
      kubernetes.io/os: linux
      env: dev

    tolerations:
      - key: "dedicated"
        operator: "Equal"
        value: "test"
        effect: "NoSchedule"

    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: kubernetes.io/hostname
                  operator: In
                  values:
                    - test-node-1
                    - test-node-2
        preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            preference:
              matchExpressions:
                - key: env
                  operator: In
                  values:
                    - dev
```


```bash
# Install the Helm chart
helm install composio ./composio \
  --create-namespace \
  --namespace composio \
  --set namespace.name=composio \
  --set externalSecrets.ecr.token="$(aws ecr get-login-password --region us-east-1)" \
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

> **Full configuration reference**: See the [complete configuration guide](https://onprem.composio.dev/configuration.html) for detailed parameter documentation.

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
| `openai-secret` | `OPENAI_API_KEY` | OpenAI API integration |

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

> **Comprehensive troubleshooting guide**: Visit [troubleshooting page](https://onprem.composio.dev/troubleshooting.html) for detailed solutions.

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

- **Documentation Website**: https://onprem.composio.dev
- **Architecture Guide**: https://onprem.composio.dev/architecture.html
- **Configuration Reference**: https://onprem.composio.dev/configuration.html
- **Cloud Provider Guides**: https://onprem.composio.dev/guides.html
- **Troubleshooting**: https://onprem.composio.dev/troubleshooting.html
- **Secret Management**: [SECRETS.md](./SECRETS.md) - Detailed secret management documentation
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

