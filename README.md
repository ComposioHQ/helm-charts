[![Helm Chart](https://img.shields.io/badge/Helm-Chart-0f1689?logo=helm)](https://helm.sh/)
# Composio Helm Charts

https://composio.dev 

Production-ready Helm charts to deploy Composio on any Kubernetes cluster with support for both **standard Kubernetes deployments** and **Knative serverless** architectures.

## 🚀 Deployment Options

### Standard Kubernetes Deployment
- Traditional Kubernetes Deployments and Services
- Fixed resource allocation
- Suitable for consistent workloads

### Knative Serverless Deployment  
- Auto-scaling serverless architecture
- Scale-to-zero capabilities
- Automatic Knative installation and configuration
- Ideal for variable or event-driven workloads

## 📋 Prerequisites

- Kubernetes cluster (GKE, EKS, AKS, or self-managed)
- Helm 3.x installed
- `kubectl` configured for your cluster
- External PostgreSQL database
- AWS ECR access (or equivalent container registry)

### GKE Setup Commands

#### Create GKE Cluster

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export CLUSTER_NAME="composio-cluster"

# Create GKE Autopilot cluster (recommended)
gcloud container clusters create-auto $CLUSTER_NAME \
    --region=$REGION \
    --project=$PROJECT_ID

# OR create standard GKE cluster
gcloud container clusters create $CLUSTER_NAME \
    --region=$REGION \
    --project=$PROJECT_ID \
    --num-nodes=3 \
    --machine-type=e2-standard-4 \
    --disk-size=50GB \
    --enable-autoscaling \
    --min-nodes=1 \
    --max-nodes=5

# Enable Horizontal Pod Autoscaling (REQUIRED for Knative)
gcloud container clusters update $CLUSTER_NAME \
    --region=$REGION \
    --enable-horizontal-pod-autoscaling
```

#### Configure kubectl

```bash
# Get cluster credentials
gcloud container clusters get-credentials $CLUSTER_NAME \
    --region=$REGION \
    --project=$PROJECT_ID

# Verify connection
kubectl cluster-info
```

#### Set up necessary permissions

```bash
# Create cluster admin binding for your user
kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account)
```

#### Install Helm (if not already installed)

```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

#### Set up Cloud SQL PostgreSQL (Optional)

```bash
# Create Cloud SQL PostgreSQL instance
gcloud sql instances create composio-postgres \
    --database-version=POSTGRES_15 \
    --tier=db-standard-2 \
    --region=$REGION \
    --project=$PROJECT_ID \
    --storage-type=SSD \
    --storage-size=20GB \
    --storage-auto-increase

# Set root password
gcloud sql users set-password postgres \
    --instance=composio-postgres \
    --password="your-secure-password"

# Create database for Composio
gcloud sql databases create composio \
    --instance=composio-postgres

# Get connection details
gcloud sql instances describe composio-postgres \
    --format="value(connectionName,ipAddresses[0].ipAddress)"

# Create Cloud SQL Proxy connection (for secure access)
gcloud sql instances patch composio-postgres \
    --authorized-networks=0.0.0.0/0  # Use with caution - consider VPC peering instead
```

## 🔧 Installation

### Step 1: Prepare Dependencies

```bash
# Update Helm dependencies
helm dependency update ./composio
```

### Step 2: Choose Your Deployment Mode

#### Option A: Standard Kubernetes Deployment

```bash
helm install composio ./composio \
  --create-namespace \
  --namespace composio \
  --set namespace.name=composio \
  --set externalSecrets.ecr.token="$(aws ecr get-login-password --region us-east-1)" \
  --set externalSecrets.postgres.url="postgresql://postgres:your_password@your_host:5432/postgres?sslmode=require" \
  --set mercury.useKnative=false
```

#### Option B: Knative Serverless Deployment

```bash
helm install composio ./composio \
  --create-namespace \
  --namespace composio \
  --set namespace.name=composio \
  --set externalSecrets.ecr.token="$(aws ecr get-login-password --region us-east-1)" \
  --set externalSecrets.postgres.url="postgresql://postgres:your_password@your_host:5432/postgres?sslmode=require" \
  --set mercury.useKnative=true
```

#### Option C: GKE with Cloud SQL Integration

```bash
# Get Cloud SQL connection string
export CLOUD_SQL_CONNECTION_NAME=$(gcloud sql instances describe composio-postgres --format="value(connectionName)")
export POSTGRES_IP=$(gcloud sql instances describe composio-postgres --format="value(ipAddresses[0].ipAddress)")

# Deploy with Cloud SQL
helm install composio ./composio \
  --create-namespace \
  --namespace composio \
  --set namespace.name=composio \
  --set externalSecrets.ecr.token="$(aws ecr get-login-password --region us-east-1)" \
  --set externalSecrets.postgres.url="postgresql://postgres:your_password@${POSTGRES_IP}:5432/composio?sslmode=require" \
  --set mercury.useKnative=false
```

#### Option D: GKE Autopilot with Knative

```bash
# For GKE Autopilot clusters, use Knative for better resource optimization
helm install composio ./composio \
  --create-namespace \
  --namespace composio \
  --set namespace.name=composio \
  --set externalSecrets.ecr.token="$(aws ecr get-login-password --region us-east-1)" \
  --set externalSecrets.postgres.url="postgresql://postgres:your_password@your_host:5432/postgres?sslmode=require" \
  --set mercury.useKnative=true \
  --set global.environment=production
```

> **🎉 That's it!** When `mercury.useKnative=true`, Helm automatically:
> - Installs Knative Serving CRDs and core components
> - Sets up Kourier networking layer  
> - Configures ingress and domain settings
> - Deploys Mercury as a Knative service with auto-scaling

### Step 3: Verify Installation

```bash
# Check all pods are running
kubectl get pods -n composio

# For Knative deployments, also check Knative infrastructure
kubectl get pods -n knative-serving

# Check Knative services (only for Knative deployments)
kubectl get ksvc -n composio
```

## ⚙️ Configuration Options

### Core Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mercury.useKnative` | Enable Knative serverless deployment | `false` |
| `mercury.enabled` | Enable Mercury service | `true` |
| `namespace.name` | Target namespace | `composio` |
| `namespace.create` | Create namespace if it doesn't exist | `true` |

### External Dependencies

| Parameter | Description | Required |
|-----------|-------------|----------|
| `externalSecrets.postgres.url` | PostgreSQL connection URL | ✅ Yes |
| `externalSecrets.ecr.token` | AWS ECR authentication token | ✅ Yes |

### Knative-Specific Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `mercury.autoscaling.minScale` | Minimum replicas | `1` |
| `mercury.autoscaling.maxScale` | Maximum replicas | `10` |
| `mercury.autoscaling.target` | Target CPU utilization | `80` |
| `mercury.containerConcurrency` | Max concurrent requests per container | `0` (unlimited) |
| `mercury.timeoutSeconds` | Request timeout | `300` |

## 🔍 Service Access

### Port Forwarding (Development)

```bash
# Apollo (Main API)
kubectl port-forward -n composio svc/composio-apollo 8080:9900

# MCP (Management Portal)  
kubectl port-forward -n composio svc/composio-mcp 8081:3000

# Temporal Web UI
kubectl port-forward -n composio svc/composio-temporal-web 8082:8080

# Mercury (Knative service)
kubectl port-forward -n composio svc/composio-mercury 8083:8080
```

### Access URLs

- **Apollo API**: http://localhost:8080
- **MCP Portal**: http://localhost:8081  
- **Temporal UI**: http://localhost:8082
- **Mercury**: http://localhost:8083

## 🔐 Retrieving Secrets

All sensitive credentials are auto-generated during installation:

```bash
# Get admin token
kubectl get secret composio-secrets -n composio -o jsonpath="{.data.APOLLO_ADMIN_TOKEN}" | base64 -d

# Get all secrets
kubectl get secret composio-secrets -n composio -o yaml
```

## 🔄 Upgrading

### Standard to Knative Migration

```bash
helm upgrade composio ./composio \
  --namespace composio \
  --set mercury.useKnative=true \
  --reuse-values
```

### Knative to Standard Migration

```bash
helm upgrade composio ./composio \
  --namespace composio \
  --set mercury.useKnative=false \
  --reuse-values
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

- **Minimum**: 4 CPUs, 8GB RAM
- **Recommended**: 8 CPUs, 16GB RAM
- **Storage**: 20GB minimum for persistent volumes

## 📚 Documentation

- **Composio Docs**: https://docs.composio.dev
- **GitHub**: https://github.com/composio/helm-charts
- **Support**: https://discord.gg/composio

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│     Apollo      │    │       MCP        │    │    Thermos      │
│   (Main API)    │◄──►│  (Management)    │◄──►│   (Execution)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │     Mercury     │
                    │   (Serverless)  │  ◄── Knative Optional
                    └─────────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   PostgreSQL    │    │     Temporal     │    │      Redis      │
│   (Database)    │    │   (Workflows)    │    │     (Cache)     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 🧹 Cleanup (GKE)

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

