## Using Azure Blob Storage for Apollo

This guide explains how to configure Composio (Apollo) to use Azure Blob Storage for object storage. You will set the storage backend, provide an Azure Storage connection string, and configure namespaces used for temporary and permanent files.

### Prerequisites

- An Azure Storage Account
- A Blob service with at least two containers for:
  - temporary files (e.g., `composio-temp`)
  - permanent files (e.g., `composio-permanent`)
- An Azure Storage connection string with permissions to read/write blobs
- `kubectl` access to your cluster and namespace running Composio

You can retrieve the connection string from the Azure Portal:
- Storage Account → Security + networking → Access keys → Connection string


### Create the Kubernetes Secret

Create a Secret named `{release}-azure-connection-string` (replace `composio` below with your Helm release name if different). The key must be `AZURE_CONNECTION_STRING`:

```bash
kubectl create secret generic composio-azure-connection-string \
  -n composio \
  --from-literal=AZURE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=<name>;AccountKey=<key>;EndpointSuffix=core.windows.net"
```

OR reference the secret from values file 

```yaml 
apollo: 
    objectStorage:
        backend: "azure_blob_storage"
        azureConnectionString: 
          secretName: "azure-cred"
          key: "AZURE_CONNECTION_STRING"
```

### Configure Helm values

Add the following under `apollo:` in your values override file (e.g., `values-override.yaml`). Update the connection string and namespaces to match your setup.

```yaml
apollo:
  objectStorage:
    backend: "azure_blob_storage"
    namespaces:
      temp: "composio-temp"
      permanent: "composio-permanent"
```

Notes:
- The `backend` must be set to `"azure_blob_storage"`.
- The Azure connection string is read from the Secret `{release}-azure-connection-string` with key `AZURE_CONNECTION_STRING`.
- Ensure the specified containers exist in your storage account.
- Note: You can also use the same container for both temporary files and permanent files since keys don't collide, but we recommend having different containers.

### Deploy or upgrade

```bash
helm upgrade --install composio ./composio \
  -n composio \
  --create-namespace \
  -f values-override.yaml
```

### Verify configuration

Check that Apollo has the Azure environment variables:

```bash
kubectl exec -n composio deploy/composio-apollo -- env | grep -E "^(OBJECT_STORAGE_BACKEND|AZURE_CONNECTION_STRING|TEMP_STORAGE_NAMESPACE|PERMANENT_STORAGE_NAMESPACE)="
```

Expected variables:
- `OBJECT_STORAGE_BACKEND=azure`
- `AZURE_CONNECTION_STRING=...` (redact in logs)
- `TEMP_STORAGE_NAMESPACE=<your-temp-container>`
- `PERMANENT_STORAGE_NAMESPACE=<your-permanent-container>`

You can also inspect logs to ensure no authentication or container errors are reported:

```bash
kubectl logs -n composio deploy/composio-apollo --tail=200
```

### FAQ

- Do I need to use a secret for the connection string?  
  It is recommended. This chart supports setting the connection string via values; you may alternatively template a Secret and reference it through a custom value to avoid storing credentials in plain text files.

- Do other services need Azure Blob Storage?  
  Apollo is the primary consumer for object storage. Some toolkits that handle files rely on object storage; configure accordingly for your workload.


