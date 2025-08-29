# Using AWS IAM Roles for Container Image Pulls on Microsoft Azure

This guide explains how to configure AWS IAM roles to pull container images from Amazon ECR when your Kubernetes cluster is running on Microsoft Azure (AKS).

## Overview

When running workloads on Azure Kubernetes Service (AKS) but storing container images in AWS ECR, you need to establish cross-cloud authentication. This involves:
- Setting up AWS IAM roles with ECR permissions
- Configuring Azure Workload Identity or service principals
- Using Azure Key Vault for secure credential storage
- Creating Kubernetes secrets for ECR authentication

## Prerequisites

- Azure Kubernetes Service (AKS) cluster
- AWS account with ECR repositories
- `kubectl` configured for your AKS cluster
- AWS CLI configured
- Azure CLI (`az`) configured
- Azure subscription with appropriate permissions

## Step 1: Create AWS IAM Role for ECR Access

### 1.1 Create IAM Policy for ECR

```bash
# Create ECR policy document
cat > ecr-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create the policy
aws iam create-policy \
    --policy-name ECRReadOnlyPolicy \
    --policy-document file://ecr-policy.json
```

### 1.2 Create IAM Role

```bash
# Create trust policy for cross-account access
cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "azure-aks-external-id"
                }
            }
        }
    ]
}
EOF

# Create the role
aws iam create-role \
    --role-name ECRAzureAccessRole \
    --assume-role-policy-document file://trust-policy.json

# Attach the policy to the role
aws iam attach-role-policy \
    --role-name ECRAzureAccessRole \
    --policy-arn arn:aws:iam::YOUR_AWS_ACCOUNT_ID:policy/ECRReadOnlyPolicy
```

## Step 2: Create AWS User for Azure Authentication

### 2.1 Create IAM User

```bash
# Create user
aws iam create-user --user-name azure-ecr-user

# Create access keys
aws iam create-access-key --user-name azure-ecr-user
```

### 2.2 Create User Policy to Assume Role

```bash
cat > assume-role-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/ECRAzureAccessRole"
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name AssumeECRRolePolicy \
    --policy-document file://assume-role-policy.json

aws iam attach-user-policy \
    --user-name azure-ecr-user \
    --policy-arn arn:aws:iam::YOUR_AWS_ACCOUNT_ID:policy/AssumeECRRolePolicy
```

## Step 3: Configure Azure Workload Identity (Recommended)

### 3.1 Enable Workload Identity on AKS

```bash
# Create resource group (if not exists)
az group create --name myResourceGroup --location eastus

# Create AKS cluster with OIDC issuer and workload identity
az aks create \
    --resource-group myResourceGroup \
    --name myAKSCluster \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --generate-ssh-keys

# Or update existing cluster
az aks update \
    --resource-group myResourceGroup \
    --name myAKSCluster \
    --enable-oidc-issuer \
    --enable-workload-identity

# Get the OIDC issuer URL
export AKS_OIDC_ISSUER="$(az aks show --name myAKSCluster --resource-group myResourceGroup --query "oidcIssuerProfile.issuerUrl" -o tsv)"
```

### 3.2 Create Azure Managed Identity

```bash
# Create managed identity
az identity create \
    --resource-group myResourceGroup \
    --name ecr-puller-identity

# Get identity details
export USER_ASSIGNED_IDENTITY_CLIENT_ID="$(az identity show --resource-group myResourceGroup --name ecr-puller-identity --query 'clientId' -o tsv)"
export USER_ASSIGNED_IDENTITY_OBJECT_ID="$(az identity show --resource-group myResourceGroup --name ecr-puller-identity --query 'principalId' -o tsv)"
```

### 3.3 Create Federated Identity Credential

```bash
# Create federated identity credential
az identity federated-credential create \
    --name ecr-puller-federated-credential \
    --identity-name ecr-puller-identity \
    --resource-group myResourceGroup \
    --issuer $AKS_OIDC_ISSUER \
    --subject system:serviceaccount:NAMESPACE:ecr-puller-ksa
```

## Step 4: Set Up Azure Key Vault for AWS Credentials

### 4.1 Create Azure Key Vault

```bash
# Create Key Vault
az keyvault create \
    --name myECRKeyVault \
    --resource-group myResourceGroup \
    --location eastus

# Grant access to the managed identity
az keyvault set-policy \
    --name myECRKeyVault \
    --object-id $USER_ASSIGNED_IDENTITY_OBJECT_ID \
    --secret-permissions get list
```

### 4.2 Store AWS Credentials in Key Vault

```bash
# Store AWS credentials
az keyvault secret set \
    --vault-name myECRKeyVault \
    --name "aws-access-key-id" \
    --value "YOUR_AWS_ACCESS_KEY_ID"

az keyvault secret set \
    --vault-name myECRKeyVault \
    --name "aws-secret-access-key" \
    --value "YOUR_AWS_SECRET_ACCESS_KEY"

az keyvault secret set \
    --vault-name myECRKeyVault \
    --name "aws-region" \
    --value "us-west-2"

az keyvault secret set \
    --vault-name myECRKeyVault \
    --name "aws-role-arn" \
    --value "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/ECRAzureAccessRole"
```

