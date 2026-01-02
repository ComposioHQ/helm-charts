## 📋 Prerequisites
- Kubernetes cluster (GKE, EKS, AKS, or self-managed)
- Helm 3.x installed
- `kubectl` configured for your cluster
- External PostgreSQL database
- AWS ECR access (or equivalent container registry)



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

### Step 2: Configure Secrets
Set up your database and API credentials using the comprehensive secret management system:

Kindly ensure Kubernetes secrets exists so they can be referenced in values file. 

```yaml
apollo: 
  smtp:
    enabled: false
    smtpAuthorEmail: "admin@yourdomain.com"
    secretRef: "connectionstring"
    key: "SMTP_CONNECTION_STRING" 
   # Apollo database configuration. Pass the complete DATABASE URI
  database:
    # Database URL secret reference
    urlSecret:
      # -- Secret name containing database URL
      name: "external-postgres-secret"
      # -- Key name in the secret
      key: "url"
  # Select the objectStorage backend
  objectStorage:
    # -- Storage backend type (s3 or azure_blob_storage)
    backend: "s3"
    # S3 access key configuration
    accessKey: 
      # -- Secret name containing S3 access key
      secretName: "s3-cred"
      # -- Key name in the secret
      key: "S3_ACCESS_KEY_ID"
    # S3 secret key configuration
    secretKey: 
      # -- Secret name containing S3 secret key
      secretName: "s3-cred"
      # -- Key name in the secret
      key: "S3_SECRET_ACCESS_KEY"
    # Azure Blob Storage connection string configuration
    azureConnectionString: 
      # -- Secret name containing Azure connection string
      secretName: "azure-cred"
      # -- Key name in the secret
      key: "AZURE_CONNECTION_STRING"

# Database credentials for thermos
thermos:
  # Pass the complete DATABASE URI
  database: 
    # -- Secret reference containing database URI
    secretRef: "thermosdb"
    # -- Key name in the secret
    key: "uri"


# Temporal Database configuration 

temporal: 
  server: 
    config:
      persistence:
        default:
          sql:
            driver: "postgres12"
            host: "postgres-new.db"
            port: 5432
            database: "temporal"
            user: "composio"
            existingSecret: "temporal-password-secret"
            maxConns: 20
            maxIdleConns: 20
            maxConnLifetime: "1h"
        visibility:
          sql:
            driver: "postgres12"
            host: "postgres-new.db"
            port: 5432
            database: "temporal_visibility"
            user: "composio"
            existingSecret: "temporal-password-secret"
            maxConns: 20
            maxIdleConns: 20
            maxConnLifetime: "1h"
```
You can use below commonds to create Kubernetes secrets 

```bash 
kubectl create secret generic openai-cred \
  --from-literal=API_KEY="sk-dummyopenaikey" \
  -n composio

kubectl create secret generic external-postgres-secret \
  --from-literal=url="postgresql://composio:devtesting123@postgres-new.db:5432/composiodb?sslmode=disable" \
  -n composio

kubectl create secret generic thermosdb \
  --from-literal=uri="postgresql://composio:devtesting123@postgres-new.db:5432/thermosdb?sslmode=disable" \
  -n composio

kubectl create secret generic temporal-password-secret \
  --from-literal=password="devtesting123" \
  -n composio

kubectl create secret generic s3-cred \
  --from-literal=S3_ACCESS_KEY_ID="dummy-access-key" \
  --from-literal=S3_SECRET_ACCESS_KEY="dummy-secret-key" \
  -n composio

kubectl create secret generic azure-cred \
  --from-literal=AZURE_CONNECTION_STRING="dummy-string" \
  -n composio

kubectl create secret generic connectionstring \
  --from-literal=SMTP_CONNECTION_STRING="smtp://user:pass@smtp.resend.com:587" \
  -n composio

kubectl create secret generic redis-cred \
  --from-literal=url="redis://redis-0.redis.db.svc.cluster.local:6379/0" \
  -n composio
```


### Step 3.1: Temporal Configuration 

> **Note**
> Kindly follow **Step 3** to configure Temporal with TLS.  
> If your database has TLS enabled and these steps are skipped, the Helm installation **will fail**.

> **Note**
> If TLS is **disabled** on your database, follow **Step 4** to install the Helm chart.

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

> **Note**
> Kindly read post-installation for imp steps after installation.
