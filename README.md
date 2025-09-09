[![Helm Chart](https://img.shields.io/badge/Helm-Chart-0f1689?logo=helm)](https://helm.sh/)
# Composio Helm Charts

https://composio.dev 

Production-ready Helm charts to deploy Composio on any Kubernetes cluster. 


## 📋 Prerequisites
- Kubernetes cluster (GKE, EKS, AKS, or self-managed)
- Helm 3.x installed
- `kubectl` configured for your cluster
- External PostgreSQL database
- AWS ECR access (or equivalent container registry)


## 🚀 Installation Steps

### Step 1: Prerequisites Setup
Ensure you have the following ready:
- Kubernetes cluster with at least **9 CPUs** and **24GB RAM** (recommended: 12+ CPUs, 32GB RAM)
- External PostgreSQL database
- AWS ECR access configured
- `kubectl` and Helm 3.x installed

### Step 2: Install Knative Components
```bash
# Install Knative Serving CRDs
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.15.0/serving-crds.yaml

# Install Knative Serving Core
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.15.0/serving-core.yaml

# Install Kourier networking layer
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.15.0/kourier.yaml

# Configure Kourier as default ingress
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
```

### Step 3: Configure External Secrets
Set up your database and API credentials:
```bash
# Required environment variables
export POSTGRES_URL="postgresql://<username>:<password>@<host_ip>:5432/<database_name>?sslmode=require"
export REDIS_URL="redis://<username>:<password>@<host>:6379/0"  # Optional
export OPENAI_API_KEY="sk-1234567890abcdef..."  # Optional

# Run the secret setup script
./secret-setup.sh -r composio -n composio
```

### Step 4: Deploy Composio with Helm
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
# Update secrets if needed (optional)
POSTGRES_URL="postgresql://<username>:<password>@<host_ip>:5432/<database_name>?sslmode=require" \
REDIS_URL="redis://<username>:<password>@<host>:6379/0" \
OPENAI_API_KEY="sk-1234567890abcdef..." \
./secret-setup.sh -r composio -n composio

# Upgrade Helm release
helm upgrade composio ./composio -n composio --debug
```

## ⚙️ Configuration Options

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

## 🔐 Retrieving Secrets

All sensitive credentials are auto-generated during installation:

```bash
# Get admin token
kubectl get secret composio-secrets -n composio -o jsonpath="{.data.APOLLO_ADMIN_TOKEN}" | base64 -d

# Get all secrets
kubectl get secret composio-secrets -n composio -o yaml
```

## 🛠️ Troubleshooting

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