## Step 5: Create Kubernetes Service Account

```bash
# Create namespace
kubectl create namespace ecr-demo

# Create service account
cat > service-account.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ecr-puller-ksa
  namespace: ecr-demo
  annotations:
    azure.workload.identity/client-id: $USER_ASSIGNED_IDENTITY_CLIENT_ID
  labels:
    azure.workload.identity/use: "true"
EOF

kubectl apply -f service-account.yaml
```

## Step 6: Deploy AWS Credentials Fetcher

### 6.1 Create Secret Provider Class for Azure Key Vault

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-credentials-spc
  namespace: ecr-demo
spec:
  provider: azure
  secretObjects:
  - secretName: aws-ecr-credentials
    type: Opaque
    data:
    - objectName: aws-access-key-id
      key: aws-access-key-id
    - objectName: aws-secret-access-key
      key: aws-secret-access-key
    - objectName: aws-region
      key: aws-region
    - objectName: aws-role-arn
      key: aws-role-arn
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    clientID: $USER_ASSIGNED_IDENTITY_CLIENT_ID
    keyvaultName: myECRKeyVault
    tenantId: YOUR_TENANT_ID
    objects: |
      array:
        - |
          objectName: aws-access-key-id
          objectType: secret
        - |
          objectName: aws-secret-access-key
          objectType: secret
        - |
          objectName: aws-region
          objectType: secret
        - |
          objectName: aws-role-arn
          objectType: secret
```

### 6.2 Create ECR Token Refresher Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ecr-token-refresher
  namespace: ecr-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ecr-token-refresher
  template:
    metadata:
      labels:
        app: ecr-token-refresher
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: ecr-puller-ksa
      containers:
      - name: token-refresher
        image: amazon/aws-cli:latest
        command: ["/bin/bash"]
        args:
        - -c
        - |
          while true; do
            echo "Refreshing ECR token..."
            
            # Read AWS credentials from mounted secret
            export AWS_ACCESS_KEY_ID=$(cat /mnt/secrets/aws-access-key-id)
            export AWS_SECRET_ACCESS_KEY=$(cat /mnt/secrets/aws-secret-access-key)
            export AWS_DEFAULT_REGION=$(cat /mnt/secrets/aws-region)
            ROLE_ARN=$(cat /mnt/secrets/aws-role-arn)
            
            # Assume role
            TEMP_ROLE=$(aws sts assume-role \
              --role-arn $ROLE_ARN \
              --role-session-name ecr-azure-session \
              --external-id azure-aks-external-id \
              --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
              --output text)
            
            if [ $? -eq 0 ]; then
              export AWS_ACCESS_KEY_ID=$(echo $TEMP_ROLE | cut -d' ' -f1)
              export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_ROLE | cut -d' ' -f2)
              export AWS_SESSION_TOKEN=$(echo $TEMP_ROLE | cut -d' ' -f3)
              
              # Get ECR token
              TOKEN=$(aws ecr get-login-password --region $AWS_DEFAULT_REGION)
              
              if [ $? -eq 0 ]; then
                # Create or update Kubernetes secret
                kubectl create secret docker-registry ecr-secret \
                  --docker-server=YOUR_AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com \
                  --docker-username=AWS \
                  --docker-password=$TOKEN \
                  --namespace=ecr-demo \
                  --dry-run=client -o yaml | kubectl apply -f -
                
                echo "ECR token refreshed successfully"
              else
                echo "Failed to get ECR token"
              fi
            else
              echo "Failed to assume role"
            fi
            
            # Sleep for 8 hours (tokens expire in 12 hours)
            sleep 28800
          done
        volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets"
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
      volumes:
      - name: secrets-store
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: aws-credentials-spc
```

## Step 7: Alternative - CronJob for Token Refresh

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ecr-token-refresher-cron
  namespace: ecr-demo
spec:
  schedule: "0 */8 * * *"  # Every 8 hours
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            azure.workload.identity/use: "true"
        spec:
          serviceAccountName: ecr-puller-ksa
          containers:
          - name: token-refresher
            image: amazon/aws-cli:latest
            command:
            - /bin/bash
            - -c
            - |
              # Read AWS credentials from mounted secret
              export AWS_ACCESS_KEY_ID=$(cat /mnt/secrets/aws-access-key-id)
              export AWS_SECRET_ACCESS_KEY=$(cat /mnt/secrets/aws-secret-access-key)
              export AWS_DEFAULT_REGION=$(cat /mnt/secrets/aws-region)
              ROLE_ARN=$(cat /mnt/secrets/aws-role-arn)
              
              # Assume role and get ECR token
              TEMP_ROLE=$(aws sts assume-role \
                --role-arn $ROLE_ARN \
                --role-session-name ecr-azure-cron \
                --external-id azure-aks-external-id \
                --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
                --output text)
              
              export AWS_ACCESS_KEY_ID=$(echo $TEMP_ROLE | cut -d' ' -f1)
              export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_ROLE | cut -d' ' -f2)
              export AWS_SESSION_TOKEN=$(echo $TEMP_ROLE | cut -d' ' -f3)
              
              TOKEN=$(aws ecr get-login-password --region $AWS_DEFAULT_REGION)
              
              kubectl create secret docker-registry ecr-secret \
                --docker-server=YOUR_AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com \
                --docker-username=AWS \
                --docker-password=$TOKEN \
                --namespace=ecr-demo \
                --dry-run=client -o yaml | kubectl apply -f -
            volumeMounts:
            - name: secrets-store
              mountPath: "/mnt/secrets"
              readOnly: true
          volumes:
          - name: secrets-store
            csi:
              driver: secrets-store.csi.k8s.io
              readOnly: true
              volumeAttributes:
                secretProviderClass: aws-credentials-spc
          restartPolicy: OnFailure
