# Using AWS IAM Roles for Container Image Pulls on Google Cloud Platform (GCP)

This guide explains how to configure AWS IAM roles to pull container images from Amazon ECR when your Kubernetes cluster is running on Google Cloud Platform (GCP).

## Overview

When running workloads on GCP but storing container images in AWS ECR, you need to establish cross-cloud authentication. This involves:
- Setting up AWS IAM roles with ECR permissions
- Configuring GCP Workload Identity or service accounts
- Creating Kubernetes secrets for ECR authentication

## Prerequisites

- GCP Kubernetes cluster (GKE)
- AWS account with ECR repositories
- `kubectl` configured for your GKE cluster
- AWS CLI configured
- Google Cloud CLI (`gcloud`) configured

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
                    "sts:ExternalId": "unique-external-id"
                }
            }
        }
    ]
}
EOF

# Create the role
aws iam create-role \
    --role-name ECRCrossCloudRole \
    --assume-role-policy-document file://trust-policy.json

# Attach the policy to the role
aws iam attach-role-policy \
    --role-name ECRCrossCloudRole \
    --policy-arn arn:aws:iam::YOUR_AWS_ACCOUNT_ID:policy/ECRReadOnlyPolicy
```

## Step 2: Create AWS User for GCP Authentication

### 2.1 Create IAM User

```bash
# Create user
aws iam create-user --user-name gcp-ecr-user

# Create access keys
aws iam create-access-key --user-name gcp-ecr-user
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
            "Resource": "arn:aws:iam::YOUR_AWS_ACCOUNT_ID:role/ECRCrossCloudRole"
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name AssumeECRRolePolicy \
    --policy-document file://assume-role-policy.json

aws iam attach-user-policy \
    --user-name gcp-ecr-user \
    --policy-arn arn:aws:iam::YOUR_AWS_ACCOUNT_ID:policy/AssumeECRRolePolicy
```

## Step 3: Configure GCP Workload Identity (Recommended)

### 3.1 Enable Workload Identity on GKE

```bash
# Enable Workload Identity on existing cluster
gcloud container clusters update CLUSTER_NAME \
    --workload-pool=PROJECT_ID.svc.id.goog \
    --zone=ZONE

# Update node pool
gcloud container node-pools update NODE_POOL_NAME \
    --cluster=CLUSTER_NAME \
    --workload-metadata=GKE_METADATA \
    --zone=ZONE
```

### 3.2 Create Google Service Account

```bash
# Create GSA
gcloud iam service-accounts create ecr-puller \
    --display-name="ECR Image Puller"

# Create Kubernetes Service Account
kubectl create serviceaccount ecr-puller-ksa \
    --namespace=NAMESPACE

# Bind GSA to KSA
gcloud iam service-accounts add-iam-policy-binding \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:PROJECT_ID.svc.id.goog[NAMESPACE/ecr-puller-ksa]" \
    ecr-puller@PROJECT_ID.iam.gserviceaccount.com

# Annotate KSA
kubectl annotate serviceaccount ecr-puller-ksa \
    --namespace=NAMESPACE \
    iam.gke.io/gcp-service-account=ecr-puller@PROJECT_ID.iam.gserviceaccount.com
```

## Step 4: Create Kubernetes Secret for ECR Authentication

### Option A: Using AWS Credentials (Direct Method)

```bash
# Create AWS credentials secret
kubectl create secret generic aws-ecr-credentials \
    --from-literal=aws-access-key-id=YOUR_ACCESS_KEY \
    --from-literal=aws-secret-access-key=YOUR_SECRET_KEY \
    --from-literal=aws-region=us-west-2 \
    --namespace=NAMESPACE
```

### Option B: Using ECR Token (Token Refresh Method)

Create a script to refresh ECR tokens:

```bash
cat > refresh-ecr-token.sh << 'EOF'
#!/bin/bash
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-west-2"
ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/ECRCrossCloudRole"

