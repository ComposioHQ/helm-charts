# Configuring S3 and GCS for File Storage

This guide shows how to configure Composio to use your own S3 buckets, or Google Cloud Storage (GCS) through its S3-compatible API. Apollo reads its S3 configuration from Helm values and credentials from a Kubernetes Secret.

### There are two ways to provide credentials to Apollo:
1. Using a Service Account with Annotations (Recommended for AWS and GCP)



### 1. Using a Service Account with Annotations (Recommended)
You can use IAM roles for service accounts (IRSA) on AWS or Workload Identity on GCP to provide permissions to Apollo without managing secrets manually.

#### For AWS (IAM Roles for Service Accounts - IRSA)
Add the following annotations to your `values.yaml` under `apollo.serviceAccount.annotations`:

```yaml
apollo:
  serviceAccount:
    enabled: true
    name: "composio-apollo"
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::<AWS_ACCOUNT_ID>:role/<IAM_ROLE_NAME>"
```

#### For GCP (Workload Identity)
Add the following annotations to your `values.yaml` under `apollo.serviceAccount.annotations`:

```yaml
apollo:
  serviceAccount:
    enabled: true
    name: "composio-apollo"
    annotations:
      iam.gke.io/gcp-service-account: "<GCP_SERVICE_ACCOUNT_EMAIL>"
```


### 2. Creating a Kubernetes Secret with Credentials

### Prerequisites

#### GCS
- A GCP project with Cloud Storage enabled
- A GCS bucket (for example: `composio-artifacts`)
- HMAC credentials for a service account (Access Key ID and Secret) to use the S3 XML API
- kubectl access to your cluster and namespace

Notes:
- GCS S3 “region” can be set to `auto`.
- Path-style access must remain enabled for compatibility.

#### S3
- An S3 bucket you have access to
- Container credentials for pods launched on AWS EKS, OR
- AWS AccessKey/SecretKey pair with permissions to access this S3 bucket

#### 1) (GCS-only) Create or retrieve GCS HMAC credentials
You need an Access Key ID and Secret that back a service account. You can create HMAC keys in the Cloud Console or via gcloud:

```bash
# Create a service account (if you don't already have one)
gcloud iam service-accounts create composio-s3-sa \
  --display-name="Composio S3 Interop"

# Grant Storage Object Admin (minimum for read/write; tighten if you prefer)
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:composio-s3-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

# Create HMAC key for the service account
gcloud storage hmac create \
  --service-account=composio-s3-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com

# The command prints AccessKeyId and Secret (copy and store securely)
```

#### 2) Create the Kubernetes Secret for Apollo
> **NOTE** If you are using container credentials where your running pods automatically have access to said S3 buckets, you
> can skip this section.

Configure S3 credentials for apollo:
```yaml 
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
```

If your Helm release name or namespace differ, adjust the secret name (`<release>-s3-credentials`) and `-n` accordingly.

#### 3) Set Helm values for GCS S3
##### For GCS
Add the following under `apollo:` in your values override file. Example:

```yaml
apollo:
  s3ForcePathStyle: "true"
  s3EndpointUrl: "https://storage.googleapis.com"
  s3Endpoint: "https://storage.googleapis.com"
  s3Bucket: "<your-gcs-bucket>"
  s3Region: "auto"
  s3SignatureVersion: "s3"
```

For reference, see `values-override.yaml` in this repository which contains similar fields.

#### For S3

```yaml
apollo:
  # Optional - use only if you are expecting to override the URL (when using say, minio, or a VPC endpoint)
  s3EndpointUrl: "..."
  # Optional - use only if you are expecting to override the URL (when using say, minio, or a VPC endpoint)
  s3Endpoint: "..."
  s3Bucket: "bucket-name"
  s3Region: "your aws region"
```

#### 4) Deploy or upgrade Helm
```bash
helm upgrade --install composio ./composio \
  -n composio \
  --create-namespace \
  -f values-override.yaml
```

#### 5) Verify configuration
Check that Apollo picked up your S3 settings and can talk to GCS:

```bash
# Inspect Apollo environment
kubectl exec -n composio deploy/composio-apollo -- env | grep -E "^S3_|^AWS_"

# Logs should not contain signature/endpoint errors
kubectl logs -n composio deploy/composio-apollo --tail=200
```

You should see variables such as `S3_ENDPOINT`, `S3_ENDPOINT_URL`, `S3_FORCE_PATH_STYLE`, `S3_REGION`, and `S3_SIGNATURE_VERSION` set to the values you configured. Credentials are injected from the `{release}-s3-credentials` secret.

### FAQ

- Do I need a GCP JSON key file for this?  
  No. For S3 interoperability, use HMAC (Access Key ID/Secret) and the `https://storage.googleapis.com` endpoint as shown above.

- Do other services (Mercury/Thermos) need S3, or GCS?
  Apollo is the primary consumer of the S3 settings shown here. Composio operates fine without an S3 bucket as well, however, any toolkit
  functionality that depends on files (for ex., sending email with attachments, or fetching email with attachments, otherwise it won't work).
