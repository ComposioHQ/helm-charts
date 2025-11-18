## Setting up S3 (or Google Cloud Storage via S3 APIs)

This guide shows how to configure Composio to use your own S3 buckets, or Google Cloud Storage (GCS) through its S3-compatible API. Apollo reads its S3 configuration from Helm values and credentials from a Kubernetes Secret.

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

Apollo loads S3 credentials from a namespaced secret named `{release}-s3-credentials` with keys `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY`.

```bash
kubectl create secret generic composio-s3-credentials \
  -n composio \
  --from-literal=S3_ACCESS_KEY_ID="<YOUR_ACCESS_KEY_ID>" \
  --from-literal=S3_SECRET_ACCESS_KEY="<YOUR_SECRET_ACCESS_KEY>"
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