# Assume role
TEMP_ROLE=$(aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name ecr-token-session \
    --external-id unique-external-id \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

export AWS_ACCESS_KEY_ID=$(echo $TEMP_ROLE | cut -d' ' -f1)
export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_ROLE | cut -d' ' -f2)
export AWS_SESSION_TOKEN=$(echo $TEMP_ROLE | cut -d' ' -f3)

# Get ECR token
TOKEN=$(aws ecr get-login-password --region $AWS_REGION)

# Create or update Kubernetes secret
kubectl create secret docker-registry ecr-secret \
    --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
    --docker-username=AWS \
    --docker-password=$TOKEN \
    --namespace=NAMESPACE \
    --dry-run=client -o yaml | kubectl apply -f -
EOF

chmod +x refresh-ecr-token.sh
```

## Step 5: Configure Helm Values

Update your `values.yaml` or `values-override.yaml`:

```yaml
# For direct AWS credentials method
imagePullSecrets:
  - name: aws-ecr-credentials

# For ECR secret method
imagePullSecrets:
  - name: ecr-secret

# Configure image repository
image:
  repository: 123456789012.dkr.ecr.us-west-2.amazonaws.com/your-app
  tag: latest

# Service account configuration
serviceAccount:
  create: true
  name: ecr-puller-ksa
  annotations:
    iam.gke.io/gcp-service-account: ecr-puller@PROJECT_ID.iam.gserviceaccount.com
```

## Step 6: Automate Token Refresh (Optional)

### Create CronJob for Token Refresh

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ecr-token-refresher
  namespace: NAMESPACE
spec:
  schedule: "0 */8 * * *"  # Every 8 hours
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: ecr-puller-ksa
          containers:
          - name: token-refresher
            image: amazon/aws-cli:latest
            command:
            - /bin/bash
            - -c
            - |
              # Your token refresh script here
              aws ecr get-login-password --region us-west-2 | \
              kubectl create secret docker-registry ecr-secret \
                --docker-server=123456789012.dkr.ecr.us-west-2.amazonaws.com \
                --docker-username=AWS \
                --docker-password-stdin \
                --dry-run=client -o yaml | kubectl apply -f -
            env:
            - name: AWS_DEFAULT_REGION
              value: us-west-2
          restartPolicy: OnFailure
```

## Step 7: Deploy and Test

```bash
# Deploy your application
helm install my-app ./composio -f values-override.yaml

# Verify image pull
kubectl get pods -n NAMESPACE
kubectl describe pod POD_NAME -n NAMESPACE
```

## Troubleshooting

### Common Issues

1. **Image Pull Errors**
   ```bash
   kubectl describe pod POD_NAME
   # Check imagePullSecrets and ECR permissions
   ```

2. **AWS Role Assumption Failures**
   ```bash
   aws sts assume-role --role-arn ROLE_ARN --role-session-name test
   # Verify trust policy and external ID
   ```

3. **Token Expiration**
   - ECR tokens expire after 12 hours
   - Set up automated refresh with CronJob
   - Monitor token refresh logs

### Verification Commands

```bash
# Test AWS access
aws ecr describe-repositories --region us-west-2

# Test role assumption
aws sts assume-role \
    --role-arn arn:aws:iam::ACCOUNT:role/ECRCrossCloudRole \
    --role-session-name test-session \
    --external-id unique-external-id

# Test ECR login
aws ecr get-login-password --region us-west-2 | \
docker login --username AWS --password-stdin ACCOUNT.dkr.ecr.us-west-2.amazonaws.com
```

## Security Best Practices

1. **Use Workload Identity** when possible instead of storing AWS credentials
2. **Rotate access keys** regularly
3. **Use least privilege** IAM policies
4. **Monitor access logs** in AWS CloudTrail
5. **Use external IDs** for cross-account role assumption
6. **Automate token refresh** to avoid manual intervention

## References

- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [AWS ECR Authentication](https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html)
- [Kubernetes Image Pull Secrets](https://kubernetes.io/docs/concepts/containers/images/#specifying-imagepullsecrets-on-a-pod)