```

## Step 8: Configure Helm Values

Update your `values.yaml` or `values-override.yaml`:

```yaml
# Configure image repository
image:
  repository: YOUR_AWS_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/your-app
  tag: latest

# Configure image pull secrets
imagePullSecrets:
  - name: ecr-secret

# Service account configuration
serviceAccount:
  create: true
  name: ecr-puller-ksa
  annotations:
    azure.workload.identity/client-id: YOUR_MANAGED_IDENTITY_CLIENT_ID
  labels:
    azure.workload.identity/use: "true"

# Namespace configuration
namespace: ecr-demo
```

## Step 9: Install Required Components

### 9.1 Install Azure Key Vault CSI Driver

```bash
# Add Helm repository
helm repo add csi-secrets-store-provider-azure \
    https://azure.github.io/secrets-store-csi-driver-provider-azure/charts

# Install the CSI driver
helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure \
    --generate-name \
    --namespace kube-system
```

### 9.2 Install Secrets Store CSI Driver

```bash
# Add Helm repository
helm repo add secrets-store-csi-driver \
    https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts

# Install the driver
helm install csi-secrets-store \
    secrets-store-csi-driver/secrets-store-csi-driver \
    --namespace kube-system
```

## Step 10: Deploy and Test

```bash
# Apply all configurations
kubectl apply -f service-account.yaml
kubectl apply -f secret-provider-class.yaml
kubectl apply -f ecr-token-refresher.yaml

# Deploy your application
helm install my-app ./composio -f values-override.yaml --namespace ecr-demo

# Verify deployment
kubectl get pods -n ecr-demo
kubectl describe pod POD_NAME -n ecr-demo
```

## Troubleshooting

### Common Issues

1. **Azure Workload Identity Issues**
   ```bash
   # Check service account annotations
   kubectl describe sa ecr-puller-ksa -n ecr-demo
   
   # Verify federated credential
   az identity federated-credential list \
       --resource-group myResourceGroup \
       --identity-name ecr-puller-identity
   ```

2. **Key Vault Access Issues**
   ```bash
   # Check managed identity permissions
   az keyvault show --name myECRKeyVault --query "properties.accessPolicies"
   
   # Test secret access
   az keyvault secret show --vault-name myECRKeyVault --name aws-access-key-id
   ```

3. **AWS Role Assumption Failures**
   ```bash
   # Test role assumption
   aws sts assume-role \
       --role-arn arn:aws:iam::ACCOUNT:role/ECRAzureAccessRole \
       --role-session-name test-session \
       --external-id azure-aks-external-id
   ```

4. **ECR Authentication Issues**
   ```bash
   # Check ECR secret
   kubectl get secret ecr-secret -n ecr-demo -o yaml
   
   # Test ECR access
   kubectl run test-pod --image=YOUR_AWS_ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/your-app:latest \
       --overrides='{"spec":{"imagePullSecrets":[{"name":"ecr-secret"}]}}' \
       --namespace=ecr-demo
   ```

### Verification Commands

```bash
# Check Azure CLI authentication
az account show

# Test AWS access from Azure
aws sts get-caller-identity

# Verify ECR repositories
aws ecr describe-repositories --region us-west-2

# Check Kubernetes secrets
kubectl get secrets -n ecr-demo

# Monitor token refresher logs
kubectl logs -f deployment/ecr-token-refresher -n ecr-demo
```

## Security Best Practices

1. **Use Azure Workload Identity** instead of storing credentials in pods
2. **Store secrets in Azure Key Vault** with proper access policies
3. **Rotate AWS access keys** regularly
4. **Use least privilege** IAM policies and Azure RBAC
5. **Monitor access logs** in both AWS CloudTrail and Azure Activity Log
6. **Use external IDs** for AWS cross-account role assumption
7. **Enable Azure Key Vault audit logging**
8. **Implement proper network policies** for pod-to-pod communication

## References

- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/docs/)
- [Azure Key Vault CSI Driver](https://azure.github.io/secrets-store-csi-driver-provider-azure/)
- [AWS ECR Authentication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html)
- [AKS Best Practices](https://docs.microsoft.com/en-us/azure/aks/best-practices)
- [Kubernetes Image Pull Secrets](https://kubernetes.io/docs/concepts/containers/images/#specifying-imagepullsecrets-on-a-pod)