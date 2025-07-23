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


## Quick installation
```
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.15.0/serving-crds.yaml

kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.15.0/serving-core.yaml

kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.15.0/kourier.yaml

kubectl patch configmap/config-network --namespace knative-serving --type merge --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

helm install composio ./composio \
  --create-namespace \
  --namespace composio \
  --set namespace.name=composio \
  --set externalSecrets.ecr.token="$(aws ecr get-login-password --region us-east-1)" \
  --set externalSecrets.postgres.url="postgresql://<username>:<password>@<host_ip>:5432/<database_name>?sslmode=require"
```

### Verify Installation

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
| `mercury.useKnative` | Enable Knative serverless deployment | `true` |
| `mercury.enabled` | Enable Mercury service | `true` |
| `namespace.name` | Target namespace | `composio` |
| `namespace.create` | Create namespace if it doesn't exist | `true` |

### External Dependencies

| Parameter | Description | Required |
|-----------|-------------|----------|
| `externalSecrets.postgres.url` | PostgreSQL connection URL | ✅ Yes |
| `externalSecrets.ecr.token` | AWS ECR authentication token | ✅ Yes |
| `externalSecrets.redis.url` | External Redis connection URL | ⚠️ Optional* |

*Required when `externalRedis.enabled: true`

#### External Redis Configuration

To use an external Redis instance instead of the built-in Redis:

```bash
helm install composio ./composio \
  --create-namespace \
  --namespace composio \
  --set namespace.name=composio \
  --set externalSecrets.ecr.token="$(aws ecr get-login-password --region us-east-1)" \
  --set externalSecrets.postgres.url="postgresql://<username>:<password>@<host_ip>:5432/<database_name>?sslmode=require" \
  --set externalSecrets.redis.url="redis://<username>:<password>@<redis_host>:6379/<database_number>" \
  --set externalRedis.enabled=true \
  --set redis.enabled=false
```

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

- **Minimum**: 4 CPUs, 8GB RAM
- **Recommended**: 8 CPUs, 16GB RAM
- **Storage**: 20GB minimum for persistent volumes

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

