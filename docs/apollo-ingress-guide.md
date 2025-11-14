# Apollo Backend Ingress Configuration Guide

## Overview

The Apollo backend ingress is now **cloud-agnostic**, automatically configuring appropriate settings based on your cloud provider.

## Quick Start

### For GCP (Current Setup)

```yaml
cloud: "gcp"

apollo:
  ingress:
    enabled: true
    class: gce
    host: "api.dev.composio.ema.co"
    staticIPName: "composio-ingress-global-ip"
    preSharedCert: backend-tls  # GCP-managed certificate
    path: /*
    pathType: ImplementationSpecific
```

### For Azure

```yaml
cloud: "azure"

apollo:
  ingress:
    enabled: true
    class: nginx
    host: "api.composio.example.com"
    path: /
    pathType: Prefix
    tls: true
    tlsSecretName: backend-tls  # Kubernetes TLS secret
    enable_ssl_server_snippet: true
```

## Path Configuration Explained

### Why Different Paths?

| Cloud | Path | PathType | Reason |
|-------|------|----------|--------|
| **GCP** | `/*` | `ImplementationSpecific` | GCE ingress controller requires glob pattern for proper routing |
| **Azure** | `/` | `Prefix` | Nginx ingress uses standard Kubernetes path matching |
| **AWS** | `/` | `Prefix` | ALB ingress uses standard Kubernetes path matching |

### When to Use Different Paths

#### Single Service (Recommended for Apollo)
- **Path**: `/*` (GCP) or `/` (Azure/AWS)
- **Use Case**: All traffic goes to one service
- **Example**: `api.composio.ema.co` → Apollo service

#### Multiple Services on Same Domain
- **Path**: `/apollo/*`, `/mercury/*`, etc.
- **Use Case**: Route different paths to different services
- **Example**: 
  - `api.composio.ema.co/apollo/*` → Apollo
  - `api.composio.ema.co/mercury/*` → Mercury

⚠️ **Warning**: Using sub-paths requires your application to handle the path prefix correctly!

## Certificate Management

### GCP (Pre-shared Certificate)

**Important**: When using GCP pre-shared certificates, the ingress will automatically enable HTTPS (port 443).

1. **Create certificate in GCP Console**:
   ```bash
   gcloud compute ssl-certificates create backend-tls \
     --domains=api.dev.composio.ema.co \
     --global
   ```

2. **Verify certificate is ACTIVE**:
   ```bash
   gcloud compute ssl-certificates describe backend-tls --global
   ```

3. **Reference in values**:
   ```yaml
   preSharedCert: backend-tls  # Certificate managed in GCP, enables port 443
   ```

**How it works**: 
- The `preSharedCert` annotation tells GCP which certificate to use
- The ingress template automatically adds a `tls` section to enable port 443
- No Kubernetes secret needed - GCP manages the certificate

### Azure/AWS (Kubernetes TLS Secret)

1. **Create Kubernetes secret**:
   ```bash
   kubectl create secret tls backend-tls \
     --cert=/path/to/cert.crt \
     --key=/path/to/cert.key \
     -n composio
   ```

2. **Reference in values**:
   ```yaml
   tls: true
   tlsSecretName: backend-tls
   ```

## Static IP Configuration

### GCP

1. **Reserve static IP**:
   ```bash
   # Global (for gce class)
   gcloud compute addresses create composio-ingress-global-ip --global
   
   # Regional (for gce-internal class)
   gcloud compute addresses create composio-ingress-regional-ip --region=us-central1
   ```

2. **Get IP address**:
   ```bash
   gcloud compute addresses describe composio-ingress-global-ip --global
   ```

3. **Use in values**:
   ```yaml
   staticIPName: "composio-ingress-global-ip"
   ```

### Azure

Azure doesn't use named IPs in ingress annotations. The Load Balancer service gets the IP automatically.

## Complete Examples

### Example 1: GCP Production

```yaml
cloud: "gcp"

apollo:
  ingress:
    enabled: true
    class: gce
    host: "api.composio.com"
    staticIPName: "prod-composio-global-ip"
    preSharedCert: prod-backend-ssl
    path: /*
    pathType: ImplementationSpecific
```

**DNS Setup**: `api.composio.com` A record → IP of `prod-composio-global-ip`

### Example 2: Azure Production

```yaml
cloud: "azure"

apollo:
  ingress:
    enabled: true
    class: nginx
    host: "api.composio.com"
    path: /
    pathType: Prefix
    tls: true
    tlsSecretName: prod-backend-tls
    enable_ssl_server_snippet: true
```

**DNS Setup**: `api.composio.com` A record → Load Balancer IP (get from `kubectl get ingress`)

## Troubleshooting

### Issue: 404 Not Found on GCP

**Cause**: Using `/` instead of `/*` with GCE ingress  
**Solution**: Change `path: /*` in values.yaml

### Issue: 502 Bad Gateway

**Cause**: Service port mismatch  
**Solution**: Verify Apollo service is running on port 9900

### Issue: Certificate not working on GCP

**Cause**: Pre-shared cert doesn't exist or wrong name  
**Solution**: 
```bash
# List certificates
gcloud compute ssl-certificates list

# Verify cert is ACTIVE and has correct domain
gcloud compute ssl-certificates describe backend-tls --global
```

### Issue: SSL redirect not working on Azure

**Cause**: Missing nginx annotations  
**Solution**: Ensure `cloud: "azure"` is set in values.yaml

## Migration Guide

### From Old Format to New Format

**Old (manual annotations)**:
```yaml
apollo:
  ingress:
    enabled: true
    className: "gce"
    annotations:
      kubernetes.io/ingress.class: "gce"
      kubernetes.io/ingress.global-static-ip-name: "my-ip"
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

**New (cloud-aware)**:
```yaml
cloud: "gcp"
apollo:
  ingress:
    enabled: true
    class: gce
    staticIPName: "my-ip"
```

## Next Steps

1. Set `cloud` variable based on your environment
2. Configure ingress values for your cloud
3. Deploy: `helm upgrade --install composio ./composio -n composio -f dev.values.yaml`
4. Verify: `kubectl get ingress -n composio`
5. Check DNS resolves to correct IP
6. Test: `curl https://api.dev.composio.ema.co/api/healthz`

